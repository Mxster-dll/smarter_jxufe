/// 跨模块「地基件」的唯一性守卫（2026-09-20 架构审查后立）。
///
/// 背景：审查发现同一件事在本仓被抄了 8 份 —— 教务会话失效判据有 7 种写法、
/// 自动刷新闸门有 5 套口径、`Cookie` 处理在 8 个数据源里逐字重复。地基件收敛到
/// `lib/core/` 之后，**必须有守卫拦住「下一个页面又自己写一份」**，否则半年后
/// 又会退化成八份。
///
/// 这里只钉「唯一性」这类静态事实（纯文本检索），不碰行为 —— 行为守卫在各自的
/// 模块测试里（`test/cxstar_auto_refresh_test.dart` / `test/chaoxing_*_test.dart`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/core/network/cas_redirect.dart';
import 'package:smarter_jxufe/core/network/sso_login_page.dart';

/// `lib/` 下所有 `.dart` 文件：`posix 相对路径 → 源码`。
Map<String, String> _sources() {
  final out = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    out[entity.path.replaceAll(r'\', '/')] = entity.readAsStringSync();
  }
  return out;
}

/// 含 [needle] 字面量的文件路径（按路径排序，便于断言整份清单）。
List<String> _hits(Map<String, String> sources, String needle) {
  final out = [
    for (final e in sources.entries)
      if (e.value.contains(needle)) e.key,
  ]..sort();
  return out;
}

/// 同 [_hits]，但**跳过 `//` 注释行**。
///
/// 有些守卫要抓的是「代码里又写了一份旧判据」，而解释这段历史的文档注释里
/// 必然会引用旧写法（否则后人不知道为什么被禁）—— 注释不该触发守卫。
List<String> _codeHits(Map<String, String> sources, String needle) {
  final out = <String>[];
  for (final e in sources.entries) {
    final hit = e.value.split('\n').any((line) {
      if (line.trimLeft().startsWith('//')) return false;
      return line.contains(needle);
    });
    if (hit) out.add(e.key);
  }
  out.sort();
  return out;
}

/// 抠出 `class <name> … { … }` 的正文（花括号配对）。
///
/// 用于「**只看这个类自己那一份**」的守卫：`final String message;` 这类 needle 在
/// 全文里会命中界面/领域模型（合法用法），只有逐类抠块才能问出「这个异常类有没有
/// 又自己写一份」。
String? _classBlock(String src, String name) {
  final head = RegExp(
    '^(?:abstract )?class $name\\b[^\\n]*\\{',
    multiLine: true,
  ).firstMatch(src);
  if (head == null) return null;
  var depth = 0;
  for (var i = src.indexOf('{', head.end - 1); i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(head.start, i + 1);
    }
  }
  return null;
}

/// 数一行里 needle 出现几次，**跳过 `//` 注释行**（理由同 [_codeHits]）。
int _countCode(String src, String needle) {
  var n = 0;
  for (final line in src.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    n += needle.allMatches(line).length;
  }
  return n;
}

/// 跨 feature import 图：`feature → {它 import 的其它 feature}`。
///
/// 只认 `package:smarter_jxufe/features/<x>/…` 指令（同 feature 的自引用不计）。
Map<String, Set<String>> _featureEdges(Map<String, String> sources) {
  final re = RegExp(
    r"^import 'package:smarter_jxufe/features/([^/']+)/",
    multiLine: true,
  );
  final out = <String, Set<String>>{};
  for (final e in sources.entries) {
    final parts = e.key.split('/'); // lib/features/<x>/…
    if (parts.length < 3 || parts[1] != 'features') continue;
    final owner = parts[2];
    for (final m in re.allMatches(e.value)) {
      final other = m.group(1)!;
      if (other == owner) continue;
      (out[owner] ??= <String>{}).add(other);
    }
  }
  return out;
}

/// 双向依赖环（a→b 且 b→a），返回去重排序后的 `'a⇄b'` 清单。
List<String> _featureCycles(Map<String, Set<String>> edges) {
  final out = <String>{};
  for (final a in edges.keys) {
    for (final b in edges[a]!) {
      if (edges[b]?.contains(a) ?? false) {
        out.add(a.compareTo(b) < 0 ? '$a⇄$b' : '$b⇄$a');
      }
    }
  }
  return out.toList()..sort();
}

/// `opener(` … 配对 `)` 的块正文（**括号配平**扫描）。
///
/// 正则做不到这件事：`Border.all(color: AppColors.hairline(context, 0.6))` 这种嵌套调用
/// 会破坏 `[^()]*` 式子 —— 首版守卫因此漏报，实测 `materials_screen.dart` 里就有 4 处。
List<String> _parenBlocks(String src, String opener) {
  final out = <String>[];
  var i = 0;
  while (true) {
    final at = src.indexOf(opener, i);
    if (at < 0) break;
    var j = at + opener.length; // 指向 '('
    var depth = 0;
    for (; j < src.length; j++) {
      if (src[j] == '(') {
        depth++;
      } else if (src[j] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.add(src.substring(at + opener.length + 1, j));
    i = j + 1;
  }
  return out;
}

/// `SnackBar(` 构造的实参正文（**要求 `SnackBar` 前面不是标识符字符 / 点**）。
///
/// `_parenBlocks(src, 'SnackBar(')` 会被 `showSnackBar(` 骗到（子串命中，而它的实参
/// 里当然没有 `persist:`）—— 这里的负向后顾把它挡掉。字符串字面量整体跳过，
/// 免得文案里的半角括号破坏配平。
List<String> _snackBarBlocks(String src) {
  final out = <String>[];
  for (final m in RegExp(r'(?<![A-Za-z0-9_.])SnackBar\(').allMatches(src)) {
    var depth = 1;
    var j = m.end;
    var inString = false;
    var quote = '';
    for (; j < src.length; j++) {
      final c = src[j];
      if (inString) {
        if (c == r'\') {
          j++;
        } else if (c == quote) {
          inString = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inString = true;
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.add(src.substring(m.end, j));
  }
  return out;
}

void main() {
  final sources = _sources();

  group('教务会话失效：一份判据 + 一个异常类型', () {
    test('判据 `jwSessionExpired` 全仓只有一处定义', () {
      expect(
        _hits(sources, 'bool jwSessionExpired('),
        ['lib/core/network/jw_page_decoding.dart'],
        reason: '公共查询曾有一份逐字重复的 isExpiredSession，别再长回来',
      );
    });

    test('异常类型 `JwSessionExpiredException` 只有一处定义', () {
      expect(
        _hits(sources, 'class JwSessionExpiredException'),
        ['lib/core/network/jw_page_decoding.dart'],
      );
    });

    test('数据层 / core 不许拿文案当类型判失效', () {
      final offenders = <String>[];
      for (final e in sources.entries) {
        final path = e.key;
        if (path == 'lib/core/network/jw_page_decoding.dart') continue; // 判据本体
        final isDataLayer =
            path.startsWith('lib/core/') || path.contains('/data/');
        if (!isDataLayer) continue; // 界面层按文案给出提示语是允许的
        if (e.value.contains("contains('凭证已失效')") ||
            e.value.contains("contains('请重新登录')")) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '改用 jwSessionExpired(html) 判、isJwSessionExpiredError(e) 判异常类型',
      );
    });
  });

  group('自动刷新闸门：只有一份机制', () {
    test('`allowsAutoRefresh` 只在 core 定义（各模块只准读）', () {
      expect(
        _hits(sources, 'bool get allowsAutoRefresh'),
        ['lib/core/navigation/refresh_gate.dart'],
        reason: '第二个模块需要节流时，继承 RefreshGate，别复制一份闸门类',
      );
    });

    test('畅想之星 / 学习通的闸门都继承 RefreshGate', () {
      expect(
        sources['lib/features/cxstar/data/providers/'
            'cxstar_refresh_gate_provider.dart'],
        contains('class CxstarRefreshGate extends RefreshGate'),
      );
      expect(
        sources['lib/features/chaoxing/data/chaoxing_gate.dart'],
        contains('class ChaoxingRefreshGate extends RefreshGate'),
      );
    });
  });

  group('SSO 登录页判据：一份实现', () {
    test('`ssoLoginPage` / `ssoLoginPageBytes` 只有 core 一处定义', () {
      expect(
        _hits(sources, 'bool ssoLoginPage('),
        ['lib/core/network/sso_login_page.dart'],
      );
      expect(
        _hits(sources, 'bool ssoLoginPageBytes('),
        ['lib/core/network/sso_login_page.dart'],
      );
    });

    test('综合服务里不再有第二份登录页判据', () {
      final offenders = [
        for (final e in sources.entries)
          if (e.key.startsWith('lib/features/comprehensive_service/') &&
              (e.value.contains("contains('authFailure')") ||
                  e.value.contains('_looksLikeLoginRedirect')))
            e.key,
      ];
      expect(
        offenders,
        isEmpty,
        reason: '这 4 份曾逐字重复（竞赛 / 志愿 / 第二课堂 / 蛟湖阅读）：'
            '统一改用 lib/core/network/sso_login_page.dart 的 ssoLoginPage(body)',
      );
    });

    test('判据只对「以 HTML 开头」的正文生效', () {
      // 正向：三个真实失效形态各一。
      expect(ssoLoginPage('<!DOCTYPE html><html><title>登录</title>'), isTrue);
      expect(ssoLoginPage('  <html>…authFailure…</html>'), isTrue);
      expect(ssoLoginPage('<html><script>location="/sso/login"</script>'), isTrue);
      // 反向（关键安全属性）：业务正文里恰好提到 /sso/login 不算失效。
      expect(ssoLoginPage('{"url":"/sso/login","ok":true}'), isFalse);
      expect(ssoLoginPage('<div>去 /sso/login 看看</div>'), isFalse);
      // 二进制：真登记表是 OOXML 压缩包，绝不能判成登录页。
      expect(ssoLoginPageBytes([0x50, 0x4B, 0x03, 0x04, 0x00]), isFalse);
    });
  });

  group('CAS 登录页判据（判 URL）：一份实现', () {
    test('`isCasLoginRedirect` 只有 core 一处定义', () {
      expect(
        _hits(sources, 'bool isCasLoginRedirect(String? url)'),
        ['lib/core/network/cas_redirect.dart'],
        reason: '它曾同时存在于 auth 数据源，另有 ssp / read_credit 两份宽松版',
      );
    });

    test('auth 数据源改为引用 core，不再内联 path 判定', () {
      final src =
          sources['lib/features/auth/data/datasources/auth_remote_datasource.dart'];
      expect(src, isNotNull);
      expect(
        src!.contains(
          "import 'package:smarter_jxufe/core/network/cas_redirect.dart';",
        ),
        isTrue,
      );
      expect(
        src.contains("final path = Uri.tryParse(url)?.path ?? '';"),
        isFalse,
        reason: '判定本体已收口，文件里只许调 isCasLoginRedirect',
      );
    });

    test('全仓不再有宽松的 `contains(\'cas/login\')` 版', () {
      expect(
        _codeHits(sources, "contains('cas/login')"),
        isEmpty,
        reason: '宽松版会把 /cas/loginfo 与「查询串里恰好带 /cas/login」误判成会话失效',
      );
      for (final path in const [
        'lib/features/comprehensive_service/data/datasource/'
            'ssp_auth_remote_datasource.dart',
        'lib/features/read_credit/data/datasources/'
            'read_credit_api_remote_datasource.dart',
      ]) {
        expect(sources[path], contains('isCasLoginRedirect('), reason: path);
      }
    });

    test('判据语义：绝对 / 相对 / 路径参数 / 反例', () {
      expect(
        isCasLoginRedirect('https://ssl.jxufe.edu.cn/cas/login?service=x'),
        isTrue,
      );
      // 路径参数（真实登录页带 `;jsessionid=`）。
      expect(
        isCasLoginRedirect('https://ssl.jxufe.edu.cn/cas/login;jsessionid=ABC'),
        isTrue,
      );
      // 相对写法：ssp 平台实测回跳就是 `cas/login?...`（无前导斜杠）。
      expect(isCasLoginRedirect('cas/login?service=x'), isTrue);
      expect(isCasLoginRedirect('/cas/login'), isTrue);
      // 反例：末段不同、查询串里带 /cas/login。
      expect(isCasLoginRedirect('https://ssl.jxufe.edu.cn/cas/loginfo'), isFalse);
      expect(isCasLoginRedirect('https://ssl.jxufe.edu.cn/login'), isFalse);
      expect(isCasLoginRedirect('https://x/error?from=/cas/login'), isFalse);
      expect(isCasLoginRedirect(null), isFalse);
      expect(isCasLoginRedirect(''), isFalse);
    });
  });

  group('被顶下线判据：同一 feature 内只有一份', () {
    test('`已在别处登录` / `被迫下线` 的判定只在 tsgxs 会话数据源', () {
      const owner =
          'lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
      expect(_hits(sources, "contains('已在别处登录')"), [owner]);
      expect(_hits(sources, "contains('被迫下线')"), [owner]);
      expect(
        sources['lib/features/library_edu/data/tsgxs_api_remote_datasource.dart'],
        contains('TsgxsAuthRemoteDataSource.isKickedOffPage('),
        reason: '同 feature 的第二份内联判定已删除（文案是超星私有的，刻意不进 core）',
      );
    });
  });

  group('「返回即刷新」只有一条路径', () {
    test('学习通主页不挂 subscribeRoute，只留 push().then(刷新)', () {
      final src =
          sources['lib/features/chaoxing/presentation/chaoxing_screen.dart'];
      expect(src, isNotNull);
      expect(
        src!.contains('_autoRefresh.subscribeRoute'),
        isFalse,
        reason: '弹窗也是路由：挂 subscribeRoute 会让关弹窗也白刷一次（一次 ~70 请求）',
      );
      expect(
        src.contains('.then((_) => _autoRefreshAll())'),
        isTrue,
        reason: '子页面返回仍必须刷新 —— 撤掉的只是重复的那一条路径',
      );
    });
  });

  group('Cookie 罐：按语义选一个，别再写第 9 份', () {
    const owner = 'lib/core/network/cookie_jar.dart';

    test('两个罐都只在 core 里定义', () {
      expect(_hits(sources, 'class SessionCookieJar'), [owner]);
      expect(_hits(sources, 'class HostCookieJar'), [owner]);
    });

    test('feature 里不得再出现私有 Cookie 三件套（含 dzj 那个同名助手）', () {
      for (final needle in const [
        '_cookieHeader(',
        '_cookieNamesOf(',
        '_storeCookies(',
        '_cookieValue(',
      ]) {
        expect(
          _codeHits(sources, needle),
          isEmpty,
          reason: '又抄了一份 $needle —— 用 `HostCookieJar`（按 host 分桶）或 '
              '`SessionCookieJar`（认 Domain），见 lib/core/network/cookie_jar.dart',
        );
      }
    });

    test('不得再手写「朴素桶」：Map<String, Map<String, String>> jar', () {
      expect(
        _codeHits(sources, 'Map<String, Map<String, String>> jar'),
        isEmpty,
        reason: '桶类型必须来自 core（`HostCookieJar`），别在数据源里现搓一个',
      );
    });

    test('四个已迁移站点都从 core 取罐', () {
      for (final path in const [
        'lib/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart',
        'lib/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart',
        'lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart',
        'lib/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart',
      ]) {
        final src = sources[path];
        expect(src, isNotNull, reason: '$path 不存在了？守卫清单要跟着改');
        expect(src, contains('core/network/cookie_jar.dart'), reason: path);
        expect(src, contains('HostCookieJar'), reason: path);
      }
    });

    test('trace 打 Set-Cookie 一律走 setCookieNames（防把凭据写进日志）', () {
      expect(
        _codeHits(sources, "=> c.split(';').first)"),
        isEmpty,
        reason: '手写 `c.split(\';\').first` 打出的是 `name=value` —— 凭据进日志。'
            '用 `setCookieNames(...)`（只出名字），占位文案传 `empty: \'(无)\'`',
      );
    });
  });

  group('异常体系：一个基类 + 一个「会话失效」标记', () {
    test('全仓只有 core 的基类允许 `implements Exception`', () {
      expect(
        _codeHits(sources, 'implements Exception'),
        ['lib/core/errors/app_exception.dart'],
        reason: '站点异常一律 `extends AppException`（会话失效用 `SessionExpiredException`）。'
            '自己 `implements Exception` 就丢掉了 message/toString 契约，'
            '界面层又只能回去 `e.toString().contains(...)` 拿文案当类型',
      );
    });

    test('每个站点异常类自身不再重复 message 字段与 toString()', () {
      // ⚠ 不能用全文 contains：`final String message;` 在界面/领域模型里是合法的
      //（如 `TsgxsExamStatus`）—— 必须逐类抠块，只看异常类自己那一份。
      const migrated = {
        'JwSessionExpiredException': 'lib/core/network/jw_page_decoding.dart',
        'TgcExpiredException':
            'lib/features/auth/data/datasources/auth_remote_datasource.dart',
        'ChaoxingSessionException': 'lib/features/chaoxing/data/chaoxing_session.dart',
        'ChaoxingSessionExpiredException':
            'lib/features/chaoxing/data/chaoxing_session.dart',
        'SspSessionExpiredException':
            'lib/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart',
        'CxstarSessionException':
            'lib/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart',
        'CxstarApiException': 'lib/features/cxstar/domain/cxstar_models.dart',
        'DzjApiException':
            'lib/features/data_center/data/datasource/dzj_api_support.dart',
        'DzjSessionExpiredException':
            'lib/features/data_center/data/datasource/dzj_auth_remote_datasource.dart',
        'ElectricityApiException':
            'lib/features/electricity/data/models/electricity_models.dart',
        'SelectionSessionExpired':
            'lib/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart',
        'TranscriptApiException':
            'lib/features/ims/grades/data/datasources/transcript_remote_datasource.dart',
        'LeaveApiException':
            'lib/features/leave/data/datasources/leave_remote_datasource.dart',
        'TsgxsApiException':
            'lib/features/library_edu/data/tsgxs_api_remote_datasource.dart',
        'TsgxsAccessDeniedException':
            'lib/features/library_edu/data/tsgxs_api_remote_datasource.dart',
        'TsgxsChapterPassedException':
            'lib/features/library_edu/data/tsgxs_api_remote_datasource.dart',
        'TsgxsSessionExpiredException':
            'lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart',
        'LibspSessionException':
            'lib/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart',
        'LibspSessionExpiredException':
            'lib/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart',
        'LibspWriteRejectedException':
            'lib/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart',
        'MyMailApiException':
            'lib/features/my_mail/data/datasources/my_mail_remote_datasource.dart',
        'NetFeeApiException':
            'lib/features/net_fee/data/datasources/net_fee_remote_datasource.dart',
        'NetworkServiceException':
            'lib/features/network_service/data/datasources/network_service_remote_datasource.dart',
        'ReadCreditApiException':
            'lib/features/read_credit/data/datasources/read_credit_api_remote_datasource.dart',
        'ReadCreditSessionExpiredException':
            'lib/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart',
        'TiceRequestException':
            'lib/features/tice/data/tice_remote_datasource.dart',
        'ZcFileException': 'lib/features/zongce/data/zc_store.dart',
      };
      const forbidden = [
        'implements Exception',
        'final String message;',
        'String toString() => message;',
      ];
      migrated.forEach((name, path) {
        final block = _classBlock(sources[path] ?? '', name);
        expect(block, isNotNull, reason: '$name 不见了？守卫清单要跟着改（$path）');
        for (final bad in forbidden) {
          expect(block, isNot(contains(bad)), reason: '$name 又自己写了一份 `$bad`');
        }
      });
    });

    test('Failure 的 8 个子类不再遮蔽基类字段（改走 super.message）', () {
      const path = 'lib/core/errors/failures.dart';
      for (final name in const [
        'UnknownFailure',
        'NetworkFailure',
        'ServerFailure',
        'CacheFailure',
        'ParseFailure',
        'MappingFailure',
        'NotFoundFailure',
        'InvalidCredentialsFailure',
      ]) {
        final block = _classBlock(sources[path]!, name);
        expect(block, isNotNull, reason: name);
        expect(block, isNot(contains('final String? message;')), reason: name);
        expect(block, contains('super.message'), reason: '$name 必须转发给基类字段');
      }
    });

    test('「异常 → 上屏文案」只有一份实现（dzj 私有的那份已上提）', () {
      expect(
        _codeHits(sources, 'String dzjFriendlyError('),
        isEmpty,
        reason: '数据中台曾私有实现一份（只在数据中台与 AA 用），已上提为 '
            '`friendlyErrorText`（lib/core/errors/app_exception.dart）',
      );
      expect(
        _hits(sources, 'String friendlyErrorText('),
        ['lib/core/errors/app_exception.dart'],
      );
      // 2026-09-20 前这个手法在 lib 里手写了 10 处（dashboard / transcript ×2 / leave ×2 /
      // my_mail / network_service ×3 / net_fee）—— 一律走 friendlyErrorText。
      for (final needle in const [
        ".replaceFirst('Exception: ', '')",
        ".replaceAll('Exception: ', '')",
      ]) {
        expect(
          _codeHits(sources, needle),
          isEmpty,
          reason: '又手写了一份「剥 Exception: 前缀」—— 用 friendlyErrorText(e)',
        );
      }
    });

    test('裸 `throw Exception(`：全仓已清零（2026-09-20 · 只减不增 → 归零）', () {
      final offenders = <String, int>{};
      sources.forEach((path, src) {
        final n = _countCode(src, 'throw Exception(');
        if (n > 0) offenders[path] = n;
      });
      expect(
        offenders,
        isEmpty,
        reason: '裸 `throw Exception(` 的 `toString()` 带英文 `Exception: ` 前缀、又没有类型 '
            '可判 —— 一律换成站点自己的 `XxxException extends AppException`'
            '（台账见 docs/agents/33-横向地基件（跨模块唯一实现）.md §33.5.2）',
      );
    });

    test('29 个站点异常都已挂到 core 基类上', () {
      const migrated = [
        'lib/core/network/jw_page_decoding.dart',
        'lib/features/auth/data/datasources/auth_remote_datasource.dart',
        'lib/features/chaoxing/data/chaoxing_session.dart',
        'lib/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart',
        'lib/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart',
        'lib/features/cxstar/domain/cxstar_models.dart',
        // 2026-10-08：`DzjApiException` 随「低层收发」一起搬到了 `dzj_api_support.dart`
        //（数据源拆分第一阶段），台账跟着搬 —— 异常类在哪个文件，这一条就指哪儿。
        'lib/features/data_center/data/datasource/dzj_api_support.dart',
        'lib/features/data_center/data/datasource/dzj_auth_remote_datasource.dart',
        'lib/features/electricity/data/models/electricity_models.dart',
        'lib/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart',
        'lib/features/ims/grades/data/datasources/transcript_remote_datasource.dart',
        'lib/features/leave/data/datasources/leave_remote_datasource.dart',
        'lib/features/library_edu/data/tsgxs_api_remote_datasource.dart',
        'lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart',
        'lib/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart',
        'lib/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart',
        'lib/features/my_mail/data/datasources/my_mail_remote_datasource.dart',
        'lib/features/net_fee/data/datasources/net_fee_remote_datasource.dart',
        'lib/features/network_service/data/datasources/network_service_remote_datasource.dart',
        'lib/features/read_credit/data/datasources/read_credit_api_remote_datasource.dart',
        'lib/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart',
        'lib/features/tice/data/tice_remote_datasource.dart',
        'lib/features/zongce/data/zc_store.dart',
        // 2026-09-20 第三轮（`throw Exception(` 全清）新增的 6 个站点异常类。
        'lib/features/auth/data/auth_exception.dart',
        'lib/features/comprehensive_service/data/ssp_exception.dart',
        'lib/features/home_widget/data/home_widget_exception.dart',
        'lib/features/ims/data/ims_exception.dart',
        'lib/features/qr_login/data/qr_login_exception.dart',
        'lib/features/school_calendar/data/school_calendar_exception.dart',
      ];
      for (final path in migrated) {
        expect(
          sources[path],
          contains('core/errors/app_exception.dart'),
          reason: '$path 的异常类必须 import core 基类（新增站点照此）',
        );
      }
      // 抽查超类写法（族成员与非成员各一）
      expect(
        sources['lib/core/network/jw_page_decoding.dart'],
        contains('class JwSessionExpiredException extends SessionExpiredException'),
      );
      expect(
        sources['lib/features/chaoxing/data/chaoxing_session.dart'],
        contains('class ChaoxingSessionExpiredException extends ChaoxingSessionException'),
      );
    });

    test('★ 每个 `*Exception` 类的根都是 `AppException`（自维护，新增站点自动受管）', () {
      // 逐类抠「类名 → 超类名」。`AppException` 自己 = 全仓唯一允许 `implements Exception`。
      final declared = <String, String>{};
      sources.forEach((path, src) {
        if (path.startsWith('lib/old/')) return;
        final heads = RegExp(
          r'^(?:abstract\s+)?class\s+(\w*Exception\w*)([^{]*)\{',
          multiLine: true,
        ).allMatches(src);
        for (final m in heads) {
          final name = m.group(1)!;
          if (name == 'AppException') continue;
          declared[name] =
              RegExp(
                r'extends\s+([\w<>.]+)',
              ).firstMatch(m.group(2)!)?.group(1) ??
              '';
        }
      });
      expect(declared, isNotEmpty, reason: '一个异常类都没扫到 —— 正则或扫描口径坏了');

      final offenders = <String>[];
      declared.forEach((name, sup) {
        if (sup.isEmpty) {
          offenders.add('$name：没有 `extends`（裸 `implements Exception` 已禁）');
        } else if (sup != 'AppException' && !declared.containsKey(sup)) {
          offenders.add('$name extends $sup —— 而 $sup 不是本仓的异常类');
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '站点异常必须 `extends AppException`（或本仓另一个异常类，最终仍是它）—— '
            '否则 `friendlyErrorText` / `is SessionExpiredException` 这类**按类型**的分支'
            '会静默漏掉它（口径见 docs/agents/33-横向地基件（跨模块唯一实现）.md §33.5）',
      );
    });
  });

  group('三态组件：加载 / 空 / 错误只有一份实现（2026-09-20 · 架构审查 ⑤）', () {
    test('三个组件只在 `lib/design/app_states.dart` 定义', () {
      for (final name in const [
        'AppLoadingState',
        'AppErrorState',
        'AppEmptyState',
      ]) {
        expect(
          _hits(sources, 'class $name extends StatelessWidget'),
          ['lib/design/app_states.dart'],
          reason: '别再写第二个 `$name` —— 三态组件的口径就在 app_states.dart',
        );
      }
    });

    test('★ 裸的中心转圈已清零：`const Center(child: CircularProgressIndicator())` 不许再出现', () {
      expect(
        _codeHits(sources, 'const Center(child: CircularProgressIndicator())'),
        isEmpty,
        reason: '改用 `const AppLoadingState()`（自 2026-09-20 起 26 个文件 / 33 处已迁完）—— '
            '裸转圈没有统一尺寸，也没有「在等什么」的位置。'
            '⚠ 按钮里的行内小转圈（`SizedBox(width: 16, child: CircularProgressIndicator(…))`）'
            '不在此列，它本来就不该居中。',
      );
    });

    test('棘轮：手写的 `Center(child: CircularProgressIndicator…)` 与 `Text(\'重试\')` 只减不增', () {
      // 基线 = 2026-09-20 迁移后实测（迁移前分别是 7 / 39 个文件）。
      const maxSpinnerCenters = 7;
      const maxRetryTexts = 28;
      final spinnerCenters = _codeHits(
        sources,
        'Center(child: CircularProgressIndicator',
      ).length;
      final retryTexts = _codeHits(sources, "Text('重试')").length;
      expect(
        spinnerCenters,
        lessThanOrEqualTo(maxSpinnerCenters),
        reason: '新增页面又自己居中放了转圈 —— 用 `AppLoadingState`。'
            '（迁移完可以把这个上限继续调小，但**不许调大**）',
      );
      expect(
        retryTexts,
        lessThanOrEqualTo(maxRetryTexts),
        reason: '新增页面又自己写了「重试」按钮 —— 用 `AppErrorState(error: e, onRetry: …)`。'
            '（同上，只减不增）',
      );
    });

    test(r'错误态文案不许自己拼 `$e` / `error.toString()` 上屏', () {
      // 允许的例外：`AppErrorState` 内部走 friendlyErrorText；日志/trace 不受此限。
      final offenders = <String>[];
      for (final e in sources.entries) {
        final path = e.key;
        if (path == 'lib/design/app_states.dart') continue;
        for (final line in e.value.split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          final isOnScreen =
              line.contains('Text(') || line.contains('text:') || line.contains('body:');
          if (!isOnScreen) continue;
          if (line.contains(r"'$e'") || line.contains(r"'$error'")) {
            offenders.add('$path：${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '把裸异常直接印上屏会带出 `Exception: ` 英文前缀 —— '
            '错误文案的唯一出口是 `friendlyErrorText(e)`（`AppErrorState` 已经这么做了）',
      );
    });
  });

  group('换证循环：一份实现（2026-09-20 · 架构审查 ②）', () {
    /// 已经迁到 `walkCasRedirects` 的站点（键 = 路径，值 = 站点名，只为报错好读）。
    const migrated = {
      'lib/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart':
          '阅读学分',
      'lib/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart':
          '畅想之星',
      'lib/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart':
          '学习通',
      'lib/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart':
          '图书馆 libsp',
      'lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart':
          '入馆教育',
    };

    test('`walkCasRedirects` 全仓只有一处定义', () {
      expect(
        _hits(sources, 'Future<CasWalkOutcome<T>> walkCasRedirects<T>('),
        ['lib/core/network/cas_walk.dart'],
      );
    });

    test('`CasWalkSpec(` 只出现在 core 与「已迁移的站点」里', () {
      final hits = _hits(sources, 'CasWalkSpec(')..remove('lib/core/network/cas_walk.dart');
      expect(
        hits,
        unorderedEquals(migrated.keys),
        reason: '新增站点请直接调 `walkCasRedirects`，别自己再写一遍跳转循环；'
            '若某个站点**确实**不适合（见 §33.3 的反例表），把它登记在案而不是偷偷例外',
      );
    });

    test('每条已迁移的链都真的调了地基件（防「改回手写循环」）', () {
      for (final entry in migrated.entries) {
        final src = sources[entry.key];
        expect(src, isNotNull, reason: '${entry.key} 不见了？');
        expect(
          src,
          contains("import 'package:smarter_jxufe/core/network/cas_walk.dart';"),
          reason: '${entry.value} 链缺 cas_walk 的 import',
        );
        expect(
          src,
          contains('walkCasRedirects<'),
          reason: '${entry.value} 链必须走 walkCasRedirects（循环机制的唯一实现）',
        );
      }
    });

    test('棘轮：`for (var hop` 手写跳转循环只减不增', () {
      // 基线 2（都在 core 的 walker 之外，且都不是换证主链）：
      //   `lib/features/library_edu/data/tsgxs_auth_remote_datasource.dart` 的 `_warmUp`
      //     —— 跨域预热子协议（4 跳，换证主链已迁走）；
      //   `lib/features/chaoxing/data/chaoxing_http_client.dart` 的 `_follow`
      //     —— **业务请求**的跟跳（`followRedirects: true` + 5 跳上限），不是换证链。
      // `lib/core/network/cas_walk.dart` 自己那一条不计（它就是那个循环）。
      const maxHandRolledHopLoops = 2;
      final hits = _hits(sources, 'for (var hop')
        ..remove('lib/core/network/cas_walk.dart');
      expect(
        hits.length,
        lessThanOrEqualTo(maxHandRolledHopLoops),
        reason: '又有人手写「跟 3xx」循环了 —— 换证链一律用 `walkCasRedirects`。'
            '当前命中：$hits',
      );
    });
  });

  group('feature 依赖环与分层（2026-09-20 · 架构审查 ⑦）', () {
    test('★ 双向依赖环只减不增（棘轮：当前 14）', () {
      // 审计起点 21 条。已用两次**语义正确**的重构降到 14：
      //   ① 「设置分节」契约（SettingsSection / SettingsActionButton）从 features/settings
      //      搬到 lib/design —— 它被 10 个 feature 当 chrome 契约用，住在 feature 里
      //      就等于让 design 层反过来 import feature（还会造出 4 条环）；
      //   ② 「平台标识」（platformGuidProvider）归一 —— 它被 7 个 feature 使用，
      //      从前住在 school_calendar、net_fee 里又复制一份，三处手工 invalidate
      //      把 platform_guid 与 leave / net_fee / school_calendar 咬成 3 条环。
      // 剩下 9 条多为**共享内核**（ims/student_info、school_calendar）与同族耦合
      //（ai/home、cxstar/read_credit …），台账见 docs/agents/33 §33.6。
      // 2026-09-20 · ⑦ 两轮：**四条纯导航的反向边**已收进「跳转缝」
      //（`lib/core/navigation/service_nav.dart`）—— zongce → 材料库、student_info → 主页、
      // home / ai → 设置页（改走 design 层官方入口 openSettings）、平台选择器 → 三个落点，
      // 14 → 12 → **9**。
      // ⚠ 这条是棘轮：**只许减**。新增一条要先想清楚，别靠调大这个数过关。
      const maxFeatureCycles = 9;
      final cycles = _featureCycles(_featureEdges(sources));
      expect(
        cycles.length,
        lessThanOrEqualTo(maxFeatureCycles),
        reason: '新增了 feature 双向依赖环：${cycles.join('、')}',
      );
    });

    test('data / domain 层不得 import 别家的 presentation', () {
      // 自维护：不列文件白名单，扫全 lib/features/*/{data,domain}/**。
      // 审计起点 2 处（home_widget 读首页仪表盘 provider、auth 的 MFA 服务弹
      // qr_login 对话框），两处都已倒转依赖。
      final re = RegExp(
        r"^import 'package:smarter_jxufe/features/([^/']+)/(presentation/[^']+)';",
        multiLine: true,
      );
      final bad = <String>[];
      for (final e in sources.entries) {
        final parts = e.key.split('/');
        if (parts.length < 4 || parts[1] != 'features') continue;
        final owner = parts[2];
        final layer = parts[3];
        if (layer != 'data' && layer != 'domain') continue;
        for (final m in re.allMatches(e.value)) {
          if (m.group(1) != owner) {
            bad.add('${e.key} → ${m.group(1)}/${m.group(2)}');
          }
        }
      }
      expect(
        bad,
        isEmpty,
        reason: '数据层去 import 界面层了 —— 要么把口径下沉到 data，'
            '要么让界面层把实现注册进来（两条先例见 docs/agents/33 §33.6）',
      );
    });

    test('页面互推走「跳转缝」（service_nav），不再直接 import 别家页面', () {
      // 2026-09-20 立 · 架构审查 ⑦：`service_nav.dart` 只放**注册表 + 两个动作**，
      // 目标页 builder 由组装根 `lib/main.dart` 注册（与 mfaReloginService.setFallback 同套路）。
      expect(
        _hits(sources, 'void registerServiceScreen('),
        ['lib/core/navigation/service_nav.dart'],
        reason: '跳转缝只能有一份实现',
      );
      expect(
        _hits(sources, 'bool openServiceScreen('),
        ['lib/core/navigation/service_nav.dart'],
      );
      // 该文件不许 import 任何 feature（core 是地基，唯一允许方向 = feature → core）。
      // ⚠ 两个坑都踩过：① 用 `_codeHits`（跳过注释行）——文件头注释里**必然**会引用它
      //   替代掉的那两条边；② 必须**只扫这一个文件**（`_codeHits` 默认扫全仓，
      //   别的文件里出现 `features/` 是正常的）。
      final seam = sources['lib/core/navigation/service_nav.dart'] ?? '';
      expect(seam, isNotEmpty, reason: '跳转缝文件必须存在');
      expect(
        _codeHits({'seam': seam}, 'features/'),
        isEmpty,
        reason: 'core/navigation/service_nav.dart 不许 import feature',
      );
      // 组装根必须注册这些页（否则跳转静默失效）。
      // ⚠ 先把空白压掉再比：注册调用可能被折成多行
      //   （`registerServiceScreen(\n  kServiceX,\n  …)`），裸 contains 会漏判。
      final mainSrc = (sources['lib/main.dart'] ?? '')
          .replaceAll(RegExp(r'\s+'), '');
      for (final id in const [
        'kServiceHome',
        'kServiceMaterials',
        'kServiceSettings',
        // 2026-09-20 第三轮：平台选择器的三个落点也走缝（`platform_selection_screen.dart`
        // 不再 import ims / comprehensive_service / data_center 的页面）。
        'kServiceIms',
        'kServiceComprehensive',
        'kServiceDataCenter',
      ]) {
        expect(mainSrc, contains('registerServiceScreen($id'), reason: '组装根少了 $id');
      }
      // 两条已收口的反向边不得复活。
      for (final entry in sources.entries) {
        if (entry.key.startsWith('lib/features/zongce/')) {
          expect(
            entry.value.contains('features/materials/presentation/'),
            isFalse,
            reason: '${entry.key} 又去 import 材料库页面了（改用 openServiceScreen）',
          );
        }
        if (entry.key.endsWith('ims/student_info/presentation/account_screen.dart')) {
          expect(
            entry.value.contains('features/home/presentation/home_screen.dart'),
            isFalse,
            reason: '账号页又去 import 首页了（改用 resetToServiceScreen(kServiceHome)）',
          );
        }
        if (entry.key.endsWith('platform/presentation/platform_selection_screen.dart')) {
          for (final dead in const [
            'features/ims/splash/presentation/ims_splash_screen.dart',
            'features/comprehensive_service/presentation/comprehensive_service_home_screen.dart',
            'features/data_center/presentation/data_center_screen.dart',
          ]) {
            expect(
              entry.value.contains(dead),
              isFalse,
              reason: '平台选择器又直接 import 落点页了（改用 replaceServiceScreen）',
            );
          }
          expect(
            entry.value.contains('replaceServiceScreen('),
            isTrue,
            reason: '三个落点应全部走跳转缝',
          );
        }
        // 设置页入口一律走 design 层的官方件（`openSettings` / `SettingsActionButton`）。
        if (entry.key.endsWith('features/home/presentation/home_screen.dart') ||
            entry.key.endsWith('features/ai/presentation/ai_chat_screen.dart')) {
          expect(
            entry.value.contains('features/settings/presentation/settings_screen.dart'),
            isFalse,
            reason: '${entry.key} 又直接 import 设置页了（改用 openSettings）',
          );
        }
      }
    });

    test('「设置分节」chrome 契约住在 design 层', () {
      expect(
        _hits(sources, 'enum SettingsSection'),
        ['lib/design/settings_section.dart'],
        reason: '被 10 个 feature + pane_chrome 引用的跨模块契约，不住 feature 里',
      );
      expect(_hits(sources, 'class SettingsActionButton'), [
        'lib/design/settings_entry.dart',
      ]);
      for (final gone in [
        'features/settings/domain/settings_section.dart',
        'features/settings/presentation/settings_entry.dart',
      ]) {
        expect(
          _codeHits(sources, gone),
          isEmpty,
          reason: '$gone 已搬走 —— 改 import 到 lib/design/，别再引旧路径',
        );
      }
    });

    test('平台标识（GUID）只有一份实现', () {
      const homePath =
          'lib/features/platform_guid/data/providers/guid_providers.dart';
      expect(
        _hits(sources, 'final platformGuidProvider = FutureProvider'),
        [homePath],
        reason: '被 7 个 feature 使用 —— 两份实现就会「保存后别处不刷新」',
      );
      expect(_hits(sources, 'final platformGuidBoxProvider = FutureProvider'), [
        homePath,
      ]);
      for (final old in [
        'wxGuidProvider',
        'wxPlatformBoxProvider',
        'netFeeGuidProvider',
        'netFeePlatformBoxProvider',
        'leaveGuidProvider',
      ]) {
        expect(
          _codeHits(sources, old),
          isEmpty,
          reason: '$old 已归一为 platformGuidProvider —— 归一之前每保存一次 GUID '
              '都要手工 invalidate 三个别家 provider（3 条依赖环的成因）',
        );
      }
    });

    test('平台标识的依赖方必须 `watch`（保存 GUID 靠级联重取）', () {
      // 归一之前 `lib/features/platform_guid/presentation/guid_guide_screen.dart`
      // 保存/清除 GUID 时要手工 invalidate 三个别家 provider（校历安排 / 网费汇总 /
      // 请假列表）—— 那正是 platform_guid ⇄ leave / net_fee / school_calendar
      // 三条环的成因。现在只 invalidate `platformGuidProvider` 一个，
      // **前提是这三家都 watch 它**：哪天有人把它改成 `read`，
      // 「保存了但别处不刷新」会静默回归。
      for (final path in [
        'lib/features/school_calendar/data/providers/wxcal_providers.dart',
        'lib/features/net_fee/data/providers/net_fee_providers.dart',
        'lib/features/leave/data/providers/leave_providers.dart',
      ]) {
        expect(
          sources[path]?.contains('ref.watch(platformGuidProvider.future)'),
          isTrue,
          reason: '$path 必须 watch（不是 read）platformGuidProvider，'
              '否则要退回手工失效名单，三条环会长回来',
        );
      }
      final guide =
          sources['lib/features/platform_guid/presentation/guid_guide_screen.dart'] ??
          '';
      expect(guide, isNotEmpty);
      for (final foreign in [
        'netFeeSummaryProvider',
        'leaveListProvider',
        'wxArrangementsProvider',
      ]) {
        expect(
          _codeHits({'guide': guide}, foreign),
          isEmpty,
          reason: '指南页不该再替别家记账（$foreign）—— 保存 GUID 只 invalidate '
              'platformGuidProvider，其余靠依赖级联；一旦这里又出现，'
              'platform_guid ⇄ net_fee / leave / school_calendar 三条环就长回来了',
        );
      }
    });

    test('首页仪表盘 provider 住在 data 层（桌面小组件复用同一口径）', () {
      const dataPath =
          'lib/features/home/data/providers/dashboard_providers.dart';
      for (final name in [
        'final dashboardElectricityProvider = FutureProvider',
        'final dashboardVolunteerHoursProvider = FutureProvider',
        'final dashboardTodayCoursesProvider = FutureProvider',
      ]) {
        expect(
          _hits(sources, name),
          [dataPath],
          reason: '`home_widget/data` 要复用这些口径 —— 写在 presentation 里就是 '
              'data → 别家 presentation 的越界（`refreshDashboard` 编排依赖小组件同步，'
              '反过来必须留在 panel）',
        );
      }
    });
  });

  group('设计色值唯一口径（2026-09-20 · 架构审查 ⑤）', () {
    /// 允许在自己文件里写颜色字面量的地方（**只有色板**，逐条给理由）。
    const colorLiteralAllowList = <String, String>{
      'lib/features/ims/schedule/presentation/schedule_tone.dart':
          '课程色板：14 填色 + 14 文字色 + 深色档，逐值经 ΔE 挑选并经用户裁定 '
              '（独立调色板，与功能色撞值属巧合而非复制）',
    };

    test('features / shared 里不许再写 `Color(0x…)` 字面量', () {
      final re = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
      final bad = <String>[];
      for (final e in sources.entries) {
        final isFeatureOrShared =
            e.key.startsWith('lib/features/') || e.key.startsWith('lib/shared/');
        if (!isFeatureOrShared || colorLiteralAllowList.containsKey(e.key)) {
          continue;
        }
        for (final line in e.value.split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          if (re.hasMatch(line)) {
            bad.add('${e.key} → ${line.trim()}');
            break;
          }
        }
      }
      expect(
        bad,
        isEmpty,
        reason: '色值唯一出处 = `lib/design/`（功能色走 feature_palette.dart，'
            '状态/等级/标签走 status_palette.dart）。字面量散在页面里，'
            '改一次主题就得全仓搜十六进制。命中：$bad',
      );
    });

    test('色值白名单不许陈旧（文件必须存在、且确实还在写字面量）', () {
      final re = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
      for (final e in colorLiteralAllowList.entries) {
        final src = sources[e.key];
        expect(src, isNotNull, reason: '${e.key} 不在 lib/ 下（白名单陈旧）');
        expect(
          re.hasMatch(src!),
          isTrue,
          reason: '${e.key} 已不再写颜色字面量 —— 请从白名单里删掉它',
        );
        expect(
          e.value.length,
          greaterThan(20),
          reason: '白名单必须写清「为什么允许」，不能空壳',
        );
      }
    });

    test('语义色板的类只在 design 层定义', () {
      for (final cls in [
        'StatusPalette',
        'ZongceTone',
        'TiceTone',
        'MaterialsTone',
        'ReadCreditTone',
        'PlatformEntryTone',
      ]) {
        expect(
          _hits(sources, 'abstract final class $cls'),
          ['lib/design/status_palette.dart'],
          reason: '$cls 是跨模块色值的唯一出处，别在 feature 里再开一份',
        );
      }
    });

    test('迁移后的关键色值仍指向同一档（防手滑改色）', () {
      // golden / 视觉守卫只覆盖少数页面，这里钉住「值搬家没改色」这条性质：
      // 每个 token 的十六进制值就是迁移前页面里那个字面量。
      const expected = <String, String>{
        'wechatBlue': '0xFF73A9EC',
        'wechatGreen': '0xFF14C468',
        'success': '0xFF0F7B0F',
        'retake': '0xFF800000',
        'scrim': '0xB3000000',
        'readerBackdrop': '0xFF2B2B2B',
        'readerInk': '0xFF1F1F1F',
        'infoBand': '0xFFEFA0A0',
        'competitionTeam': '0xFF6A1B9A',
        'ticeFemale': '0xFFAD1457',
      };
      final palette = sources['lib/design/status_palette.dart']!;
      for (final e in expected.entries) {
        expect(
          palette.contains('${e.key} = Color(${e.value})'),
          isTrue,
          reason: 'StatusPalette.${e.key} 必须仍是 ${e.value} —— '
              '这批 token 是「值搬家」，不是配色调整',
        );
      }
    });

    test('五育色 = 2026-09-21 定色后的取值', () {
      // 用户原话：「我觉得我现在调的五育不好看，你改改」。上一版（提亮那版）的毛病
      // 是**不齐**：白底对比度散在 3.68–4.43（智育蓝明显更亮），且德育红 ≈ 不合格红、
      // 体育绿 ≈ 优秀绿（ΔE 15 / 19），同一行里「育名 + 等次」会糊。
      // 现在五色按两条硬指标定：① 对比度一律 4.75:1（五行等重）；② 育与育最小
      // ΔE(CIE76) 55.9、育与最近等次色最小 ΔE 20.2。要再亮得先改形态，别直接调亮。
      const expected = <String, String>{
        'deyu': '0xFFD03860',
        'zhiyu': '0xFF2B77B8',
        'tiyu': '0xFF1E8261',
        'meiyu': '0xFFBA31CF',
        'laoyu': '0xFF926D22',
      };
      final palette = sources['lib/design/status_palette.dart']!;
      for (final e in expected.entries) {
        expect(
          palette.contains('${e.key} = Color(${e.value})'),
          isTrue,
          reason: 'ZongceTone.${e.key} 必须仍是 ${e.value}（提亮档，别手滑改回去）',
        );
      }
    });
  });

  group('⑤-B 设计口径：节标题 / 卡片形状 / 断点（2026-09-20 · 架构审查）', () {
    test('节标题（3px 竖条）只有一份实现', () {
      final sources = _sources();
      expect(_hits(sources, 'Widget appSectionTitle('), [
        'lib/design/section_title.dart',
      ], reason: '节标题的唯一实现在 lib/design/section_title.dart');
      // 兼容别名 geCardTitle 必须**转发**，不许自己再留一份实现。
      final ge =
          sources['lib/features/score_estimate/presentation/ge_common.dart']!;
      expect(ge.contains('appSectionTitle('), isTrue);
      expect(
        ge.contains('width: 3,'),
        isFalse,
        reason: 'geCardTitle 只许转发 appSectionTitle，不许留竖条实现',
      );
    });

    test('★ 手写竖条只允许「竖条 + 图标 + 文案」那一种构件', () {
      // 白名单 = ① 唯一实现自己；② 两处「竖条 + 图标 + 文案」的分组头
      // （并进 appSectionTitle 会丢掉中间那个图标，故有意保留）。
      const allowed = [
        'lib/design/section_title.dart',
        'lib/features/school_calendar/presentation/school_calendar_screen.dart',
        'lib/features/site_nav/presentation/site_nav_screen.dart',
      ];
      final bar = RegExp(r'width: 3,\n[ \t]*height: 1[345],');
      final found = <String>[
        for (final e in _sources().entries)
          if (bar.hasMatch(e.value)) e.key,
      ]..sort();
      expect(found, equals([...allowed]..sort()),
          reason: '节标题请用 appSectionTitle（lib/design/section_title.dart）');
    });

    test('手拼卡片形状（圆角 12 + hairline 边）已清零', () {
      // 两类写法都算：`decoration: BoxDecoration(...)` 与 `Card(shape: RoundedRectangleBorder(...))`。
      final bad = <String>[];
      for (final e in _sources().entries) {
        final bodies = [
          ..._parenBlocks(e.value, 'decoration: BoxDecoration'),
          ..._parenBlocks(e.value, 'shape: RoundedRectangleBorder'),
        ];
        for (final body in bodies) {
          final rounded = body.contains('circular(12)') ||
              body.contains('circular(kAppCardRadius)');
          if (rounded && body.contains('hairline')) bad.add(e.key);
        }
      }
      expect(bad..sort(), isEmpty,
          reason: '与卡片契约等价的形状请写 appCardShape(context)'
              '（BoxDecoration 用 ShapeDecoration(shape: appCardShape(context), color: …)）');
    });

    test('卡片描边只许比契约轻：`scheme.outline` 实线描边零命中', () {
      // 卡片描边的唯一出处 = `appCardBorderSide`（浅色 `outlineVariant` 60% / 深色原值）。
      // 起点：`lib/features/rules/presentation/rules_home_screen.dart` 与
      // `lib/features/site_nav/presentation/site_nav_screen.dart` 曾写
      // `side: BorderSide(color: scheme.outline)` —— 比契约深一档的灰实线 + 自定圆角（9），
      // 用户 2026-09-20 一眼看出「『规章制度』和『网站导航』中的卡片样式与其他页面不同」。
      final sources = _sources();
      expect(
        _codeHits(sources, 'BorderSide(color: scheme.outline)'),
        isEmpty,
        reason: '卡片描边请走 appCardShape(context) / appCardBorderSide(scheme)，'
            '别自己写 scheme.outline 实线描边',
      );
      expect(
        _codeHits(sources, 'Border.all(color: scheme.outline)'),
        isEmpty,
        reason: '手拼卡片容器请用 ShapeDecoration(shape: appCardShape(context), color: …)',
      );
    });

    test('响应式断点只有一份取值表', () {
      // 只禁「与三位数字面量比大小」的硬编码断点；胶囊宽度之类的数值不受影响。
      final literal = RegExp(r'(?:maxWidth|size\.width)\s*[<>]=?\s*\d{3}');
      final found = <String>[
        for (final e in _sources().entries)
          if (e.value
              .split('\n')
              .any((l) => !l.trimLeft().startsWith('//') && literal.hasMatch(l)))
            e.key,
      ]..sort();
      expect(found, isEmpty,
          reason: '断点请用 lib/design/breakpoints.dart 的 Breakpoints.narrow / tight / wide / extraWide');
    });
  });

  group('SnackBar 的 persist 口径（2026-09-21 立）', () {
    test('带 action 的 SnackBar 必须显式写 persist: false', () {
      // 用户 2026-09-21 原话：「合并后，底部的提示信息不消失」。
      // 根因在框架默认值：`SnackBar` 构造里 `persist = persist ?? action != null`
      // （`<FLUTTER_ROOT>\packages\flutter\lib\src\material\snack_bar.dart:303`），
      // 而 `ScaffoldMessengerState` 的自动消失计时器回调第一句就是
      // `if (snackBar.persist) return;`
      // （`…/material/scaffold.dart:618-625`）→ **带 action 的提示默认永不消失**，
      // 页面上写的 `duration:` 形同虚设。
      // 确实要常驻的提示把路径写进 allowed 并写明理由（本仓暂无）。
      const allowed = <String>[];
      final bad = <String>{};
      var seen = 0;
      for (final e in _sources().entries) {
        final blocks = _snackBarBlocks(e.value);
        seen += blocks.length;
        for (final body in blocks) {
          if (body.contains('action:') && !body.contains('persist:')) {
            bad.add(e.key);
          }
        }
      }
      // 防空扫：全仓 SnackBar 构造有近百处，扫到个位数说明配平/前瞻写坏了。
      expect(seen, greaterThan(30), reason: '扫描器没扫到 SnackBar 构造');
      expect(
        bad.toList()..sort(),
        equals([...allowed]..sort()),
        reason: '带 action 的 SnackBar 请补 `persist: false`，否则它永远不会自己消失',
      );
    });
  });
}
