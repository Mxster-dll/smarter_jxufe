/// 学习通取数编排 —— 会话管理 + 并发扫描 + 缓存。
///
/// 四件事收在这一处：
/// 1. **会话**：首次用到才换票（`TGC → CAS → 超星网关 → 学习空间`），
///    真失效时**只重换一次**再重试（口径同 `libsp_remote_adapter` / §12.2）；
/// 2. **并发**：34 门课 × 2 请求串行要 20 秒以上，这里开 [concurrency]（默认 4）
///    条流水线，并**逐课容错**（某课失败只记进 `failedCourseKeys`，不拖垮整次刷新）；
/// 3. **缓存**：只有「取全了」才落 Hive（按账号隔离），失败不覆盖旧数据；
/// 4. **风控**：命中验证码页（见 `ChaoxingHttpClient.ensureUsable`）→ 立刻收手、
///    整次作废、冷却 [challengeCooldown]，期间不自动重试。
///
/// ⚠ 成本控制的第一手段是**缩小范围**（[currentTermCode]：只扫当下学期，
/// 35 门 → 12 门 = 24 个请求），不是分批轮转 —— 作业是学习通里唯一没有统一接口的
/// 数据，逐课 2 请求，全扫必然撞预算。详见 `domain/chaoxing_scan.dart`。
library;

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_limits.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_store.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_mooc_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_notice_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/data/datasources/chaoxing_sign_remote_datasource.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_scan.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

/// 取票端口 —— `AuthRepository.getServiceRedirectUrl` 的形状。
///
/// 只取这一个方法而不是整个 `AuthRepository`：仓库要的只是「给我一张带 ticket 的
/// 回调地址」，用函数接缝后单测可以直接喂假票据（`libsp` 那边传整个 repository，
/// 于是它的适配器只能靠真网络验证）。
typedef ChaoxingTicketFetcher =
    Future<Either<Failure, String>> Function(String casLoginUrl);

/// 取数阶段（界面据此显示「正在更新 12/34」）。
enum ChaoxingPhase {
  /// 换证建会话。
  session,

  /// 拉课程清单。
  courses,

  /// 逐课扫描作业。
  works,

  /// 逐课扫描签到（与作业同一批课程，每门课多 1 个请求）。
  signs,

  /// 拉通知。
  notices,

  /// 收尾落缓存。
  done,
}

/// 取数进度。
class ChaoxingProgress {
  const ChaoxingProgress({
    required this.phase,
    required this.done,
    required this.total,
  });

  final ChaoxingPhase phase;
  final int done;
  final int total;

  /// 0..1；[total] ≤ 0 时返回 0（不确定进度）。
  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1);

  @override
  String toString() => 'ChaoxingProgress(${phase.name} $done/$total)';
}

/// 学习通仓库。
class ChaoxingRepository {
  ChaoxingRepository({
    required ChaoxingAuthRemoteDataSource auth,
    required ChaoxingMoocRemoteDataSource mooc,
    required ChaoxingNoticeRemoteDataSource notice,
    required ChaoxingSignRemoteDataSource sign,
    required ChaoxingTicketFetcher fetchTicket,
    required this.store,
    this.concurrency = 4,
    this.scanWindow = maxCoursesPerScan,
    this.currentTermCode = '',
    List<String>? trace,
    DateTime Function()? now,
  }) : _auth = auth,
       _mooc = mooc,
       _notice = notice,
       _sign = sign,
       _fetchTicket = fetchTicket,
       _trace = trace,
       _now = now ?? DateTime.now;

  /// 命中风控后的冷却时长。
  ///
  /// 实测（2026-09-19）：突发触发风控后，**每 1 秒探测一次的 60 次全中** —— 窗口至少
  /// 60 秒，且探测本身可能延长它。所以冷却取一倍余量，且期间**一个请求都不发**
  /// （重打既拿不到数据、又让窗口更久）。
  static const Duration challengeCooldown = chaoxingChallengeCooldown;

  /// 每轮最多扫几门课的作业（**扫描窗口**）。
  ///
  /// 实测（2026-09-19）：风控的触发量是**累计请求数**而不是速率 —— 2 请求/秒
  /// 匀速扫 35 门课，仍然在第 31 门（≈62 个请求）开始整段返回验证码页；
  /// 首版并发 4 更快，同样在末尾 6 门撞上。一次全扫 = 35 × 2 = 70 个请求 > 预算，
  /// **必然撞墙**。
  ///
  /// 2026-09-20 起真正的解法是**缩小范围**（见 [currentTermCode] 与
  /// `chaoxing_scan.dart`）而不是分批：只扫当下学期（实测 12 门 = 24 个请求）时
  /// 这一个窗口**装得下全部目标**，于是游标原地不动 → 每轮都扫同一批全量，
  /// 用户点一次刷新就是完整的。窗口本身留作极端情况（一学期选了 > 20 门课）的
  /// 兜底：那时才恢复「轮转 + 如实标注未扫到」。
  ///
  /// ⚠ 数值定义在 `data/chaoxing_limits.dart`（**纯 Dart**：`tool/chaoxing_smoke.dart`
  /// 也要用它，而那个脚本不能 import 本文件 —— 本文件依赖 `flutter/foundation`）。
  static const int maxCoursesPerScan = chaoxingMaxCoursesPerScan;

  final ChaoxingAuthRemoteDataSource _auth;
  final ChaoxingMoocRemoteDataSource _mooc;
  final ChaoxingNoticeRemoteDataSource _notice;
  final ChaoxingSignRemoteDataSource _sign;
  final ChaoxingTicketFetcher _fetchTicket;

  /// 快照缓存（按账号隔离）。
  final ChaoxingStore store;

  /// 作业扫描的并发流水线条数（1 = 完全串行，测试用）。
  final int concurrency;

  /// 每轮扫描的课程数上限（≤ 0 或 ≥ 课程数 = 不分批，全扫）。
  final int scanWindow;

  /// 当下学期的**学期码**（`261`；见 `school_term.dart` 的 `schoolTermCode`）。
  ///
  /// 非空时**只扫当下学期**（+ 学期前缀认不出的课），其余课沿用缓存、记进
  /// `skippedCourseKeys`。空串 = 不筛（旧行为：全课程按窗口轮转）。
  /// 口径与理由见 `domain/chaoxing_scan.dart`。
  final String currentTermCode;

  /// 非空时逐跳记录换证链（调试用；生产传 null）。
  final List<String>? _trace;

  final DateTime Function() _now;

  ChaoxingSession? _current;

  /// 最近一次命中风控的时刻（`null` = 没命中过）。
  DateTime? _challengedAt;

  /// 分批轮转的游标（课程下标；每轮前进 [scanWindow]）。
  int _scanCursor = 0;

  /// 冷却剩余时长；`null` = 不在冷却期。
  Duration? get challengeCooldownLeft {
    final since = _challengedAt;
    if (since == null) return null;
    final left = challengeCooldown - _now().difference(since);
    return left > Duration.zero ? left : null;
  }

  /// 读缓存（首次进页面先显示这个）。
  Future<ChaoxingSnapshot?> cached() => store.load();

  /// 会话是否已在内存里（界面「会话」状态行用）。
  bool get hasSession => _current?.isAlive ?? false;

  /// 丢弃内存会话（退出登录 / 手动「重新登录」时调）。
  void invalidateSession() => _current = null;

  /// 全量取数：课程 + 一批课程的作业 + 通知，写完缓存返回。
  ///
  /// [previous] 非空时：**本轮没扫到 / 扫描失败的课一律沿用它的旧作业**
  /// （分批轮转与风控收手都靠这一条兜底，见 [_fetchAllWorks]）。
  /// [onProgress] 每完成一门课回调一次（界面显示进度用）。
  /// [force] = true 时忽略风控冷却（**手动下拉 / 点刷新**用：用户明确要求就让他试；
  /// 自动刷新不传，免得在风控窗口里反复撞墙）。
  ///
  /// ⚠ **不落盘口径**：课程清单拿不到 → 整次抛错、**不落盘**；作业批次里个别课失败
  /// 或撞风控 → **照常落盘**（因为那些课的数据是从上一份快照里原样搬过来的，
  /// 落盘不会让任何数据变少）。首版是无条件 `store.save`，于是被风控截断的那一次
  /// 会**把好缓存覆盖成缺作业的版本** —— 用户退出重进也回不来（「刷新会刷新没」）。
  Future<ChaoxingSnapshot> refresh({
    ChaoxingSnapshot? previous,
    void Function(ChaoxingProgress progress)? onProgress,
    bool force = false,
  }) async {
    final cooling = challengeCooldownLeft;
    if (!force && cooling != null) {
      throw ChaoxingChallengedException(
        '学习通还在安全验证冷却期（约 ${cooling.inSeconds} 秒后可再自动重试）——'
        '已保留上次数据',
      );
    }
    try {
      return await _fetchSnapshot(previous: previous, onProgress: onProgress);
    } on ChaoxingChallengedException {
      // **所有**风控出口都在这里记账（课程清单命中 / 作业扫描命中 / force 重撞）
      // —— 冷却窗口统一从最后一次命中算起。放在 pre-check 之外，免得每次被冷却
      // 挡回来都把窗口往后推（那样会自动刷新永远解不开）。
      _challengedAt = _now();
      rethrow;
    }
  }

  /// 真正的一次取数（风控记账由 [refresh] 统一包）。
  Future<ChaoxingSnapshot> _fetchSnapshot({
    ChaoxingSnapshot? previous,
    void Function(ChaoxingProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const ChaoxingProgress(phase: ChaoxingPhase.session, done: 0, total: 1),
    );
    await _session();

    onProgress?.call(
      const ChaoxingProgress(phase: ChaoxingPhase.courses, done: 0, total: 1),
    );
    // 课程清单失败（含「一门课都没有」与风控页）→ 整次抛错，界面保留上次数据。
    final courses = await _withSession(_mooc.courses);
    onProgress?.call(
      const ChaoxingProgress(phase: ChaoxingPhase.courses, done: 1, total: 1),
    );

    // 通知可以立刻起（1 个请求），作业扫描慢慢跑。
    final noticesFuture = _fetchNotices();

    final works = await _fetchAllWorks(courses, previous: previous, onProgress: onProgress);
    final notices = await noticesFuture;

    // 本轮撞了风控 → 记账进冷却（**即使这一次没抛错**：数据是齐的，但接下来
    // 一段时间不该再打，否则自动刷新会在验证码窗口里反复撞墙）。
    if (works.challenged) _challengedAt = _now();

    onProgress?.call(
      const ChaoxingProgress(phase: ChaoxingPhase.done, done: 1, total: 1),
    );

    final snapshot = ChaoxingSnapshot(
      courses: courses,
      works: works.works,
      signs: works.signs,
      // 通知没取到**不是「没有通知」**：沿用上一次的列表，只把可用性降级。
      notices: notices ?? previous?.notices ?? const <ChaoxingNotice>[],
      fetchedAt: _now(),
      failedCourseKeys: works.failedCourseKeys,
      failedSignCourseKeys: works.failedSignCourseKeys,
      pendingCourseKeys: works.pendingCourseKeys,
      skippedCourseKeys: works.skippedCourseKeys,
      throttled: works.challenged,
      noticesAvailable: notices != null,
    );
    await store.save(snapshot);
    return snapshot;
  }

  /// 只取通知（页面里「通知」段单独下拉刷新时用；成本 = 1 个请求）。
  ///
  /// 拿不到通知时返回 null（调用方保留旧列表）。
  Future<List<ChaoxingNotice>?> fetchNoticesOnly() => _fetchNotices();

  /// 逐课扫描（**作业 + 签到**，只扫当下学期 + 并发 + 逐课容错）。
  ///
  /// 合并口径（本轮结果与旧数据的关系，**唯一实现，别在别处再拼**）：
  /// - 本轮**扫过**的课 → 一律采信本轮结果（哪怕它是「真空课」的空列表）；
  /// - 本轮**没跑到**的课（窗口外，一学期选课 > 20 门才会出现）→ 沿用旧作业，
  ///   记进 `pendingCourseKeys`；
  /// - 本轮**失败**的课 → 沿用旧作业，记进 `failedCourseKeys`；
  /// - **不在扫描范围内**的课（非当下学期）→ 沿用旧作业，记进 `skippedCourseKeys`。
  ///
  /// ⚠ 每门课两个请求：作业 2 个（课程详情 + 作业列表）、签到 1 个（活动清单）。
  /// **两者各自容错**：签到失败不影响该课的作业（反之亦然），失败分别记进
  /// `failedSignCourseKeys` / `failedCourseKeys` —— 合成一句话会把
  /// 「作业拿到了但签到没拿到」说成整门课失败。
  ///
  /// ⚠ [currentTermCode] 非空时课程池先按学期筛一遍（实测 35 门 → 12 门 = 24 个请求，
  /// 一次扫完、不再轮转）—— 这是「刷新一次拿全」的关键，见 `chaoxing_scan.dart`。
  /// 当下学期一门课都没有（暑假/新学期课程还没建）时**不筛**，否则会变成什么都不扫。
  ///
  /// ⚠ 一旦某门课**命中风控**（[ChaoxingChallengedException]）立刻**收手**：
  /// 实测风控窗口内后续请求会全部失败（60 秒内 60/60 全中），继续打完剩下的请求
  /// 既白等、又可能延长窗口。此时 `challenged = true`，剩下的课全部按「没跑到」处理
  /// —— **本轮已经拿到的数据照样算数**（不再整次作废）。
  Future<_WorksScan> _fetchAllWorks(
    List<ChaoxingCourse> courses, {
    ChaoxingSnapshot? previous,
    void Function(ChaoxingProgress progress)? onProgress,
  }) async {
    if (courses.isEmpty) {
      return const _WorksScan(works: [], failedCourseKeys: []);
    }

    // 课程池：当下学期（+ 学期认不出的课）。判不出学期或一门都不匹配时**不筛**。
    final plan = chaoxingScanPlan(courses, currentTermCode: currentTermCode);
    final skipped = plan.skipped;
    final pool = plan.targets;
    final total = pool.length;

    // 这一轮要扫的下标：从游标开始按顺序取 window 个（绕回），然后游标前进。
    // ⚠ 窗口装得下整个课程池时（只扫当下学期时的常态）`window == total`，
    // 游标推回 0 → **每轮都是同一批全量**，不再有两轮才凑齐的问题。
    final window = scanWindow <= 0 || scanWindow >= total ? total : scanWindow;
    final targets = [for (var i = 0; i < window; i++) (_scanCursor + i) % total];
    _scanCursor = (_scanCursor + window) % total;

    onProgress?.call(
      const ChaoxingProgress(phase: ChaoxingPhase.works, done: 0, total: 1)
          ._withTotal(targets.length),
    );

    final works = <ChaoxingWork>[];
    final signs = <ChaoxingSign>[];
    final failed = <String>[];
    final failedSigns = <String>[];
    /// **扫成功**的课（只有这些课的数据才允许替换旧数据）。
    final okIds = <String>{};
    /// **签到清单**扫成功的课（与 [okIds] 分开：签到失败不该丢掉作业）。
    final okSignIds = <String>{};
    /// **发过请求**的课（含失败的；用来把「撞风控后收手、根本没发出去」区分出来）。
    final attemptedIds = <String>{};
    var challenged = false;
    var done = 0;
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (challenged) return; // 已撞风控：不再发新请求
        final index = next;
        next += 1;
        if (index >= targets.length) return;
        final course = pool[targets[index]];
        attemptedIds.add(course.courseId);
        try {
          works.addAll(await _worksOfCourse(course));
          okIds.add(course.courseId);
        } on ChaoxingChallengedException catch (e) {
          challenged = true;
          failed.add(course.key);
          debugPrint('[chaoxing] 命中风控，作业扫描提前收手：$e');
        } catch (e) {
          failed.add(course.key);
          debugPrint('[chaoxing] 课程 ${course.key} 作业扫描失败：$e');
        }
        // 签到清单（1 个请求）：作业那一步撞了风控就不再发。
        if (!challenged) {
          try {
            signs.addAll(await _signsOfCourse(course));
            okSignIds.add(course.courseId);
          } on ChaoxingChallengedException catch (e) {
            challenged = true;
            failedSigns.add(course.key);
            debugPrint('[chaoxing] 命中风控，签到扫描提前收手：$e');
          } catch (e) {
            failedSigns.add(course.key);
            debugPrint('[chaoxing] 课程 ${course.key} 签到清单失败：$e');
          }
        }
        done += 1;
        onProgress?.call(
          ChaoxingProgress(phase: ChaoxingPhase.works, done: done, total: targets.length),
        );
      }
    }

    final lanes = concurrency < 1 ? 1 : (concurrency > targets.length ? targets.length : concurrency);
    await Future.wait([for (var i = 0; i < lanes; i++) worker()]);

    // ⚠ 兜底口径（本 bug 的修复要点）：**只要某门课本轮没扫成功，它的旧作业就原样搬过来**
    // —— 无论是「窗口外没轮到」还是「扫了但失败/被风控拦下」。所以刷新永远不会让
    // 作业凭空消失；只有「扫成功 + 页面确认」才允许替换（哪怕是替换成空）。
    // 签到用**另一套** okSignIds（两个请求各自成功/失败）。
    if (previous != null) {
      if (previous.works.isNotEmpty) {
        works.addAll([
          for (final w in previous.works)
            if (!okIds.contains(w.courseId)) w,
        ]);
      }
      if (previous.signs.isNotEmpty) {
        signs.addAll([
          for (final s in previous.signs)
            if (!okSignIds.contains(s.courseId)) s,
        ]);
      }
    }

    // 待补齐 = **课程池里**本轮既没扫成功、也没记失败的课（窗口外 + 撞风控后没发出去的）。
    // ⚠ 只数课程池：非当下学期的课不在池里，它们是**有意不扫**（记 skipped），
    // 不该被说成「下一轮会扫」。
    final failedIds = {for (final key in failed) key.split('/').first};
    final pending = <String>[
      for (final c in pool)
        if (!okIds.contains(c.courseId) && !failedIds.contains(c.courseId)) c.key,
    ];
    return _WorksScan(
      works: works,
      signs: signs,
      failedCourseKeys: failed,
      failedSignCourseKeys: failedSigns,
      pendingCourseKeys: pending,
      skippedCourseKeys: [for (final c in skipped) c.key],
      challenged: challenged,
    );
  }

  /// 一门课的作业；会话失效时重换一次再试。
  ///
  /// ⚠ **风控不算失效**：换票不会让验证码消失（风控认的是请求速率与账号，
  /// 不是票据），所以 [ChaoxingChallengedException] 直接往上抛。
  Future<List<ChaoxingWork>> _worksOfCourse(ChaoxingCourse course) async {
    final session = await _session();
    try {
      return await _mooc.worksOf(session, course);
    } on ChaoxingSessionExpiredException {
      // 别的流水线可能已经换好了新会话，取当前的那个再试。
      final fresh = await _session();
      if (identical(fresh, session)) {
        return await _mooc.worksOf(await _session(force: true), course);
      }
      return await _mooc.worksOf(fresh, course);
    }
  }

  /// 一门课的**签到清单**（1 个请求）；失效重换口径同 [_worksOfCourse]。
  Future<List<ChaoxingSign>> _signsOfCourse(ChaoxingCourse course) async {
    final session = await _session();
    try {
      return await _sign.signsOf(session, course);
    } on ChaoxingSessionExpiredException {
      final fresh = await _session();
      if (identical(fresh, session)) {
        return await _sign.signsOf(await _session(force: true), course);
      }
      return await _sign.signsOf(fresh, course);
    }
  }

  /// 一条签到活动的**我的状态**（1 个请求，按需调用）。
  Future<ChaoxingSign> _signDetail(ChaoxingSign sign) async {
    final session = await _session();
    try {
      return await _sign.detailOf(session, sign);
    } on ChaoxingSessionExpiredException {
      final fresh = await _session();
      if (identical(fresh, session)) {
        return await _sign.detailOf(await _session(force: true), sign);
      }
      return await _sign.detailOf(fresh, sign);
    }
  }

  /// **按需**取一条签到活动的状态（用户点开某条时调），并把结果并进快照 + 落盘。
  ///
  /// 成本 = **1 个请求**；撞风控时记账并抛（界面提示冷却中）。
  Future<ChaoxingSnapshot> refreshSignDetail(
    ChaoxingSnapshot current,
    ChaoxingSign sign,
  ) async {
    try {
      final updated = await _signDetail(sign);
      final next = current.copyWith(signs: _replaceSign(current.signs, updated));
      await store.save(next);
      return next;
    } on ChaoxingChallengedException {
      _challengedAt = _now();
      rethrow;
    }
  }

  /// **手动全量更新签到**（用户点按钮才走这条；自动刷新永远不碰）。
  ///
  /// 两步（都带节流 260ms，撞风控立刻收手）：
  /// 1. 逐课取签到清单 —— [allCourses] = false 时**只扫当下学期**（与自动刷新同口径），
  ///    true 时扫**全部课程**（含往期学期，请求数 = 课程数）；
  /// 2. 逐条补「我的状态」（1 请求 / 活动）—— 只补 `statusLoaded == false` 的那些。
  ///
  /// ⚠ 这是本模块**唯一**可能一次发几十个请求的入口（实测 ≈60 个/窗口就撞验证码页），
  /// 所以只允许用户明确触发，并把「撞风控就停、已拿到的照算」如实回报。
  Future<ChaoxingSnapshot> refreshSignsFull(
    ChaoxingSnapshot current, {
    bool allCourses = false,
    void Function(ChaoxingProgress progress)? onProgress,
  }) async {
    final pool = allCourses
        ? current.courses
        : chaoxingScanTargets(current.courses, currentTermCode: currentTermCode);
    if (pool.isEmpty) return current;

    var merged = current.signs;
    final failedSigns = <String>{};
    final okIds = <String>{};
    var challenged = false;

    // ① 清单：逐课（串行 —— 与流水线并发相比，这里更在意「可预期地撞上冷却」）。
    for (var i = 0; i < pool.length; i++) {
      if (challenged) break;
      final course = pool[i];
      onProgress?.call(
        ChaoxingProgress(phase: ChaoxingPhase.signs, done: i, total: pool.length),
      );
      try {
        final list = await _signsOfCourse(course);
        okIds.add(course.courseId);
        merged = [
          for (final s in merged)
            if (s.courseId != course.courseId) s,
          ...list,
        ];
      } on ChaoxingChallengedException catch (e) {
        challenged = true;
        failedSigns.add(course.key);
        debugPrint('[chaoxing] 签到全量更新命中风控，已收手：$e');
      } catch (e) {
        failedSigns.add(course.key);
        debugPrint('[chaoxing] 课程 ${course.key} 签到清单失败：$e');
      }
    }

    // ② 状态：只补还没查过的（一条一个请求）。
    final unknown = [for (final s in merged) if (!s.statusLoaded) s];
    for (var i = 0; i < unknown.length; i++) {
      if (challenged) break;
      onProgress?.call(
        ChaoxingProgress(
          phase: ChaoxingPhase.signs,
          done: pool.length + i,
          total: pool.length + unknown.length,
        ),
      );
      try {
        final updated = await _signDetail(unknown[i]);
        merged = _replaceSign(merged, updated);
      } on ChaoxingChallengedException catch (e) {
        challenged = true;
        debugPrint('[chaoxing] 补签到状态命中风控，已收手：$e');
      } catch (e) {
        debugPrint('[chaoxing] 签到 ${unknown[i].key} 详情失败：$e');
      }
    }

    if (challenged) _challengedAt = _now();
    onProgress?.call(
      ChaoxingProgress(
        phase: ChaoxingPhase.signs,
        done: pool.length + unknown.length,
        total: pool.length + unknown.length,
      ),
    );

    final next = current.copyWith(
      signs: merged,
      // 没扫的课保留上一次的失败标记（否则界面会说「都成功」）。
      failedSignCourseKeys: [
        ...failedSigns,
        ...current.failedSignCourseKeys.where(
          (k) => !okIds.contains(k.split('/').first),
        ),
      ],
      throttled: challenged,
    );
    await store.save(next);
    return next;
  }

  /// 用 [updated] 替换列表里同键的那条（键 = `courseId/activeId`）。
  static List<ChaoxingSign> _replaceSign(
    List<ChaoxingSign> signs,
    ChaoxingSign updated,
  ) => [
    for (final s in signs)
      if (s.key == updated.key) updated else s,
  ];

  /// 通知：取不到返回 null（不抛 —— 通知挂了不该让整次刷新失败）。
  Future<List<ChaoxingNotice>?> _fetchNotices() async {
    try {
      return await _withSession(_notice.list);
    } on ChaoxingChallengedException catch (e) {
      // 通知这条命中了风控也要记账：否则自动刷新会在窗口里继续撞。
      _challengedAt = _now();
      debugPrint('[chaoxing] 通知命中风控：$e');
      return null;
    } catch (e) {
      debugPrint('[chaoxing] 通知取数失败：$e');
      return null;
    }
  }

  /// 带一次「失效重换」的重试包装（口径同 `libsp_remote_adapter`）。
  Future<T> _withSession<T>(Future<T> Function(ChaoxingSession session) run) async {
    final session = await _session();
    try {
      return await run(session);
    } on ChaoxingSessionExpiredException {
      final fresh = await _session(force: true);
      return await run(fresh);
    }
  }

  /// 取得（必要时新换）会话。
  Future<ChaoxingSession> _session({bool force = false}) async {
    final cached = _current;
    if (!force && cached != null && cached.isAlive) return cached;

    final Either<Failure, String> result =
        await _fetchTicket(ChaoxingEndpoints.casServiceUrl);
    final ticketUrl = result.fold(
      (failure) => throw ChaoxingSessionException(
        '统一认证换票失败：${failure.message}（请确认已在 App 里登录过）',
      ),
      (url) => url,
    );
    final session = await _auth.establishSession(ticketUrl, trace: _trace);
    _current = session;
    return session;
  }
}

/// 作业扫描结果。
class _WorksScan {
  const _WorksScan({
    required this.works,
    this.signs = const [],
    required this.failedCourseKeys,
    this.failedSignCourseKeys = const [],
    this.pendingCourseKeys = const [],
    this.skippedCourseKeys = const [],
    this.challenged = false,
  });

  final List<ChaoxingWork> works;

  /// 本轮扫到的签到（扫成功的课采用本轮；其余沿用旧数据）。
  final List<ChaoxingSign> signs;

  final List<String> failedCourseKeys;

  /// 签到清单失败的课程键（与 [failedCourseKeys] 分开记）。
  final List<String> failedSignCourseKeys;

  /// 本轮窗口外（或撞风控后收手）而**没跑到**的课程键 —— 数据用的是上一次的。
  final List<String> pendingCourseKeys;

  /// **不在扫描范围内**的课程键（非当下学期）—— 下一轮也不会扫。
  final List<String> skippedCourseKeys;

  /// 扫描中途撞上风控（请求被验证码页拦下）→ 后续课程一律沿用旧数据。
  final bool challenged;
}

extension on ChaoxingProgress {
  /// 进度占位（课程数未知时先报 `0/1`，拿到课程数再报真实总数）。
  ChaoxingProgress _withTotal(int total) =>
      ChaoxingProgress(phase: phase, done: done, total: total);
}
