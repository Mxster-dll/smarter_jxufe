import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';

/// 入馆教育调试屏：验证 CAS→tsgxs 会话链，并把登录后的关键页面
/// dump 到本地 %TEMP%（供逆向接口结构）。正式 UI 逆向后替换。
class TsgxsScreen extends ConsumerStatefulWidget {
  const TsgxsScreen({super.key});

  @override
  ConsumerState<TsgxsScreen> createState() => _TsgxsScreenState();
}

class _TsgxsScreenState extends ConsumerState<TsgxsScreen> {
  final List<String> _logs = [];
  bool _busy = false;
  String _account = '';

  @override
  void initState() {
    super.initState();
    _account = ref.read(currentAccountProvider);
    _log('账号: ${_account.isEmpty ? '(未登录)' : _account}');
  }

  void _log(String line) {
    setState(
      () => _logs.add(
        '${DateTime.now().hour.toString().padLeft(2, '0')}:'
        '${DateTime.now().minute.toString().padLeft(2, '0')}:'
        '${DateTime.now().second.toString().padLeft(2, '0')}  $line',
      ),
    );
  }

  Future<String> _dumpDir() async {
    final env = Platform.environment['TEMP'];
    final dir = (env == null || env.isEmpty) ? Directory.systemTemp.path : env;
    return dir;
  }

  Future<void> _save(String name, String content) async {
    final dir = await _dumpDir();
    final file = File('$dir\\$name');
    await file.writeAsString(content, flush: true);
    _log('已保存: $dir\\$name (${content.length} 字符)');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _log('错误: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ① 建立 tsgxs 会话(走 CAS 换证)，并记录逐跳链路。
  Future<void> _establishSession() => _run(() async {
    final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
    final trace = <String>[];
    _log('开始换取 tsgxs 会话(TGC → ticket → casapi → tsgxs)…');
    final cookie = await repo.refreshSessionCookie(_account, trace: trace);
    for (final line in trace) {
      _log(line);
    }
    _log(
      '会话 Cookie 获取成功: '
      '${cookie.length > 48 ? '${cookie.substring(0, 48)}…' : cookie}',
    );
  });

  /// ② 抓取 /Web/User 页面结构(跟随 302 与 JS stub)。
  Future<void> _dumpUserPage() => _run(() async {
    final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
    final cookie = await repo.getSessionCookie(_account);
    if (cookie.isEmpty) {
      _log('尚无会话 Cookie，请先执行「① 建立会话」');
      return;
    }
    final dio = ref.read(tsgxsDioProvider);
    var url = '/Web/User';
    var html = '';
    for (var hop = 0; hop < 5; hop++) {
      final resp = await dio.get(
        url,
        options: Options(
          headers: {'Cookie': cookie},
          followRedirects: false,
          validateStatus: (s) => true,
        ),
      );
      final status = resp.statusCode ?? 0;
      final body = resp.data?.toString() ?? '';
      _log('GET $url -> $status (len=${body.length})');
      if (status >= 300 && status < 400) {
        final loc = resp.headers.value('location') ?? '';
        _log('   302 -> $loc');
        url = Uri.parse('http://tsgxs.jxufe.cn').resolve(loc).toString();
        continue;
      }
      if (body.contains('已在别处登录') || body.contains('被迫下线')) {
        _log('!! 账号已在别处登录,本会话被顶下线(单点登录)');
        return;
      }
      final js = RegExp(
        r"""location\.href\s*=\s*['"]([^'"]+)['"]""",
        caseSensitive: false,
      ).firstMatch(body)?.group(1);
      if (js != null && body.length < 400) {
        _log('   JS跳转 -> $js');
        url = Uri.parse('http://tsgxs.jxufe.cn').resolve(js).toString();
        continue;
      }
      html = body;
      break;
    }
    if (html.isEmpty) {
      _log('未取到内容页');
      return;
    }
    await _save('_tsgxs_dump_user.html', html);
    final title = RegExp(
      r'<title>(.*?)</title>',
      dotAll: true,
    ).firstMatch(html)?.group(1)?.trim();
    _log('页面标题: ${title ?? '(无)'}');
    final chapterLinks = _chapterLinks(html);
    // 首页标题模板固定为“登录”,但登录后页含头像/个人中心/退出与章节入口,
    // 故以章节入口为准判断是否已进入闯关首页。
    _log(
      chapterLinks.isNotEmpty
          ? '登录形态 OK(已进入闯关首页,${chapterLinks.length} 个章节)'
          : '!! 未发现章节入口，会话可能未生效',
    );
    _log('章节链接 ${chapterLinks.length} 个:');
    for (final l in chapterLinks.take(12)) {
      _log('   $l');
    }
  });

  /// ③ 抓取全部章节学习页。
  Future<void> _dumpChapters() => _run(() async {
    final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
    final cookie = await repo.getSessionCookie(_account);
    if (cookie.isEmpty) {
      _log('尚无会话 Cookie，请先执行「① 建立会话」');
      return;
    }
    final dio = ref.read(tsgxsDioProvider);
    final dir = await _dumpDir();
    final userFile = File('$dir\\_tsgxs_dump_user.html');
    if (!await userFile.exists()) {
      _log('缺少 _tsgxs_dump_user.html，请先执行「② 抓 User 页」');
      return;
    }
    final html = await userFile.readAsString();
    final links = _chapterLinks(html);
    _log('开始抓取 ${links.length} 个章节页…');
    var n = 0;
    for (final link in links) {
      final resp = await dio.get(
        link,
        options: Options(
          headers: {'Cookie': cookie},
          followRedirects: false,
          validateStatus: (s) => true,
        ),
      );
      final status = resp.statusCode ?? 0;
      final body = resp.data?.toString() ?? '';
      if (status >= 300 && status < 400) {
        _log('[$n] $status -> ${resp.headers.value('location')}');
        continue;
      }
      await _save('_tsgxs_dump_chapter_$n.html', body);
      final title = RegExp(
        r'<title>(.*?)</title>',
        dotAll: true,
      ).firstMatch(body)?.group(1)?.trim();
      final exam = body.contains('Exam') || body.contains('考试');
      _log(
        '[$n] ${title ?? '?'} len=${body.length}'
        '${exam ? ' [含考试线索]' : ''}',
      );
      n++;
    }
    _log('章节抓取完成');
  });

  /// ④ 注销 tsgxs 旧登录态后重建会话(用于验证单点登录冲突)。
  Future<void> _logoutAndRebuild() => _run(() async {
    final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
    final dio = ref.read(tsgxsDioProvider);
    final old = await repo.getSessionCookie(_account);
    if (old.isNotEmpty) {
      final resp = await dio.get(
        '/web/user/Logout',
        options: Options(
          headers: {'Cookie': old},
          followRedirects: false,
          validateStatus: (s) => true,
        ),
      );
      _log(
        '注销 /web/user/Logout -> ${resp.statusCode} '
        '${resp.headers.value('location') ?? ''}',
      );
    } else {
      _log('本地无会话 Cookie');
    }
    await repo.clearSessionCookie(_account);
    _log('已清本地会话缓存，重新建立…');
    final trace = <String>[];
    final cookie = await repo.refreshSessionCookie(_account, trace: trace);
    for (final line in trace) {
      _log(line);
    }
    _log('新会话: ${cookie.length > 60 ? '${cookie.substring(0, 60)}…' : cookie}');
    await _dumpUserPage();
  });

  /// ⑤ 进入闯关首页:必要时先 POST /Web/User/SelectTheme 选主题(角色)。
  ///
  /// 登录后 /Web/User 页面标题仍为“登录”,但其内容已是“点击进入个人中心 +
  /// 选择一个角色参加知识闯关”,说明学校身份已绑定,只差选主题一步。
  Future<void> _enterIndex() => _run(() async {
    final repo = await ref.read(tsgxsAuthRepositoryProvider.future);
    var cookie = await repo.getSessionCookie(_account);
    if (cookie.isEmpty) {
      _log('尚无会话 Cookie，请先执行「① 建立会话」');
      return;
    }
    final dio = ref.read(tsgxsDioProvider);
    final uid = RegExp(
      r'(?:^|;\s*)uid=([^;]+)',
    ).firstMatch(cookie)?.group(1)?.trim();
    _log('uid=$uid');

    Future<void> fetchIndex(String label, String ck) async {
      final resp = await dio.get(
        '/web/user/Index',
        options: Options(
          headers: {'Cookie': ck},
          followRedirects: false,
          validateStatus: (s) => true,
        ),
      );
      final status = resp.statusCode ?? 0;
      final body = resp.data?.toString() ?? '';
      final loc = resp.headers.value('location');
      final title = RegExp(
        r'<title>(.*?)</title>',
        dotAll: true,
      ).firstMatch(body)?.group(1)?.trim();
      _log(
        '$label GET /web/user/Index -> $status len=${body.length}'
        '${loc != null && loc.isNotEmpty ? ' -> $loc' : ''}'
        ' title=${title ?? '(无)'}',
      );
      final newOnes = resp.headers['set-cookie'];
      if (newOnes != null && newOnes.isNotEmpty) {
        _log(
          '   Set-Cookie: ${newOnes.map((c) => c.split(';').first).join(',')}',
        );
      }
      if (body.isNotEmpty && status == 200 && body.length > 400) {
        await _save('_tsgxs_dump_index.html', body);
      }
    }

    await fetchIndex('进首页:', cookie);
    if (uid == null || uid.isEmpty) {
      _log('Cookie 中无 uid，无法选主题');
      return;
    }
    // 选主题(角色):tid 取登录页当前默认显示的书生版。此调用即“登录”本体，
    // 响应 Success=1「登录成功」，并可能下发新的会话 Cookie。
    const tid = '5d037bb3-12c5-4554-a3c2-d128766dd025';
    final resp = await dio.post(
      '/Web/User/SelectTheme',
      data: {'uid': uid, 'tid': tid},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Cookie': cookie},
        followRedirects: false,
        validateStatus: (s) => true,
      ),
    );
    _log(
      'POST SelectTheme -> ${resp.statusCode} '
      '${(resp.data?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim()}',
    );
    final setCookies = resp.headers['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      final names = setCookies.map((c) => c.split(';').first).join(',');
      _log('   Set-Cookie: $names');
      cookie = _mergeCookieString(cookie, setCookies);
    }
    await repo.updateSessionCookie(_account, cookie);
    _log('已持久化最新会话 Cookie');
    await fetchIndex('选主题后:', cookie);
  });

  /// 把 Set-Cookie 列表合并进 Cookie 串(同名覆盖)。
  static String _mergeCookieString(String acc, List<String> setCookies) {
    final map = <String, String>{};
    for (final seg in acc.split(';')) {
      final s = seg.trim();
      if (s.isEmpty) continue;
      final eq = s.indexOf('=');
      if (eq > 0) map[s.substring(0, eq).trim()] = s.substring(eq + 1);
    }
    for (final raw in setCookies) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) map[first.substring(0, eq).trim()] = first.substring(eq + 1);
    }
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  List<String> _chapterLinks(String html) {
    final seen = <String>{};
    final re = RegExp(
      r'href="(/Web/Chapter/Index/[a-f0-9-]{36}\?tid=[a-f0-9-]{36})"',
    );
    for (final m in re.allMatches(html)) {
      seen.add(m.group(1)!);
    }
    return seen.toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('新生入馆教育 · 调试'),
        actions: [
          IconButton(
            tooltip: '清空日志',
            onPressed: () => setState(_logs.clear),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.science_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '验证登录链并抓取页面结构(逆向阶段)',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _establishSession,
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('① 建立会话'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _dumpUserPage,
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('② 抓 User 页'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _dumpChapters,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('③ 抓全部章节'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _logoutAndRebuild,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('④ 注销并重建'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _enterIndex,
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('⑤ 进闯关首页'),
                ),
              ],
            ),
          ),
          const Divider(height: 12),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SelectableText(
                        _logs[i],
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'Cascadia Code',
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
