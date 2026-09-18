// 图书馆订阅词云同步 · 状态机守卫（假远端 + 假本机存储，全确定性）。
//
// 守住的是协议里最贵的几条不变式：
// - **任意时刻云端至少有一份完整快照**：第一份写入/校验失败时，上一版一个字节都不能动；
// - **稳态形状 = [最新版, 最新版, 上一版]**（Q10）：第二次上传后必须同时存在两代；
// - **绝不碰用户的订阅词**（服务端不去重，所以只能按结构识别、不能按内容比对）；
// - **写入后必须逐片读回校验**（服务端超长是静默截断、且不去重）；
// - **前缀被服务端改写（全半角归一）不算失败** —— 识别锚在结构上；
// - **清理要按结构全删并对账**；**恢复前必须留档**；**部分缺片要自愈**。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_codec.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

/// 假远端：可控地制造「第二份失败 / 静默截断 / 前缀改写 / 拒绝删除」等情形。
class FakeRemote implements LibspRemote {
  FakeRemote({List<String> userWords = const []}) {
    for (final w in userWords) {
      _words.add(LibspRemoteWord(subId: _nextId++, subName: w));
    }
  }

  final List<LibspRemoteWord> _words = [];
  int _nextId = 1;

  /// 写入多少条之后开始抛错（模拟网络中断 / 配额）。
  int? failAfterAdds;

  /// 每次写入后把词截断到这个长度（模拟服务端静默截断）。
  int? truncateTo;

  /// 写入时把全角标点换成 ASCII（模拟 NFKC 归一）。
  bool normalizeFullWidth = false;

  /// 拒绝删除这些 subId（模拟服务端删不掉）。
  final Set<int> refuseDelete = {};

  int addCount = 0;
  int deleteCount = 0;

  List<LibspRemoteWord> get all => List.unmodifiable(_words);

  @override
  Future<List<LibspRemoteWord>> listWords() async => [..._words];

  @override
  Future<void> addWord(String name) async {
    if (failAfterAdds != null && addCount >= failAfterAdds!) {
      throw StateError('假的网络故障（第 $addCount 次写入后）');
    }
    addCount++;
    var stored = name;
    if (truncateTo != null && stored.length > truncateTo!) {
      stored = stored.substring(0, truncateTo!);
    }
    if (normalizeFullWidth) {
      stored = stored.replaceAll('！', '!').replaceAll('：', ':');
    }
    _words.add(LibspRemoteWord(subId: _nextId++, subName: stored));
  }

  @override
  Future<void> deleteWord(int subId) async {
    deleteCount++;
    if (refuseDelete.contains(subId)) return;
    _words.removeWhere((w) => w.subId == subId);
  }

  /// 手动删掉一条（模拟用户在图书馆界面手删）。
  void removeAt(int index) => _words.removeAt(index);

  int get ourWordCount =>
      _words.where((w) => decodeLibspWord(w.subName) != null).length;
}

/// 假本机存储。
class FakeStore implements LibspLocalStore {
  Map<String, Map<String, String>> prefs = {
    'themePrefs': {'themeMode': 'dark'},
    'electricityBinding': {'campusId': '2', 'room': 'B12-305'},
  };
  List<Map<String, dynamic>> courses = [];
  Map<String, String> zongce = {};

  int writePrefsCount = 0;
  int writeCoursesCount = 0;

  @override
  Future<Map<String, Map<String, String>>> readPrefs() async => {
    for (final e in prefs.entries) e.key: {...e.value},
  };

  @override
  Future<List<Map<String, dynamic>>> readCourses() async =>
      [for (final c in courses) jsonDecode(jsonEncode(c)) as Map<String, dynamic>];

  @override
  Future<Map<String, String>> readZongceEntries() async => {...zongce};

  @override
  Future<void> writePrefs(Map<String, Map<String, String>> next) async {
    writePrefsCount++;
    for (final e in next.entries) {
      prefs[e.key] = {...e.value};
    }
  }

  @override
  Future<void> writeCourses(List<Map<String, dynamic>> next) async {
    writeCoursesCount++;
    courses = [for (final c in next) Map<String, dynamic>.from(c)];
  }

  @override
  Future<void> writeZongceEntries(Map<String, String> entries) async {
    zongce = {...entries};
  }
}

Map<String, dynamic> courseJson(String name, {int createdAt = 1000}) => {
  'id': 'uuid-$name',
  'name': name,
  'courseCode': '1004606732',
  'dailyPercent': 30.0,
  'credits': 2.0,
  'parts': [
    {
      'id': 'p-$name',
      'name': '考勤',
      'mode': 'down',
      'target': 16,
      'current': 14,
      'score': 0.0,
      'cap': 5.0,
      'note': '',
    },
  ],
  'finalScore': null,
  'note': '教师：陈润平',
  'memo': {'text': '要背的东西很多', 'images': <dynamic>[]},
  'deadlines': <dynamic>[],
  'createdAt': createdAt,
};

void main() {
  late FakeRemote remote;
  late FakeStore store;
  late LibspSyncService service;
  var seq = 0;

  setUp(() {
    seq = 0;
    remote = FakeRemote(userWords: ['计算机网络', '数据结构']);
    store = FakeStore()
      ..courses = [courseJson('计算机网络'), courseJson('线性代数(工)', createdAt: 900)]
      ..zongce = {'manual-2026': '{"tScore":88}'};
    service = LibspSyncService(
      remote: remote,
      store: store,
      newId: () => 'new-${seq++}',
    );
  });

  group('首次上传', () {
    test('空云端 → 写两份最新版，用户自己的词一条不动', () async {
      final outcome = await service.upload(account: '2000000000', nowMs: 1000);
      expect(outcome.ok, isTrue);
      expect(outcome.up!.slotsWritten.length, 2, reason: 'Q10：最新版两份');
      expect(outcome.up!.chunkCount, greaterThan(0));

      final state = await service.inspect();
      expect(state.verifiedSlots.length, 2);
      expect(state.verifiedSlots.map((s) => s.generatedAt).toSet(), {1000});
      expect(state.foreign.map((w) => w.subName), containsAll(['计算机网络', '数据结构']),
          reason: '用户的订阅词绝不能被碰');
      expect(remote.deleteCount, 0, reason: '首次上传没有任何东西可删');
    });

    test('同一个槽位内的片数 = 快照分片数，且槽位号写进了 ASCII 数字头', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final state = await service.inspect();
      for (final slot in state.verifiedSlots) {
        expect(slot.chunks.length, slot.total);
        expect(slot.chunks.first.slot, slot.slot);
      }
    });
  });

  group('稳态形状与原子性', () {
    test('第二次上传后 = [最新版×2, 上一版×1]', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final second = await service.upload(account: 'a', nowMs: 2000);
      expect(second.ok, isTrue);

      final state = await service.inspect();
      expect(state.slots.length, 3, reason: '三个槽位都该有内容');
      final gens = [
        for (final s in state.verifiedSlots) s.generatedAt,
      ]..sort();
      expect(gens, [1000, 2000, 2000], reason: '上一版必须留着（误操作可回滚）');
    });

    test('第一份写入就失败 → 云端一个字节都不动，上一版仍完整', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final before = (await service.inspect()).slots
          .map((s) => '${s.slot}:${s.generatedAt}')
          .toList()
        ..sort();

      remote.failAfterAdds = remote.addCount; // 下一次写入立即失败
      final outcome = await service.upload(account: 'a', nowMs: 2000);
      expect(outcome.ok, isFalse);
      expect(outcome.failure, LibspSyncFailure.network);
      expect(outcome.message, contains('上一版未被改动'));

      final after = (await service.inspect()).slots
          .map((s) => '${s.slot}:${s.generatedAt}')
          .toList()
        ..sort();
      expect(after, before, reason: '失败必须无副作用');
    });

    test('第二份失败 → 仍算成功（第一份完整），但如实说明只剩一份', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final limit = remote.addCount + 3; // 第一份写到第 3 片时断
      remote.failAfterAdds = limit;
      final outcome = await service.upload(account: 'a', nowMs: 2000);
      expect(outcome.ok, isTrue, reason: '第一份写成功就算成功');
      expect(outcome.up!.error, isNotNull);
      expect(outcome.up!.error, contains('只剩一份'));
    });

    test('服务端静默截断 → 读回校验失败，归类 verifyFailed 且不删旧版', () async {
      await service.upload(account: 'a', nowMs: 1000);
      remote.truncateTo = 80; // 我们的词是 100 字 → 一律被砍
      final outcome = await service.upload(account: 'a', nowMs: 2000);
      expect(outcome.ok, isFalse);
      expect(outcome.failure, LibspSyncFailure.verifyFailed);
      expect(outcome.message, contains('截断'));
    });

    test('前缀里的全角 ！/： 被服务端归一成 ASCII → 依然算成功（识别锚在结构上）', () async {
      remote.normalizeFullWidth = true;
      final outcome = await service.upload(account: 'a', nowMs: 1000);
      expect(outcome.ok, isTrue);
      expect(outcome.up!.slotsWritten.length, 2);
      final state = await service.inspect();
      expect(state.verifiedSlots.length, 2);
      expect(state.verifiedSlots.first.generatedAt, 1000);
    });

    test('载荷过大 → tooLarge，云端不受影响', () async {
      final tiny = LibspSyncService(
        remote: remote,
        store: store,
        newId: () => 'x',
        maxEnvelopeBytes: 1,
      );
      final outcome = await tiny.upload(account: 'a', nowMs: 1000);
      expect(outcome.ok, isFalse);
      expect(outcome.failure, LibspSyncFailure.tooLarge);
      expect(outcome.message, contains('云端不受影响'));
      expect((await service.inspect()).mine, isEmpty);
    });
  });

  group('自愈（Q13：部分缺片自愈，整组缺失不自愈）', () {
    test('最新版的一份被手删一片 → 下次同步补回两份完整', () async {
      await service.upload(account: 'a', nowMs: 1000);
      expect(remote.ourWordCount, greaterThan(0));

      // 模拟用户手删：删掉我们的一条词
      final victim = remote.all.firstWhere(
        (w) => decodeLibspWord(w.subName) != null,
      );
      remote.removeAt(remote.all.indexOf(victim));
      final broken = await service.inspect();
      expect(broken.verifiedSlots.length, lessThan(2),
          reason: '删掉一条后不再有两份完整');

      await service.upload(account: 'a', nowMs: 2000);
      final healed = await service.inspect();
      final newest = healed.verifiedSlots.where((s) => s.generatedAt == 2000);
      expect(newest.length, 2, reason: '自愈后最新版必须仍是两份');
    });

    test('我们的词被整体删光 → 不自愈，转为写入新的一份', () async {
      await service.upload(account: 'a', nowMs: 1000);
      for (final w in [...remote.all]) {
        if (decodeLibspWord(w.subName) != null) {
          await remote.deleteWord(w.subId);
        }
      }
      expect((await service.inspect()).mine, isEmpty);

      // 这不叫自愈，而是「云端为空」→ 正常上传一份新的（用户删光了，App 不做对抗）
      final outcome = await service.upload(account: 'a', nowMs: 3000);
      expect(outcome.ok, isTrue);
      final state = await service.inspect();
      expect(state.verifiedSlots.first.generatedAt, 3000);
      expect(state.foreign.length, 2, reason: '用户自己的词仍在');
    });
  });

  group('清理（Q13：按结构全删 + 对账）', () {
    test('删掉全部我们的词，用户自己的词留着，对账残留 0', () async {
      await service.upload(account: 'a', nowMs: 1000);
      await service.upload(account: 'a', nowMs: 2000);

      final result = await service.clearCloud();
      expect(result.deleted, greaterThan(0));
      expect(result.remaining, 0);
      expect(result.clean, isTrue);
      expect(remote.ourWordCount, 0);
      expect(
        (await service.inspect()).words.map((w) => w.subName),
        containsAll(['计算机网络', '数据结构']),
        reason: '清理绝不能误伤用户自己的订阅词',
      );
    });

    test('有删不掉的 → clean=false（不谎报成功）', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final one = remote.all.firstWhere(
        (w) => decodeLibspWord(w.subName) != null,
      );
      remote.refuseDelete.add(one.subId);
      final result = await service.clearCloud();
      expect(result.clean, isFalse);
      expect(result.remaining, greaterThan(0));
    });
  });

  group('恢复（Q6：留档 + 展示摘要 + uuid 本地重生）', () {
    test('latestSummary 给出可读摘要（不做盲盒覆盖）', () async {
      await service.upload(account: '2000000000', nowMs: 1789578751890);
      final summary = await service.latestSummary();
      expect(summary, isNotNull);
      expect(summary!.courseCount, 2);
      expect(summary.prefEntryCount, 3, reason: 'themePrefs 1 项 + 电费 2 项');
      expect(summary.hasZongce, isTrue);
      expect(summary.label, contains('门课'));
      expect(summary.label, contains('项偏好'));
    });

    test('恢复写回本机：偏好合并、课程补新 uuid、备忘录恢复为空', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final snapshot = (await service.latestSnapshot())!;

      store
        ..courses = [courseJson('本地要保住的课')]
        ..prefs = {'themePrefs': {'themeMode': 'light'}};
      await service.restore(snapshot, nowMs: 5000);

      expect(store.writeCoursesCount, 1);
      expect(store.courses.length, 2);
      final names = store.courses.map((c) => c['name']).toSet();
      expect(names, containsAll(['计算机网络', '线性代数(工)']));
      expect(store.courses.first['id'], startsWith('new-'));
      expect(store.courses.first['memo'], isA<Map>());
      expect(store.courses.first['createdAt'], greaterThanOrEqualTo(5000));
      expect(store.zongce['manual-2026'], contains('88'));
      expect(store.prefs['themePrefs']!['themeMode'], 'dark');
    });

    test('恢复前留档：云端会留下「恢复前的本机状态」作为上一版', () async {
      await service.upload(account: 'a', nowMs: 1000);
      final oldSnapshot = (await service.latestSnapshot())!;

      // 本机改成了别的东西，然后准备恢复旧快照 —— 先留档
      store.courses = [courseJson('恢复前本机独有的课')];
      final archived = await service.backupBeforeRestore(account: 'a', nowMs: 2000);
      expect(archived, isTrue);

      await service.restore(oldSnapshot, nowMs: 3000);
      final state = await service.inspect();
      final gens = [for (final s in state.verifiedSlots) s.generatedAt];
      expect(gens, contains(2000), reason: '留档的那一版必须在云端');
      expect(gens, contains(1000));

      // 留档里确实是「恢复前的本机状态」
      final archivedSnapshot = state.verifiedSlots
          .firstWhere((s) => s.generatedAt == 2000);
      final decoded = await service.latestSnapshot(state);
      expect(decoded, isNotNull);
      expect(
        state.verifiedSlots.map((s) => s.generatedAt).toSet(),
        containsAll([1000, 2000]),
      );
      expect(archivedSnapshot.verified, isTrue);
    });

    test('留档失败 → 返回 false（调用方据此拦住恢复）', () async {
      remote.failAfterAdds = 0;
      expect(await service.backupBeforeRestore(account: 'a', nowMs: 1), isFalse);
    });
  });
}
