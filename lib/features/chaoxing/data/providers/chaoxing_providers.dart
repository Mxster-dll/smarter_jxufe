/// 学习通 · providers（唯一装配点）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_gate.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_repository.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_store.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_mooc_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_notice_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_sign_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';

/// 学习通请求专用 Dio（与其它平台的会话互不干扰）。
///
/// `followRedirects: false`：换证链要**逐跳**看 `Set-Cookie` 与 `Location`
/// （Cookie 归属哪个域只有服务端知道，交给 Dio 自动跟就跟丢了）。
final chaoxingDioProvider = Provider<Dio>((ref) {
  return createAppDio(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    sendTimeout: const Duration(seconds: 25),
    followRedirects: false,
  );
});

final chaoxingHttpClientProvider = Provider<ChaoxingHttpClient>(
  (ref) => ChaoxingHttpClient(ref.watch(chaoxingDioProvider)),
);

final chaoxingAuthRemoteDataSourceProvider = Provider<ChaoxingAuthRemoteDataSource>(
  (ref) => ChaoxingAuthRemoteDataSource(ref.watch(chaoxingHttpClientProvider)),
);

final chaoxingMoocRemoteDataSourceProvider = Provider<ChaoxingMoocRemoteDataSource>(
  (ref) => ChaoxingMoocRemoteDataSource(ref.watch(chaoxingHttpClientProvider)),
);

final chaoxingNoticeRemoteDataSourceProvider = Provider<ChaoxingNoticeRemoteDataSource>(
  (ref) => ChaoxingNoticeRemoteDataSource(ref.watch(chaoxingHttpClientProvider)),
);

final chaoxingSignRemoteDataSourceProvider = Provider<ChaoxingSignRemoteDataSource>(
  (ref) => ChaoxingSignRemoteDataSource(ref.watch(chaoxingHttpClientProvider)),
);

/// 快照缓存（**按账号隔离**：box 名 `chaoxing_<账号>`）。
final chaoxingStoreProvider = FutureProvider<ChaoxingStore>(
  (ref) async => ChaoxingStore(
    await openAccountScopedBox(kChaoxingBoxName, ref.watch(currentAccountProvider)),
  ),
);

/// 仓库（会话 + 并发扫描 + 缓存）。
///
/// `currentTermCode` = **当下学期**的学期码（`261`），由校历口径的
/// `currentSchoolTerm()` 推出 —— 仓库据此**只扫当下学期**（作业是唯一没有统一
/// 接口的数据，逐课 2 请求，全扫必然撞风控；见 `domain/chaoxing_scan.dart`）。
/// 拿不到学期时传空串 = 不筛（退回全课程轮转）。
final chaoxingRepositoryProvider = FutureProvider<ChaoxingRepository>((ref) async {
  final authRepository = await ref.watch(authRepositoryProvider.future);
  final term = currentSchoolTerm(
    DateTime.now(),
    terms: ref.watch(offlineSemesterTermsProvider),
  );
  return ChaoxingRepository(
    auth: ref.watch(chaoxingAuthRemoteDataSourceProvider),
    mooc: ref.watch(chaoxingMoocRemoteDataSourceProvider),
    notice: ref.watch(chaoxingNoticeRemoteDataSourceProvider),
    sign: ref.watch(chaoxingSignRemoteDataSourceProvider),
    fetchTicket: authRepository.getServiceRedirectUrl,
    store: await ref.watch(chaoxingStoreProvider.future),
    currentTermCode: schoolTermCode(term.xn, term.xq),
  );
});

/// 刷新闸门（**非 autoDispose**：1 分钟窗口必须跨越页面重建）。
final chaoxingRefreshGateProvider = Provider<ChaoxingRefreshGate>(
  (ref) => ChaoxingRefreshGate(),
);

/// 取数进度（`null` = 空闲）。
class ChaoxingProgressNotifier extends Notifier<ChaoxingProgress?> {
  @override
  ChaoxingProgress? build() => null;

  /// 更新进度 / 置空。
  void set(ChaoxingProgress? progress) {
    if (progress == null) {
      state = null;
      return;
    }
    // 只有阶段或计数真的变了才发通知（34 门课 = 34 次，别让无关重建翻倍）。
    final old = state;
    if (old != null &&
        old.phase == progress.phase &&
        old.done == progress.done &&
        old.total == progress.total) {
      return;
    }
    state = progress;
  }
}

final chaoxingProgressProvider =
    NotifierProvider<ChaoxingProgressNotifier, ChaoxingProgress?>(
      ChaoxingProgressNotifier.new,
    );

/// 页面数据控制器：先给缓存，再由 [ChaoxingController.refresh] 更新。
class ChaoxingController extends AsyncNotifier<ChaoxingSnapshot> {
  @override
  Future<ChaoxingSnapshot> build() async {
    final repository = await ref.watch(chaoxingRepositoryProvider.future);
    final cached = await repository.cached();
    return cached ?? ChaoxingSnapshot.empty;
  }

  /// 正在进行的那一次取数（**单飞**：同一时刻只允许一次全扫）。
  Future<void>? _inFlight;

  /// 全量取数（课程 + 全部课程作业 + 通知）。
  ///
  /// 失败**不抛出**：落成 `AsyncError` 并保留上一份数据（`copyWithPrevious`），
  /// 界面据此显示「数据可能是旧的 + 一条错误提示」，而不是整页白掉。
  /// [force] = true 时忽略仓库的风控冷却（**手动下拉 / 点刷新**用）。
  ///
  /// ⚠ **单飞理由**（实测 2026-09-20）：页面侧有三条触发路径（首帧 `post-frame`
  /// 自动刷新、`RouteAware.didPopNext`、`_openChild().then`），闸门只在**取到新数据后**
  /// 才记账，所以「刚失败 / 刚进页面」时拦不住重复触发。两次全扫各自要打 ~40 个请求，
  /// 既双双撞进学习通风控，又会先后落盘两份残缺快照（实测两帧相差 280 ms：
  /// works=13 与 works=29），后写的那份盖掉前一份。已在飞的那次直接复用即可。
  Future<void> refresh({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _refreshOnce(force: force);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<void> _refreshOnce({required bool force}) async {
    final repository = await ref.read(chaoxingRepositoryProvider.future);
    // ⚠ **previous 不能只看内存**：首帧自动刷新会在 `build()` 读完缓存**之前**触发，
    // 那时 `state` 还停在 loading、`valueOrNull` 是 null —— 仓库那套「只信扫成功、
    // 其余沿用 previous」的兜底会整条失效，本轮没扫到的课（分批轮转的窗口外 /
    // 撞风控后收手）连**缓存里已有的作业一起丢**。实测 2026-09-20：线性代数的作业
    // 就是这样从界面上消失的，而它明明就在磁盘缓存里。所以要回落到磁盘缓存。
    final previous = state.valueOrNull ?? await repository.cached();
    final progress = ref.read(chaoxingProgressProvider.notifier);

    state = const AsyncValue<ChaoxingSnapshot>.loading().copyWithPrevious(state);
    try {
      final snapshot = await repository.refresh(
        previous: previous,
        onProgress: progress.set,
        force: force,
      );
      state = AsyncValue<ChaoxingSnapshot>.data(snapshot);
      ref.read(chaoxingRefreshGateProvider).markUpdated();
    } catch (e, st) {
      state = AsyncValue<ChaoxingSnapshot>.error(e, st).copyWithPrevious(
        AsyncValue<ChaoxingSnapshot>.data(previous ?? ChaoxingSnapshot.empty),
      );
    } finally {
      progress.set(null);
    }
  }

  /// 只重取通知（成本 1 个请求）—— 通知段单独刷新时用。
  Future<void> refreshNoticesOnly() async {
    final repository = await ref.read(chaoxingRepositoryProvider.future);
    final previous = state.valueOrNull;
    if (previous == null) return;
    final notices = await repository.fetchNoticesOnly();
    if (notices == null) return;
    state = AsyncValue<ChaoxingSnapshot>.data(
      previous.copyWith(notices: notices, noticesAvailable: true),
    );
    ref.read(chaoxingRefreshGateProvider).markUpdated();
  }

  /// **按需**取一条签到活动的状态（成本 1 个请求）。
  ///
  /// 用于「点开某条签到」：清单接口不给我自己的状态（见 `chaoxing_sign.dart`），
  /// 所以状态是**点开才补**的。已有结论（`statusLoaded`）的条目不再重复请求。
  /// 失败不抛出，返回 false（界面照旧显示「状态未知」）。
  Future<bool> loadSignDetail(ChaoxingSign sign) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (sign.statusLoaded) return true;
    final repository = await ref.read(chaoxingRepositoryProvider.future);
    try {
      final next = await repository.refreshSignDetail(current, sign);
      state = AsyncValue<ChaoxingSnapshot>.data(next);
      return true;
    } catch (e) {
      debugPrint('[chaoxing] 签到 ${sign.key} 状态取数失败：$e');
      return false;
    }
  }

  /// **手动全量更新签到**（清单 + 我的状态；见仓库的 `refreshSignsFull`）。
  ///
  /// ⚠ 这是本模块唯一可能一次发几十个请求的入口（≈60 个/窗口就撞风控），
  /// 所以只由用户点按钮触发，并如实回报「撞风控就停、已拿到的照算」。
  Future<void> refreshSignsFull({bool allCourses = false}) async {
    final repository = await ref.read(chaoxingRepositoryProvider.future);
    final previous = state.valueOrNull;
    if (previous == null) return;
    final progress = ref.read(chaoxingProgressProvider.notifier);
    try {
      final next = await repository.refreshSignsFull(
        previous,
        allCourses: allCourses,
        onProgress: progress.set,
      );
      state = AsyncValue<ChaoxingSnapshot>.data(next);
      ref.read(chaoxingRefreshGateProvider).markUpdated();
    } catch (e, st) {
      state = AsyncValue<ChaoxingSnapshot>.error(e, st).copyWithPrevious(
        AsyncValue<ChaoxingSnapshot>.data(previous),
      );
    } finally {
      progress.set(null);
    }
  }

  /// 丢弃会话与缓存（「清除本机学习通数据」）。
  Future<void> clear() async {
    final repository = await ref.read(chaoxingRepositoryProvider.future);
    repository.invalidateSession();
    await repository.store.clear();
    state = const AsyncValue<ChaoxingSnapshot>.data(ChaoxingSnapshot.empty);
  }
}

final chaoxingControllerProvider =
    AsyncNotifierProvider<ChaoxingController, ChaoxingSnapshot>(
      ChaoxingController.new,
    );

/// 当前快速状态（概览卡与磁贴角标用）：待做作业数 / 未读通知数。
final chaoxingBadgeProvider = Provider<({int todo, int unread})>((ref) {
  final snapshot = ref.watch(chaoxingControllerProvider).valueOrNull;
  return (
    todo: snapshot?.todoCount ?? 0,
    unread: snapshot?.unreadNoticeCount ?? 0,
  );
});
