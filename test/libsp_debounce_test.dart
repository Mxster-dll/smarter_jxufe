// 图书馆订阅词云同步 · 「防抖触发」守卫（Q12 的自动化那半条腿）。
//
// 守住两件事：
// 1. **改动从哪来**：`LibspDirtyWatcher` 监听的是 Hive box 本身，所以任何写入路径
//    （偏好 6 个箱 + 账号级分数估计箱）都会通知一次 —— 包括以后新增的写入路径；
// 2. **改动之后什么时候传**：`LibspSyncController.markDirty()` 只开一个防抖窗口，
//    窗口内再改**顺延**；到点才走一次真上传，且仍受 `LibspSyncGate` 约束。
//
// ⚠ 这两组都用**真时钟**的 `test()`（不 `testWidgets`）：链路里含真实 Hive 文件 I/O，
// 而 `testWidgets` 的假异步区里真 I/O 的回调永远等不到（首版这么写，整轮测试挂死）。
// 生产默认 60s 的约定用「常量 + 默认参数」断言，不用真等 60 秒。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_dirty_watch.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_controller.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';

import 'libsp_sync_test.dart' show FakeRemote, FakeStore;

/// 测试用的防抖窗口（比生产短，留足调度余量）。
const Duration _fast = Duration(milliseconds: 300);

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late Directory dir;

  // ⚠ 用本仓既有的 Hive 测试口径（见 `libsp_store_test.dart`）：**整个文件一个临时目录**
  // + 每个测试 `deleteFromDisk()` 清箱。别在每个测试里 `Hive.init` 一个新目录 ——
  // 上一个测试打开的 box 会留在 Hive 的缓存里，路径与断言都会串味（首版踩到，测试挂死）。
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('libsp_dirty_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> settle() => _wait(80);

  group('LibspDirtyWatcher（改动从哪来）', () {
    test('白名单 box 被写入 → 通知一次（连续两次写 → 两次）', () async {
      var hits = 0;
      final watcher = LibspDirtyWatcher(
        account: 'A',
        onDirty: () => hits++,
        boxNames: const ['themePrefs'],
      );
      await watcher.start();
      final box = await Hive.openBox<String>('themePrefs');

      await box.put('themeMode', 'dark');
      await settle();
      expect(hits, 1, reason: '深色模式这种偏好写完就该被看见');

      await box.put('themeMode', 'light');
      await settle();
      expect(hits, 2);

      await watcher.dispose();
    });

    test('账号级分数估计 box 被写入也算改动（主要数据）', () async {
      var hits = 0;
      final watcher = LibspDirtyWatcher(
        account: 'A',
        onDirty: () => hits++,
        boxNames: const [],
      );
      await watcher.start();
      final box = await Hive.openBox<String>('score_estimate_A');

      await box.put('courses', '[]');
      await settle();
      expect(hits, 1, reason: '分数估计是这套同步存在的理由，必须被监听');

      // 别的账号的 box 不该惊动我们。
      final other = await Hive.openBox<String>('score_estimate_B');
      await other.put('courses', '[]');
      await settle();
      expect(hits, 1, reason: '只监听当前账号的箱');

      await watcher.dispose();
    });

    test('pauseWhile 期间（恢复本机数据）不通知，结束后恢复通知', () async {
      var hits = 0;
      final watcher = LibspDirtyWatcher(
        account: 'A',
        onDirty: () => hits++,
        boxNames: const ['themePrefs'],
      );
      await watcher.start();
      final box = await Hive.openBox<String>('themePrefs');

      final returned = await watcher.pauseWhile(() async {
        await box.put('themeMode', 'dark');
        await settle();
        return 'done';
      });
      expect(returned, 'done');
      expect(hits, 0, reason: '恢复自己写的事件不能被当成「本机新改动」');

      await box.put('themeMode', 'light');
      await settle();
      expect(hits, 1, reason: '暂停结束后要恢复监听');

      await watcher.dispose();
    });

    test('dispose 之后不再通知', () async {
      var hits = 0;
      final watcher = LibspDirtyWatcher(
        account: 'A',
        onDirty: () => hits++,
        boxNames: const ['themePrefs'],
      );
      await watcher.start();
      final box = await Hive.openBox<String>('themePrefs');
      await watcher.dispose();

      await box.put('themeMode', 'dark');
      await settle();
      expect(hits, 0);
    });

    test('start 幂等：重复调用不叠加监听（否则一次改动通知多次）', () async {
      var hits = 0;
      final watcher = LibspDirtyWatcher(
        account: 'A',
        onDirty: () => hits++,
        boxNames: const ['themePrefs'],
      );
      await watcher.start();
      await watcher.start();
      await watcher.start();
      final box = await Hive.openBox<String>('themePrefs');

      await box.put('themeMode', 'dark');
      await settle();
      expect(hits, 1);

      await watcher.dispose();
    });
  });

  group('LibspSyncController · 防抖（改动之后什么时候传）', () {
    /// 造一个控制器；[enabled] 决定是否已 opt-in。
    Future<(LibspSyncController, FakeRemote)> build({
      bool enabled = true,
      Duration debounce = _fast,
      int? failAfterAdds,
    }) async {
      final prefs = LibspSyncPrefsStore();
      await prefs.ensureLoaded();
      if (enabled) await prefs.setEnabled(true);
      final remote = FakeRemote();
      if (failAfterAdds != null) remote.failAfterAdds = failAfterAdds;
      final controller = LibspSyncController(
        service: () async => LibspSyncService(
          remote: remote,
          store: FakeStore(),
          newId: () => 'test-id',
        ),
        prefs: prefs,
        gate: const LibspSyncGate(),
        account: () => '2000000000',
        clock: () => DateTime(2026, 9, 17, 12),
        debounce: debounce,
      );
      return (controller, remote);
    }

    test('生产默认窗口 = 60 秒（Q12），且控制器默认就取它', () async {
      expect(libspMinUploadInterval, const Duration(seconds: 60));
      final (controller, _) = await build(debounce: _fast);
      expect(controller.debounce, _fast, reason: '注入生效');
      // 不注入时取常量。
      final plain = LibspSyncController(
        service: () async => LibspSyncService(
          remote: FakeRemote(),
          store: FakeStore(),
          newId: () => 'x',
        ),
        prefs: LibspSyncPrefsStore(),
        gate: const LibspSyncGate(),
        account: () => 'a',
      );
      expect(plain.debounce, libspMinUploadInterval);
      plain.dispose();
      controller.dispose();
    });

    test('markDirty 后要等满窗口才上传；窗口内再改只顺延', () async {
      final (controller, remote) = await build();
      addTearDown(controller.dispose);

      controller.markDirty();
      expect(controller.dirty, isTrue);

      await _wait(150);
      expect(remote.addCount, 0, reason: '窗口没到就不该发请求');

      controller.markDirty(); // 第 150ms 又改了一次 → 重新计时
      await _wait(200);
      expect(remote.addCount, 0, reason: '距最后一次改动只有 200ms，不该上传');

      await _wait(500);
      expect(remote.addCount, greaterThan(0), reason: '窗口到点应有一次真上传');
      expect(controller.dirty, isFalse, reason: '上传成功后「待同步」要落下');
    });

    test('未开启同步时，防抖到点也不上传（opt-in 优先）', () async {
      final (controller, remote) = await build(enabled: false);
      addTearDown(controller.dispose);

      controller.markDirty();
      await _wait(700);
      expect(remote.addCount, 0, reason: '没开启就一个字节都不能上传');
      expect(controller.status, LibspSyncStatus.idle);
    });

    test('dispose 后待发的防抖不再触发（不留悬挂定时器）', () async {
      final (controller, remote) = await build();
      controller.markDirty();
      controller.dispose();
      await _wait(700);
      expect(remote.addCount, 0);
    });

    test('上传失败：状态回落 failed、dirty 保留（还等着下次传）', () async {
      final (controller, remote) = await build(failAfterAdds: 0);
      addTearDown(controller.dispose);

      controller.markDirty();
      await _wait(700);
      expect(controller.status, LibspSyncStatus.failed);
      expect(controller.dirty, isTrue, reason: '没传上去就还是「待同步」');
      expect(controller.message, isNotNull);
      expect(remote.addCount, 0);
    });
  });
}
