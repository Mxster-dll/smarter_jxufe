/// 图书馆订阅词云同步 · providers（唯一装配点）。
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/local_data_revision.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_dirty_watch.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_local_store.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_remote_adapter.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_controller.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';

/// 图书馆请求专用 Dio（与其它平台的会话互不干扰）。
final libspDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 25),
      // 自己跟随重定向（换证链要逐跳看 Set-Cookie）。
      followRedirects: false,
      validateStatus: (_) => true,
    ),
  );
});

final libspAuthRemoteDataSourceProvider = Provider<LibspAuthRemoteDataSource>(
  (ref) => LibspAuthRemoteDataSource(ref.watch(libspDioProvider)),
);

final libspSubscribeRemoteDataSourceProvider =
    Provider<LibspSubscribeRemoteDataSource>(
      (ref) => LibspSubscribeRemoteDataSource(ref.watch(libspDioProvider)),
    );

/// 远端端口（会话随用随换，失效只重换一次）。
final libspRemoteProvider = FutureProvider<LibspRemoteAdapter>((ref) async {
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return LibspRemoteAdapter(
    subscribe: ref.watch(libspSubscribeRemoteDataSourceProvider),
    auth: ref.watch(libspAuthRemoteDataSourceProvider),
    authRepository: authRepository,
  );
});

/// 同步服务（本机存储按当前账号隔离）。
final libspSyncServiceProvider = FutureProvider<LibspSyncService>((ref) async {
  final remote = await ref.watch(libspRemoteProvider.future);
  final account = ref.watch(currentAccountProvider);
  return LibspSyncService(
    remote: remote,
    store: HiveLibspLocalStore(account: account),
    newId: () => const Uuid().v4(),
  );
});

/// 控制器（界面唯一入口）。
///
/// 在这里装配「本机有改动」监听：白名单 box（6 个偏好 + 账号级分数估计）一旦被写
/// → 控制器开 60s 防抖窗口 → 到点自动上传（Q12）。监听失败只降级成「没有防抖」
/// （回前台对账那条路仍在），绝不阻塞界面。
///
/// 另外装配「恢复之后叫醒页面」：偏好 store 自己订阅了 box（`BoxReloadWatcher`），
/// 写盘即跟上；而分数估计 / 综测这类**把数据读进自己 State** 的页面不会自己知道，
/// 靠这个版本号让它们重读（用户 2026-09-17 报「恢复后设置不会变」的同源问题）。
final libspSyncControllerProvider = ChangeNotifierProvider<LibspSyncController>(
  (ref) {
    final controller = LibspSyncController(
      service: () => ref.read(libspSyncServiceProvider.future),
      prefs: ref.read(libspSyncPrefsProvider.notifier),
      gate: ref.watch(libspSyncGateProvider),
      account: () => ref.read(currentAccountProvider),
      onRestored: () => ref.read(localDataRevisionProvider.notifier).bump(),
    );
    final watcher = LibspDirtyWatcher(
      account: ref.read(currentAccountProvider),
      onDirty: controller.markDirty,
    );
    controller.dirtyWatcher = watcher;
    unawaited(watcher.start());
    ref.onDispose(() => unawaited(watcher.dispose()));
    return controller;
  },
);
