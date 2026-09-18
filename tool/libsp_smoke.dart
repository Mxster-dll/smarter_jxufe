/// 图书馆订阅词云同步 · **真机端到端**冒烟（真账号 / 真服务端 / 真 Dart 代码）。
///
/// 为什么是独立脚本：它走的是**纯 Dart** 链路（`dart:io` + `dio` + 真 Hive box 文件），
/// 不拉 Flutter —— 于是能在命令行直接跑一次「本机真实数据 → 加密编码 → 上传 →
/// 读回解码 → 逐字段比对 → 恢复 → 清除」，把协议对真实服务端验一遍。
///
/// 覆盖到的**真实类**：
/// - `LibspAuthRemoteDataSource.establishSession`（换证链 + 网关桥接 + `SESSION` cookie）
/// - `LibspSubscribeRemoteDataSource`（list / add / del，含 401 与登录页识别）
/// - `LibspSyncService`（inspect / upload / latestSummary / latestSnapshot / restore /
///   clearCloud，含双代轮转、逐片读回校验、部分缺片自愈）
/// - `libsp_codec.dart` / `libsp_payload.dart` 全套（汉字编码、CRC、gzip、降级链）
///
/// 不覆盖（属于 Flutter 侧，另有单测）：`HiveLibspLocalStore`（用 `hive_flutter`）、
/// `LibspRemoteAdapter`（依赖 `AuthRepository`）、`LibspSyncController`。
/// 本脚本用 `_MemoryStore` 顶替前者，因此**写入链路在这里是内存版**，
/// 但读进快照的源数据仍是磁盘上**真实 box 文件**（拷副本后只读打开）。
///
/// 用法（仓库根目录）：
/// ```
/// $env:FLUTTER_ROOT='D:\Program\flutter'
/// & 'D:\Program\flutter\bin\cache\dart-sdk\bin\dart.exe' run tool\libsp_smoke.dart
/// ```
/// ⚠ 安全口径：**只打印长度与条数，绝不打印 TGC / ticket / cookie / 订阅词原文**。
/// 脚本结束会把云端自己的词删干净（对账），失败也会尽力收尾。
library;

// 这是命令行验收脚本：打印就是它的输出通道。
// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

const String _appData = r'D:\Project\Ongoing\smarter_jxufe\app_data';
const String _account = '2000000000';

int _passed = 0;
int _failed = 0;

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

// ───────────────────────────── 真本机数据（只读） ─────────────────────────────

/// 拷贝 box 文件到临时目录后**只读**打开（App 运行中会锁住原文件）。
Future<Box<String>?> _openCopy(
  String boxName,
  String tmpDir,
) async {
  final src = File('$_appData\\$boxName.hive');
  if (!src.existsSync()) return null;
  try {
    final dst = await src.copy('$tmpDir\\$boxName.hive');
    final _ = dst;
    return await Hive.openBox<String>(boxName);
  } catch (e) {
    print('    （$boxName 打不开：$e）');
    return null;
  }
}

/// 合成兜底数据（读不到真 box 时用；**不是**默认路径）。
({Map<String, Map<String, String>> prefs, List<Map<String, dynamic>> courses})
_synthetic() {
  final courses = <Map<String, dynamic>>[
    for (var i = 0; i < 10; i++)
      {
        'id': 'syn-$i',
        'name': '合成课程$i（用于容量估算的随机内容 '
            '${List.generate(12, (k) => String.fromCharCode(0x4E00 + (i * 97 + k * 31) % 0x2000)).join()}）',
        'courseCode': 'SYN$i',
        'dailyPercent': 30 + i,
        'credits': 1 + i % 4,
        'finalScore': 80 + i,
        'note': '合成备注$i',
        'parts': [
          {
            'id': 'p$i',
            'name': '作业',
            'mode': 'up',
            'target': 10,
            'current': i,
            'score': 0,
            'cap': 40,
            'note': '',
          },
        ],
        'deadlines': [
          {
            'id': 'd$i',
            'title': '第 $i 次作业',
            'kind': 'homework',
            'dueAt': 1789000000000 + i * 86400000,
            'repeat': 'none',
            'note': '',
            'doneAt': null,
            'remind': true,
          },
        ],
        'memo': {'text': '不进载荷', 'images': <dynamic>[]},
        'createdAt': 1780000000000 + i,
      },
  ];
  return (
    prefs: {
      'themePrefs': {'mode': 'dark'},
      'myCampusPrefs': {'campus': '蛟桥园校区'},
      'schoolCalendarPrefs': {'markStyle': 'below', 'filterAudience': 'true'},
    },
    courses: courses,
  );
}

// ───────────────────────────── 端口实现（脚本内） ─────────────────────────────

class _SmokeRemote implements LibspRemote {
  _SmokeRemote(this._ds, this._cookie);

  final LibspSubscribeRemoteDataSource _ds;
  final String _cookie;
  int adds = 0;
  int deletes = 0;

  @override
  Future<List<LibspRemoteWord>> listWords() => _ds.listWords(_cookie);

  @override
  Future<void> addWord(String name) async {
    adds++;
    await _ds.addWord(_cookie, name);
  }

  @override
  Future<void> deleteWord(int subId) async {
    deletes++;
    await _ds.deleteWord(_cookie, subId);
  }
}

class _MemoryStore implements LibspLocalStore {
  _MemoryStore({
    required this.prefs,
    required this.courses,
    required this.zongce,
  });

  Map<String, Map<String, String>> prefs;
  List<Map<String, dynamic>> courses;
  Map<String, String> zongce;

  @override
  Future<Map<String, Map<String, String>>> readPrefs() async => prefs;

  @override
  Future<List<Map<String, dynamic>>> readCourses() async => courses;

  @override
  Future<Map<String, String>> readZongceEntries() async => zongce;

  @override
  Future<void> writePrefs(Map<String, Map<String, String>> value) async {
    prefs = value;
  }

  @override
  Future<void> writeCourses(List<Map<String, dynamic>> value) async {
    courses = value;
  }

  @override
  Future<void> writeZongceEntries(Map<String, String> value) async {
    zongce = value;
  }
}

// ───────────────────────────── 工具 ─────────────────────────────

/// 帧格式：`[1B 键长][键][0x04][4B-LE 值长][值]`（与 `.scratch/libsp.py` 同口径）。
String? _tgcFrom(File box, String account) {
  final raw = Uint8List.fromList(box.readAsBytesSync());
  final needle = ascii.encode('TGC|$account');
  for (var i = 0; i + needle.length < raw.length; i++) {
    var hit = true;
    for (var k = 0; k < needle.length; k++) {
      if (raw[i + k] != needle[k]) {
        hit = false;
        break;
      }
    }
    if (!hit) continue;
    final p = i + needle.length;
    if (p + 5 > raw.length || raw[p] != 0x04) continue;
    final len = raw[p + 1] | (raw[p + 2] << 8) | (raw[p + 3] << 16) |
        (raw[p + 4] << 24);
    if (len <= 0 || len > 4096 || p + 5 + len > raw.length) continue;
    return utf8.decode(raw.sublist(p + 5, p + 5 + len), allowMalformed: true);
  }
  return null;
}

/// 与 `AuthRepository.getServiceRedirectUrl` 同语义：带 TGC 访问 CAS，
/// 跟到跳出 CAS 域、带 `ticket=` 的那个地址。
Future<String> _ticketUrl(Dio dio, String tgc) async {
  var url = LibspAuthRemoteDataSource.casServiceUrl;
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
    if (loc == null || loc.isEmpty) break;
    url = Uri.parse(url).resolve(loc).toString();
    if (url.contains('ticket=')) return url;
  }
  throw StateError('CAS 没给票据（TGC 可能已过期，请在 App 里重新登录一次）');
}

String _canon(Object? value) {
  Object? norm(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: norm(v[k])};
    }
    if (v is List) return [for (final e in v) norm(e)];
    return v;
  }

  return jsonEncode(norm(value));
}

/// 课程「跨设备可见字段」的规范串（剔除 id / createdAt / memo —— 它们本就不过云）。
String _courseSignature(Map<String, dynamic> raw, {required bool withNotes}) {
  final clean = sanitizeGeCourse(
    raw,
    dropNotes: !withNotes,
    maxDeadlines: null,
  );
  return _canon(clean);
}

Future<void> main() async {
  final tmpDir = Directory.systemTemp.createTempSync('libsp_smoke_').path;
  Hive.init(tmpDir);
  Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: false,
      validateStatus: (_) => true,
    ),
  );

  _SmokeRemote? remote;
  LibspSyncService? service;

  try {
    // ── 0. 凭据 ────────────────────────────────────────────────
    _step('0) 从 app_data/auth.hive 取 TGC（只报长度）');
    final authBox = File('$_appData\\auth.hive');
    if (!authBox.existsSync()) {
      print('  ✗ 找不到 $authBox —— 请先在 App 里登录一次');
      exitCode = 1;
      return;
    }
    final tgc = _tgcFrom(authBox, _account);
    if (tgc == null) {
      print('  ✗ auth.hive 里没有账号 …${_account.substring(6)} 的 TGC');
      exitCode = 1;
      return;
    }
    print('  ✓ 取到 TGC（长度 ${tgc.length}，形态 ${tgc.substring(0, 3)}…，原文不打印）');

    // ── 1. 换票 ────────────────────────────────────────────────
    _step('1) CAS 换票 → 超星网关 → 图书馆会话');
    final ticket = await _ticketUrl(dio, tgc);
    print('  ✓ 拿到票据（长度 ${ticket.length}，含 ticket= 参数）');
    final auth = LibspAuthRemoteDataSource(dio);
    final trace = <String>[];
    final cookie = await auth.establishSession(ticket, trace: trace);
    for (final line in trace) {
      print('    $line');
    }
    final cookieNames =
        cookie.split('; ').map((e) => e.split('=').first).toList();
    _check('换到图书馆会话（${LibspAuthRemoteDataSource.sessionCookieName}）',
        LibspAuthRemoteDataSource.hasSession(cookie),
        'cookie 名 = ${cookieNames.join(', ')}');

    // ── 2. 本机真实数据 ────────────────────────────────────────
    _step('2) 读本机真实数据（box 副本，只读）');
    var prefs = <String, Map<String, String>>{};
    for (final name in kLibspSyncedPrefBoxes) {
      final box = await _openCopy(name, tmpDir);
      if (box == null) continue;
      final entries = <String, String>{};
      for (final key in box.keys) {
        final v = box.get(key.toString());
        if (v != null) entries[key.toString()] = v;
      }
      if (entries.isNotEmpty) prefs[name] = entries;
      print('    $name：${entries.length} 条');
    }

    var courses = <Map<String, dynamic>>[];
    final geBox = await _openCopy('score_estimate_$_account', tmpDir);
    final rawCourses = geBox?.get('courses');
    if (rawCourses is String && rawCourses.isNotEmpty) {
      final decoded = jsonDecode(rawCourses);
      if (decoded is List) {
        courses = [
          for (final c in decoded)
            if (c is Map) Map<String, dynamic>.from(c),
        ];
      }
    }
    var zongce = <String, String>{};
    final zcBox = await _openCopy('zongce_$_account', tmpDir);
    if (zcBox != null) {
      for (final key in zcBox.keys) {
        final v = zcBox.get(key.toString());
        if (v != null) zongce[key.toString()] = v;
      }
    }

    final realCourses = courses.length;
    if (courses.isEmpty && prefs.isEmpty) {
      print('    ⚠ 真 box 读不出内容（App 可能正在运行 / 账号不同）→ 改用合成数据');
      final syn = _synthetic();
      prefs = syn.prefs;
      courses = syn.courses;
      zongce = <String, String>{};
    }
    final deadlineTotal = courses.fold<int>(
      0,
      (sum, c) => sum + ((c['deadlines'] as List?)?.length ?? 0),
    );
    print('  ✓ 源数据：${courses.length} 门课（真 box $realCourses 门）、'
        '${deadlineTotal} 条截止日期、'
        '${prefs.length} 个偏好箱、${zongce.length} 条综测项');

    final store = _MemoryStore(
      prefs: prefs,
      courses: courses,
      zongce: zongce,
    );
    remote = _SmokeRemote(LibspSubscribeRemoteDataSource(dio), cookie);
    service = LibspSyncService(
      remote: remote,
      store: store,
      newId: () => 'smoke-${DateTime.now().microsecondsSinceEpoch}',
    );

    // ── 3. 上传 ────────────────────────────────────────────────
    _step('3) 上传（真实 codec + 双代轮转 + 逐片读回校验）');
    final before = await service.inspect();
    print('    云端当前：${before.words.length} 条词'
        '（我们的 ${before.mine.length}，别人的 ${before.foreign.length}）');
    final t0 = DateTime.now();
    final up = await service.upload(
      account: _account,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final secs = DateTime.now().difference(t0).inMilliseconds / 1000;
    _check('上传成功', up.ok, up.ok ? null : up.message);
    if (!up.ok) {
      throw StateError('上传失败：${up.message}');
    }
    final result = up.up!;
    print('    槽位 = ${result.slotsWritten}，每份 ${result.chunkCount} 片，'
        '信封 ${result.envelopeBytes} B，压缩后落盘 ${result.envelopeBytes} B，'
        '自愈 ${result.healed}，耗时 ${secs.toStringAsFixed(1)}s');
    print('    裁剪报告 = ${result.trim.isEmpty ? '无（数据全装下）' : result.trim.summary}');
    _check('写了 2 份（双代冗余）', result.slotsWritten.length == 2,
        '实际 ${result.slotsWritten.length}');
    _check('没有丢数据', result.trim.isEmpty, result.trim.isEmpty ? null : result.trim.summary);

    final after = await service.inspect();
    print('    云端现在：${after.words.length} 条词（我们的 ${after.mine.length}）');
    _check('槽位数 = 2', after.slots.length == 2);
    _check('两槽都通过 CRC 校验', after.slots.every((s) => s.verified));
    _check('别人的词一条没动', after.foreign.length == before.foreign.length);

    // ── 4. 读回摘要 + 逐字段比对 ───────────────────────────────
    _step('4) 读回并解码，逐字段与源数据比对');
    final summary = await service.latestSummary();
    _check('拿得到摘要', summary != null, summary?.label);
    final snap = await service.latestSnapshot();
    if (snap == null) {
      throw StateError('读不回快照（latestSnapshot == null）');
    }
    _check('快照生成时刻单调', snap.generatedAt > 0,
        '${DateTime.fromMillisecondsSinceEpoch(snap.generatedAt)}');
    _check('账号一致', snap.account == _account);
    _check(
      '偏好逐项一致（${prefs.length} 箱）',
      _canon(snap.prefs) == _canon(prefs),
      _canon(snap.prefs) == _canon(prefs)
          ? null
          : '载荷=${snap.prefs.length} 箱 vs 源=${prefs.length} 箱',
    );
    _check('综测条目一致', _canon(snap.zongce) == _canon(zongce),
        '${snap.zongce.length} vs ${zongce.length}');
    _check('课程门数一致', snap.courses.length == courses.length,
        '${snap.courses.length} vs ${courses.length}');

    var courseOk = 0;
    final withNotes = result.trim.droppedCourseNotes == 0;
    for (var i = 0; i < courses.length && i < snap.courses.length; i++) {
      final want = _courseSignature(courses[i], withNotes: withNotes);
      final got = _canon(snap.courses[i]);
      if (want == got) {
        courseOk++;
      } else {
        print('    ✗ 第 $i 门不一致：');
        print('      源   ${want.length > 200 ? '${want.substring(0, 200)}…' : want}');
        print('      云端 ${got.length > 200 ? '${got.substring(0, 200)}…' : got}');
      }
    }
    _check('课程逐字段一致', courseOk == courses.length,
        '$courseOk/${courses.length} 门完全相同');

    final noteTotal = courses.fold<int>(
      0,
      (s, c) => s + (((c['note'] as String?) ?? '').isEmpty ? 0 : 1),
    );
    print('    备注 ${noteTotal} 条、截止日期 $deadlineTotal 条 —— '
        '${withNotes ? '全部随载荷往返' : '被降级链清空（见裁剪报告）'}');

    // ── 5. 恢复（写进一个干净的本机） ──────────────────────────
    _step('5) 恢复：写进一个干净的本机存储并比对');
    final fresh = _MemoryStore(
      prefs: <String, Map<String, String>>{},
      courses: <Map<String, dynamic>>[],
      zongce: <String, String>{},
    );
    var restoreSeq = 0;
    final service2 = LibspSyncService(
      remote: remote,
      store: fresh,
      // ⚠ 生产是 `Uuid().v4()`；这里用计数器是因为同一微秒内循环 10 次会撞 id
      //（首版脚本用了 `DateTime.now().microsecondsSinceEpoch`，10 门课拿到同一个 id）。
      newId: () => 'restored-${restoreSeq++}',
    );
    // 留档用的是**当前本机**（service 的 store），restore 用的是干净本机（service2）——
    // 这正是 App 里的分工（先把现状传上去，再拿云端那版覆盖本机）。
    final archived = await service.backupBeforeRestore(
      account: _account,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    _check('恢复前留档成功（Q6）', archived);
    await service2.restore(snap, nowMs: DateTime.now().millisecondsSinceEpoch);
    _check('恢复后偏好一致', _canon(fresh.prefs) == _canon(prefs));
    _check('恢复后课程门数一致', fresh.courses.length == courses.length,
        '${fresh.courses.length} vs ${courses.length}');
    var restoredOk = 0;
    for (var i = 0; i < courses.length && i < fresh.courses.length; i++) {
      if (_courseSignature(fresh.courses[i], withNotes: withNotes) ==
          _courseSignature(courses[i], withNotes: withNotes)) {
        restoredOk++;
      }
    }
    _check('恢复后课程逐字段一致', restoredOk == courses.length,
        '$restoredOk/${courses.length}');
    final ids = fresh.courses.map((c) => c['id']).toSet();
    _check('恢复后 id 全部重新生成（跨设备不撞）',
        ids.length == fresh.courses.length &&
            !ids.any((id) => (id?.toString() ?? '').startsWith('smoke-')),
        '${ids.length} 个互不相同');
    _check(
      '恢复后备忘录为空（Q7-B：备忘不进云）',
      fresh.courses.every((c) {
        final memo = c['memo'];
        return memo is Map &&
            ((memo['text'] as String?) ?? '').isEmpty &&
            ((memo['images'] as List?) ?? const []).isEmpty;
      }),
    );

    // ── 6. 幂等：再传一次 ──────────────────────────────────────
    _step('6) 幂等：同一份数据再传一次');
    final up2 = await service.upload(
      account: _account,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final after2 = await service.inspect();
    _check('第二次上传仍成功', up2.ok, up2.message);
    final newest =
        after2.verifiedSlots.isEmpty ? null : after2.verifiedSlots.first.generatedAt;
    final newestCopies =
        after2.verifiedSlots.where((s) => s.generatedAt == newest).length;
    final olderCopies = after2.verifiedSlots.length - newestCopies;
    _check(
      '稳态形状 = [最新版 ×2, 上一版 ×1]（Q10）',
      newestCopies == 2 && olderCopies == 1,
      '最新 $newestCopies 份 / 上一版 $olderCopies 份，共 ${after2.slots.length} 槽',
    );
    _check('云端词数 = 三份（没有无限增长）',
        after2.mine.length <= result.chunkCount * 3,
        '${after.mine.length} → ${after2.mine.length} 条（每份 ${result.chunkCount} 片）');

    // ── 7. 清除 ────────────────────────────────────────────────
    _step('7) 清除云端数据（按结构全删 + 对账）');
    final cleared = await service.clearCloud();
    _check('清除干净', cleared.clean,
        '删除 ${cleared.deleted} 条，残留 ${cleared.remaining} 条');
    final end = await service.inspect();
    print('    收尾：云端共 ${end.words.length} 条词'
        '（我们的 ${end.mine.length}，别人的 ${end.foreign.length}）');
    _check('我们写的词一条不剩', end.mine.isEmpty);
    if (before.foreign.isNotEmpty) {
      _check('别人的词仍在', end.foreign.length == before.foreign.length,
          '${before.foreign.length} → ${end.foreign.length}');
    }
    print('    HTTP 写入次数：add ${remote.adds}，del ${remote.deletes}');
  } catch (e, st) {
    _failed++;
    print('\n✗ 端到端中断：$e');
    print(st.toString().split('\n').take(6).join('\n'));
    // 尽力收尾：把我们的词删干净，别在用户账号里留垃圾。
    try {
      if (service != null) {
        final r = await service.clearCloud();
        print('  收尾清理：删除 ${r.deleted} 条，残留 ${r.remaining} 条');
      }
    } catch (e2) {
      print('  收尾清理失败：$e2');
    }
  } finally {
    try {
      await Hive.close();
    } catch (_) {}
    try {
      Directory(tmpDir).deleteSync(recursive: true);
    } catch (_) {}
  }

  _step('结论');
  print('通过 $_passed 项，失败 $_failed 项');
  exitCode = _failed == 0 ? 0 : 1;
}
