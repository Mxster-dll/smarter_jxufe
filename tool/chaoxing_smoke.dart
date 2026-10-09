/// 学习通（超星）· **真机端到端**冒烟（真账号 / 真服务端 / 真 Dart 代码）。
///
/// 为什么是独立脚本：换证链与三个数据源都是**纯 Dart**（`dio` + `dart:io`），
/// 不拉 Flutter —— 于是能在命令行把「本机已有 TGC → CAS 换票 → 网关桥接 →
/// 学习通会话 → 课程 → 作业 → 通知」对**真实服务端**跑一遍。
///
/// 覆盖到的**真实类**：
/// - `ChaoxingAuthRemoteDataSource.establishSession`（换票链 + 网关桥接 + passport 判定 + 收件箱 token）
/// - `ChaoxingMoocRemoteDataSource.courses / worksOf`（课程清单 + 逐课作业入口与列表）
/// - `ChaoxingNoticeRemoteDataSource.hasNew / list`
/// - `SessionCookieJar` / `ChaoxingHttpClient`（按域 Cookie / 失效识别）
/// - `ChaoxingSnapshot` 派生口径（待做排序 / 未读计数 / 最近截止）
///
/// 不覆盖（属 Flutter 侧，另有单测）：providers、控制器、四个页面、`ChaoxingStore`（Hive）。
///
/// 用法（仓库根目录）：
/// ```
/// $env:FLUTTER_ROOT='<FLUTTER_ROOT>'
/// & "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe" run tool\chaoxing_smoke.dart
/// ```
/// 参数：`--diag` 落盘第一门课的中间页与作业页；`--all` 全扫（**会撞风控**，
/// 是诊断用；默认只扫「当下学期」，与生产口径一致）；`--term=252` 手动指定学期码。
/// ⚠ 安全口径：只打印**长度 / 条数 / 状态分布**，TGC、票据、Cookie 值、收件箱 token、
/// 作业页 `enc`/`openc`、课程名与通知原文一律不打印（trace 里也逐个掩码）。
library;

// 这是命令行验收脚本：打印就是它的输出通道。
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_work_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_mooc_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_notice_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_sign_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_scan.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

const String _authBox = r'app_data\auth.hive';

/// 逐课取作业的并发度（与 `ChaoxingRepository` 默认值同口径）。
const int _concurrency = 4;

int _passed = 0;
int _failed = 0;

/// 课程里**最大的学期码**（`261` > `252` > `251`）—— 纯 Dart 推「当下学期」：
/// 本学期的课一定是最新那批。一门都认不出学期前缀时返回空串（= 不筛）。
String _newestTermCode(List<ChaoxingCourse> courses) {
  var best = '';
  for (final c in courses) {
    final code = c.termCode;
    if (code.isEmpty) continue;
    if (code.compareTo(best) > 0) best = code;
  }
  return best;
}

void _check(String what, bool ok, [String? detail]) {
  if (ok) {
    _passed++;
    print('  ✓ $what${detail == null ? '' : ' — $detail'}');
  } else {
    _failed++;
    print('  ✗ $what${detail == null ? '' : ' — $detail'}');
  }
}

void _step(String title) => print('\n=== $title ===');

/// 计数分布（`二维码签到=3 / 手势签到=1`）。
String _distribution(Iterable<String> values) {
  final map = <String, int>{};
  for (final v in values) {
    map[v] = (map[v] ?? 0) + 1;
  }
  return map.entries.map((e) => '${e.key}=${e.value}').join(' / ');
}

/// 签到状态文案（冒烟脚本不 import 页面层，故在这里给一份最小映射）。
String chainStatusText(ChaoxingSign sign) =>
    sign.statusLoaded ? sign.status.label : '状态未知（还没查）';

/// 掩码：任何 `key=value` 形态的凭据都只留键名。
String _mask(String line) => line
    .replaceAll(
      RegExp(r'(ticket|data|time|enc|openc|s|JSESSIONID)=[^&\s]+'),
      r'$1=***',
    )
    .replaceAll(RegExp(r'[0-9a-fA-F]{32,}'), '***');

// ───────────────────────── 本机凭据（只读，只报形态） ─────────────────────────

/// 从 `auth.hive` 里扫 `TGC|<10 位账号>` 帧（帧格式：`[1B 键长][键][0x04][4B-LE 值长][值]`）。
({String account, String tgc})? _tgcFrom(File box) {
  final raw = Uint8List.fromList(box.readAsBytesSync());
  final needle = 'TGC|'.codeUnits;
  ({String account, String tgc})? found;
  for (var i = 0; i + needle.length + 10 < raw.length; i++) {
    var hit = true;
    for (var k = 0; k < needle.length; k++) {
      if (raw[i + k] != needle[k]) {
        hit = false;
        break;
      }
    }
    if (!hit) continue;
    final acctStart = i + needle.length;
    final acct = String.fromCharCodes(raw.sublist(acctStart, acctStart + 10));
    if (!RegExp(r'^\d{10}$').hasMatch(acct)) continue;
    final p = acctStart + 10;
    if (p + 5 > raw.length || raw[p] != 0x04) continue;
    final len =
        raw[p + 1] | (raw[p + 2] << 8) | (raw[p + 3] << 16) | (raw[p + 4] << 24);
    if (len <= 0 || len > 4096 || p + 5 + len > raw.length) continue;
    found = (
      account: acct,
      tgc: String.fromCharCodes(raw.sublist(p + 5, p + 5 + len)),
    );
  }
  return found;
}

/// 与 `AuthRepository.getServiceRedirectUrl` 同语义：带 TGC 访问 CAS，
/// 跟到跳出 CAS 域、带 `ticket=` 的那个地址。
///
/// [trace] 非空时逐跳记录（只记状态码与主机名，**URL 一律掩码**）。
Future<String> _ticketUrl(Dio dio, String tgc, {List<String>? trace}) async {
  var url = ChaoxingEndpoints.casServiceUrl;
  for (var hop = 0; hop < 8; hop++) {
    final r = await dio.get<dynamic>(
      url,
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: {'Cookie': 'TGC=$tgc'},
      ),
    );
    final loc = r.headers.value('location');
    final body = r.data?.toString() ?? '';
    trace?.add(
      '跳[$hop] ${r.statusCode} ${Uri.parse(url).host}'
      ' location=${loc == null || loc.isEmpty ? '无' : '有'}'
      ' 页面 ${body.length} B${body.contains('name="password"') ? '（含密码框 → 登录页）' : ''}',
    );
    if (loc == null || loc.isEmpty) break;
    url = Uri.parse(url).resolve(loc).toString();
    if (url.contains('ticket=')) return url;
  }
  throw StateError('CAS 没给票据（TGC 可能已过期，请在 App 里重新登录一次）');
}

/// 按 [limit] 并发跑一批任务，逐项容错（返回 null = 该项失败）。
Future<List<T?>> _mapLimited<S, T>(
  List<S> items,
  int limit,
  Future<T> Function(S item) run,
) async {
  final out = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) return;
      try {
        out[i] = await run(items[i]);
      } catch (e) {
        print('    （第 ${i + 1} 门课取作业失败：$e）');
      }
    }
  }

  await Future.wait([for (var i = 0; i < limit && i < items.length; i++) worker()]);
  return out;
}

Future<void> main(List<String> args) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
      headers: {'User-Agent': kChaoxingUserAgent},
    ),
  );
  final http = ChaoxingHttpClient(dio);

  try {
    // ── 0. 本机 TGC ──────────────────────────────────────────────
    _step('0) 从 app_data/auth.hive 取 TGC（只报长度）');
    final box = File(_authBox);
    if (!box.existsSync()) {
      print('  ✗ 找不到 $box —— 请先在 App 里登录一次');
      exitCode = 1;
      return;
    }
    final cred = _tgcFrom(box);
    if (cred == null) {
      print('  ✗ auth.hive 里没有 TGC —— 请先在 App 里登录一次');
      exitCode = 1;
      return;
    }
    print(
      '  ✓ 账号 …${cred.account.substring(6)}；TGC 长度 ${cred.tgc.length}，'
      '形态 ${cred.tgc.substring(0, 3)}…（原文不打印）',
    );

    // ── 1. CAS 换票 ─────────────────────────────────────────────
    _step('1) CAS 换票（service = 超星统一认证网关）');
    final casTrace = <String>[];
    late String ticket;
    try {
      ticket = await _ticketUrl(dio, cred.tgc, trace: casTrace);
    } finally {
      // 失败时也要把逐跳打出来 —— 这才是诊断「票过期 vs 链路变了」的依据。
      for (final line in casTrace) {
        print('    ${_mask(line)}');
      }
    }
    print('  ✓ 拿到票据（URL 长度 ${ticket.length}，含 ticket= 参数）');

    // ── 2. 网关桥接 → 学习通会话 ─────────────────────────────────
    _step('2) 网关桥接 → 学习通会话（passport 域级 Cookie + 收件箱 token）');
    final auth = ChaoxingAuthRemoteDataSource(http);
    final trace = <String>[];
    final session = await auth.establishSession(ticket, trace: trace);
    for (final line in trace) {
      print('    ${_mask(line)}');
    }
    _check('会话就位（passport Cookie）', session.isAlive,
        '罐内域 = ${session.jar.namesOf().keys.join(', ')}');
    _check(
      '收件箱 token 已抠到（登录链最后一跳顺带）',
      session.canFetchNotices,
      'token 长度 ${(session.noticeToken ?? '').length}（原文不打印）',
    );

    // ── 3. 课程清单 ─────────────────────────────────────────────
    _step('3) 课程清单 /visit/courses');
    final mooc = ChaoxingMoocRemoteDataSource(http);
    final courses = await mooc.courses(session);
    _check('课程清单非空', courses.isNotEmpty, '共 ${courses.length} 门');
    final terms = <String, int>{};
    for (final c in courses) {
      final term = c.termLabel.isEmpty ? '（无学期前缀）' : c.termLabel;
      terms[term] = (terms[term] ?? 0) + 1;
    }
    print('    学期分布：${terms.entries.map((e) => '${e.key}=${e.value}').join(' / ')}');
    _check(
      '每门课的 courseId / classId / cpi 都齐',
      courses.every((c) => c.courseId.isNotEmpty && c.classId.isNotEmpty),
    );

    // ── 4. 逐课作业 ─────────────────────────────────────────────
    //
    // ⚠ **默认只扫「当下学期」**（与 `ChaoxingRepository` 的生产口径一致，口径函数 =
    // `chaoxingScanTargets`）：作业是学习通里唯一没有统一接口的数据（逐课 2 请求），
    // 35 门全扫 = 70 个请求必然撞风控（实测第 31 门 ≈62 个请求处整段变验证码页）。
    // 只扫当下学期（实测 261 学期 10 门 + 无学期前缀 2 门 = 12 门 = 24 个请求）就脱离
    // 预算区，一轮拿全。要看全扫的后果加 `--all`（末尾几门被验证码页拦下是预期现象）。
    final scanAll = args.contains('--all');
    // 纯 Dart 推当下学期：取课程里**最大的学期码**（261 > 252 > 251）—— 本学期课程
    // 一定是最新的那批。`--term=252` 可手动指定。
    final termArg = args.firstWhere((a) => a.startsWith('--term='), orElse: () => '');
    final currentTermCode = termArg.isEmpty
        ? _newestTermCode(courses)
        : termArg.substring('--term='.length);
    final scanCourses = scanAll
        ? courses
        : chaoxingScanTargets(courses, currentTermCode: currentTermCode);
    _step(
      '4) 逐课作业（并发 $_concurrency：课程详情 → 作业列表）'
      '${scanAll ? '【--all 全扫】' : ' · 当前学期码 ${currentTermCode.isEmpty ? '（判不出，不筛）' : currentTermCode}'
          ' → ${scanCourses.length}/${courses.length} 门'}',
    );
    final sw = Stopwatch()..start();
    final perCourse = await _mapLimited(
      scanCourses,
      _concurrency,
      (c) => mooc.worksOf(session, c),
    );
    sw.stop();
    final works = <ChaoxingWork>[
      for (final list in perCourse) ...?list,
    ];
    final failedCourses = [
      for (var i = 0; i < perCourse.length; i++)
        if (perCourse[i] == null) scanCourses[i].key,
    ];
    final withWorks = perCourse.where((l) => (l ?? const []).isNotEmpty).length;
    _check('逐课扫描完成（无异常课）', failedCourses.isEmpty,
        '耗时 ${sw.elapsedMilliseconds} ms，${scanCourses.length} 门');
    if (failedCourses.isNotEmpty) print('    失败课：${failedCourses.length} 门');
    print('    有作业的课 $withWorks / ${scanCourses.length}；作业共 ${works.length} 条');
    final byStatus = <ChaoxingWorkStatus, int>{};
    for (final w in works) {
      byStatus[w.status] = (byStatus[w.status] ?? 0) + 1;
    }
    print(
      '    状态分布：'
      '${byStatus.entries.map((e) => '${e.key.label.isEmpty ? '未知' : e.key.label}=${e.value}').join(' / ')}',
    );

    // ── 4b. 诊断（`--diag`）：把第一门课的中间页与作业页原样落盘 ──
    if (args.contains('--diag') && courses.isNotEmpty) {
      _step('4b) 诊断：课程详情页与作业列表的原始响应');
      final c = courses.first;
      final referer =
          'https://${ChaoxingEndpoints.moocHost}${ChaoxingEndpoints.moocCoursesPath}';
      final midHops = <String>[];
      final middle = await http.get(
        'https://${ChaoxingEndpoints.moocHost}'
        '${ChaoxingEndpoints.moocCourseMiddlePath}',
        jar: session.jar,
        query: {
          'courseid': c.courseId,
          'clazzid': c.classId,
          'vc': '1',
          'cpi': c.cpi,
        },
        referer: referer,
        followRedirects: true,
        trace: midHops,
      );
      final midBody = middle.data?.toString() ?? '';
      if (midHops.isNotEmpty) print('    重定向链：${midHops.join(' → ')}');
      print(
        '    课程详情 ${middle.statusCode} · ${midBody.length} B · '
        'getAllWork×${RegExp('getAllWork').allMatches(midBody).length} · '
        '含 &amp; = ${midBody.contains('&amp;')} · '
        '含「暂无内容」= ${midBody.contains('暂无内容')} · '
        '含「作业」= ${midBody.contains('作业')}',
      );
      File(r'.scratch\xxt_smoke_middle.html').writeAsStringSync(midBody);

      final query = chaoxingWorkEntryQuery(midBody);
      if (query == null) {
        print('    ✗ 抠不出作业入口 query（解析器与真实页面不一致）');
      } else {
        print('    抠出 query：长度 ${query.length} · ${_mask(query)}');
        final list = await http.get(
          'https://${ChaoxingEndpoints.moocHost}'
          '${ChaoxingEndpoints.moocWorkListPath}?$query',
          jar: session.jar,
          referer:
              'https://${ChaoxingEndpoints.moocHost}'
              '${ChaoxingEndpoints.moocCourseMiddlePath}',
          followRedirects: true,
        );
        final body = list.data?.toString() ?? '';
        final parsed = parseChaoxingWorks(
          body,
          courseId: c.courseId,
          courseName: c.name,
        );
        print(
          '    作业列表 ${list.statusCode} · ${body.length} B · '
          '解析出 ${parsed.length} 条 · 判空 = ${chaoxingWorkPageIsEmpty(body)}',
        );
        File(r'.scratch\xxt_smoke_worklist.html').writeAsStringSync(body);
      }
    }

    // ── 4c. 签到（清单 1 请求/课 + 按需 1 请求/活动） ──────────────
    //
    // 成本口径：清单是**每门课 1 个请求**（`POST widget/pcpick/stu/activeList`）；
    // 「我的状态」只能逐活动取（1 请求/活动），所以这里**只抽 1 条**验证链路
    // （全量补状态是 App 里的手动动作，见 `chaoxing_signs_screen.dart`）。
    _step('4c) 签到（清单 × ${scanCourses.length > 3 ? 3 : scanCourses.length} 门 + 1 条详情）');
    final signSource = ChaoxingSignRemoteDataSource(http);
    final signCourses = scanCourses.take(3).toList();
    final signs = <ChaoxingSign>[];
    final signFailures = <String>[];
    for (final c in signCourses) {
      try {
        signs.addAll(await signSource.signsOf(session, c));
      } catch (e) {
        signFailures.add(c.key);
        print('    （${c.key} 签到清单失败：$e）');
      }
    }
    _check(
      '每门课 1 个请求就拿到全部签到',
      signFailures.isEmpty,
      '${signCourses.length} 门课 → ${signs.length} 条签到'
      '（进行中 ${signs.where((s) => s.isOpenAt(DateTime.now())).length} 条）',
    );
    if (signs.isNotEmpty) {
      print('    类型分布：'
          '${_distribution(signs.map((s) => s.typeName.isEmpty ? '（无名）' : s.typeName))}');
      final sample = signs.first;
      final detail = await signSource.detailOf(session, sample);
      _check(
        '抽 1 条取「我的状态」（1 请求/活动）',
        true,
        '状态 = ${chainStatusText(detail)}'
        '${detail.signedAt == null ? '' : ' · 签到时刻 ${chaoxingMomentText(detail.signedAt)}'}'
        ' · 状态已确认 = ${detail.statusLoaded}',
      );
    }
    _check(
      '签到「没查状态」与「未签」分得开',
      signs.every((s) => !s.statusLoaded),
      '清单接口不给我的状态（实测 userStatus 恒为 null）→ 全部「状态未知」',
    );

    // ── 5. 通知 ─────────────────────────────────────────────────
    _step('5) 通知（收件箱红点 + 列表）');
    final notice = ChaoxingNoticeRemoteDataSource(http);
    final hasNew = await notice.hasNew(session);
    print('    红点 hasNew = $hasNew（⚠ 实测口径：它不是条数）');
    var notices = <ChaoxingNotice>[];
    var noticesAvailable = true;
    try {
      notices = await notice.list(session);
    } catch (e) {
      noticesAvailable = false;
      print('  ✗ 通知取数失败：$e');
    }
    _check('通知列表可解析', noticesAvailable, '共 ${notices.length} 条');
    if (noticesAvailable) {
      final unread = notices.where((n) => !n.read).length;
      final senders = notices.where((n) => n.sender.isNotEmpty).length;
      print('    未读 $unread 条；带发件人的 $senders 条；置顶 '
          '${notices.where((n) => n.top).length} 条');
      _check('字段口径正确（发件人 / 已读 / 时间）',
          senders > 0 && notices.every((n) => n.sentAt != null || n.content.isNotEmpty));
    }

    // ── 6. 快照派生（界面直接用到的那些数） ──────────────────────
    _step('6) ChaoxingSnapshot 派生口径');
    final snapshot = ChaoxingSnapshot(
      courses: courses,
      works: works,
      signs: signs,
      notices: notices,
      fetchedAt: DateTime.now(),
      failedCourseKeys: failedCourses,
      noticesAvailable: noticesAvailable,
    );
    _check('课程数', snapshot.courses.length == courses.length,
        '${snapshot.courses.length}');
    _check('待做作业', snapshot.todoCount >= 0, '${snapshot.todoCount} 条');
    _check('未读通知', snapshot.unreadNoticeCount >= 0,
        '${snapshot.unreadNoticeCount} 条');
    _check(
      '待做按截止升序（越早越靠前）',
      () {
        final list = snapshot.openWorks;
        for (var i = 1; i < list.length; i++) {
          final a = list[i - 1].dueAt, b = list[i].dueAt;
          if (a == null || b == null) continue;
          if (a.isAfter(b)) return false;
        }
        return true;
      }(),
    );
    final nearest = snapshot.openWorks.isEmpty ? null : snapshot.openWorks.first;    if (nearest != null) {
      print('    最近一条待做：截止 ${chaoxingDueText(nearest.dueAt)} · '
          '${chaoxingCountdownText(nearest.dueAt, DateTime.now())}');
    }
    _check('快照 JSON 往返（缓存要能落盘再读回）',
        ChaoxingSnapshot.fromJson(snapshot.toJson()).courses.length ==
            courses.length);

    // ── 收尾 ────────────────────────────────────────────────────
    _step('结果');
    print('  通过 $_passed 项，失败 $_failed 项');
    exitCode = _failed == 0 ? 0 : 1;
  } catch (e) {
    print('\n✗ 冒烟失败：$e');
    exitCode = 1;
  } finally {
    dio.close(force: true);
  }
}
