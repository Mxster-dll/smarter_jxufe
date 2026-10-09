/// 学习通（超星）服务主页 —— 只读：课程 / 作业 / 签到 / 通知。
///
/// 数据来源 = 学习通网页端（`i.chaoxing.com` + `mooc1.chaoxing.com` +
/// `mobilelearn.chaoxing.com` + `notice.chaoxing.com`），
/// **零密码**复用 App 内已登录的 CAS 票据换证，不写任何学习通数据。
/// 链路与字段口径见 `reverse_engineering/学习通接口.md`，模块约定见
/// `lib/features/chaoxing/README.md`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_repository.dart';
import 'package:smarter_jxufe/features/chaoxing/data/providers/chaoxing_providers.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_snapshot.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_text.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_common.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_courses_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_notices_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_signs_screen.dart';
import 'package:smarter_jxufe/features/chaoxing/presentation/chaoxing_works_screen.dart';

/// 主页里每个区块最多直接铺几条（其余走「查看全部」）。
const int kChaoxingPreviewWorks = 5;
const int kChaoxingPreviewNotices = 4;
const int kChaoxingPreviewCourses = 6;
const int kChaoxingPreviewSigns = 4;

/// 主页「通知里的作业提醒」最多显示几条。
const int kChaoxingPreviewWorkHints = 3;

/// 学习通主页。
class ChaoxingScreen extends ConsumerStatefulWidget {
  const ChaoxingScreen({super.key});

  @override
  ConsumerState<ChaoxingScreen> createState() => _ChaoxingScreenState();
}

class _ChaoxingScreenState extends ConsumerState<ChaoxingScreen> {
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _autoRefreshAll,
  );

  /// 倒计时基准时刻（每次刷新/重建取一次，避免同一帧里两次 `DateTime.now()` 打架）。
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  /// 首次进入 / 从子页返回 / App 回前台 —— 受 1 分钟闸门约束（一次取数 ~69 个请求）。
  ///
  /// **不传 force**：自动刷新要尊重仓库的风控冷却，别在验证码窗口里反复撞墙。
  void _autoRefreshAll() {
    if (!mounted) return;
    final snapshot = ref.read(chaoxingControllerProvider).valueOrNull;
    final gate = ref.read(chaoxingRefreshGateProvider);
    if (snapshot != null && !snapshot.isEmpty && !gate.allowsAutoRefresh) {
      return;
    }
    unawaited(_refresh());
  }

  /// [force] = true 时忽略风控冷却（**手动下拉 / 点刷新**才有这个权力）。
  Future<void> _refresh({bool force = false}) async {
    setState(() => _now = DateTime.now());
    await ref.read(chaoxingControllerProvider.notifier).refresh(force: force);
    if (mounted) setState(() => _now = DateTime.now());
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('清除本机学习通数据'),
        content: const Text(
          '只会删掉本机缓存的课程 / 作业 / 通知与当前会话，'
          '不会影响学习通上的任何内容。下次进入会重新取数。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(chaoxingControllerProvider.notifier).clear();
    if (mounted) setState(() {});
  }

  /// 子页面入口 —— 返回后刷新一次（**本页唯一**的「返回即刷新」路径）。
  ///
  /// ⚠ 本页**刻意不挂 `subscribeRoute`**（约定见 AGENTS.md §3「能 `await push` 就
  /// `await push`，并撤掉 `subscribeRoute`」，2026-09-20 收敛）：
  /// - 两条路径并存 → 同一次返回会触发两次自动刷新，而学习通一次取数是 ~70 个请求，
  ///   这正是历史上「刷新会刷新没」（并发双扫撞风控）的成因之一；
  /// - **弹窗也是路由** —— 挂 `subscribeRoute` 时，关掉任意一个通知 / 作业详情
  ///   弹窗都会让本页收到 `didPopNext` 白刷一次。
  void _openChild(Widget screen) {
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen))
          .then((_) => _autoRefreshAll()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chaoxingControllerProvider);
    final snapshot = async.valueOrNull ?? ChaoxingSnapshot.empty;
    final busy = async.isLoading;
    final error = async.hasError ? async.error : null;

    final refreshButton = IconButton(
      tooltip: '刷新',
      icon: const Icon(Icons.refresh),
      onPressed: busy ? null : () => _refresh(force: true),
    );

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('学习通'),
        centerTitle: true,
        actions: [refreshButton],
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: PaneBody(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 2),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : () => _refresh(force: true),
          ),
        ],
        child: snapshot.isEmpty && busy
            ? _buildFirstLoad()
            : RefreshIndicator(
                onRefresh: () => _refresh(force: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 48),
                  children: [
                    if (error != null) ...[
                      _buildErrorCard(error),
                      const SizedBox(height: 12),
                    ],
                    _buildOverviewCard(snapshot, busy),
                    const SizedBox(height: 12),
                    ..._buildWorkSection(snapshot, busy),
                    const SizedBox(height: 12),
                    _buildSignSection(snapshot, busy),
                    const SizedBox(height: 12),
                    _buildNoticeSection(snapshot, busy),
                    const SizedBox(height: 12),
                    _buildCourseSection(snapshot, busy),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFirstLoad() {
    final progress = ref.watch(chaoxingProgressProvider);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_progressText(progress) ?? '正在读取学习通数据…'),
          const SizedBox(height: 8),
          Text(
            '首次取数要把当下学期的课逐门扫一遍，约十几秒',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(Object error) {
    final critical = AppColors.critical(context);
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: critical, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '取数失败',
                    style: TextStyle(fontWeight: FontWeight.w700, color: critical),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$error',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted(context)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '下面显示的可能是上一次的数据。',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ChaoxingSnapshot snapshot, bool busy) {
    final progress = ref.watch(chaoxingProgressProvider);
    final accent = appCardAccent(context);
    final muted = AppColors.textMuted(context);
    final updated = snapshot.fetchedAt;
    final openSigns = snapshot.openSignsAt(_now).length;
    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    busy ? (_progressText(progress) ?? '正在更新…') : '数据已更新',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: busy ? accent : AppColors.textBase(context),
                    ),
                  ),
                ),
                if (updated != null && !busy)
                  Text(
                    '更新于 ${_hmss(updated)}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress == null || progress.fraction == 0
                      ? null
                      : progress.fraction,
                  minHeight: 4,
                  backgroundColor: AppColors.tint(context, accent, 0.10),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    '待做作业',
                    '${snapshot.todoCount}',
                    accent,
                    key: const Key('chaoxingTodoCount'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    '未读通知',
                    snapshot.noticesAvailable ? '${snapshot.unreadNoticeCount}' : '—',
                    accent,
                    key: const Key('chaoxingUnreadCount'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric('课程', '${snapshot.courses.length}', accent,
                      key: const Key('chaoxingCourseCount')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    '签到次数',
                    '${snapshot.signs.length}',
                    accent,
                    key: const Key('chaoxingSignCount'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric('进行中签到', '$openSigns', accent,
                      key: const Key('chaoxingOpenSignCount')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric('已确认未签', '${snapshot.absentSignCount}', accent,
                      key: const Key('chaoxingAbsentSignCount')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '共 ${snapshot.works.length} 条作业记录'
              ' · ${chaoxingSignSummary(snapshot, _now)}'
              '${snapshot.skippedCourseKeys.isEmpty ? '' : ' · 只扫当下学期（${snapshot.courses.length - snapshot.skippedCourseKeys.length}/${snapshot.courses.length} 门）'}'
              '${snapshot.failedCourseKeys.isEmpty ? '' : ' · ${snapshot.failedCourseKeys.length} 门课扫描失败'}'
              '${snapshot.failedSignCourseKeys.isEmpty ? '' : ' · ${snapshot.failedSignCourseKeys.length} 门课签到没取到'}'
              '${snapshot.pendingCourseKeys.isEmpty ? '' : ' · 另有 ${snapshot.pendingCourseKeys.length} 门课本轮没跑到'}'
              '${snapshot.throttled ? ' · 学习通限流，本轮沿用上次数据' : ''}'
              '${snapshot.noticesAvailable ? '' : ' · 通知暂不可用'}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '只读接入：登录用 App 内已有的统一认证票据，不写入学习通。',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
                TextButton(
                  onPressed: _confirmClear,
                  child: const Text('清除本机数据', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color accent, {Key? key}) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.tint(context, accent, 0.07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        Text(
          value,
          key: key,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted(context)),
        ),
      ],
    ),
  );

  List<Widget> _buildWorkSection(ChaoxingSnapshot snapshot, bool busy) {
    final open = snapshot.openWorks;
    final finished = snapshot.finishedWorks;
    final preview = open.take(kChaoxingPreviewWorks).toList();
    final hints = chaoxingNoticeWorkHints(snapshot);
    return [
      ChaoxingSectionCard(
        title: '待做作业',
        trailing: _countChip('${open.length} 条'),
        onSeeAll: open.isEmpty ? null : () => _openChild(const ChaoxingWorksScreen()),
        seeAllLabel: '查看全部作业',
        children: [
          if (preview.isEmpty)
            ChaoxingEmptyHint(
              // ⚠ 未扫到的课**不能**算进「没有待做作业」：它们显示的是上次数据，
              // 里面可能正藏着一条没交的作业（用户 2026-09-20 报的就是这个场景）。
              text: snapshot.unscannedCourseCount > 0
                  ? '暂时没有待做作业'
                        '（另有 ${snapshot.unscannedCourseCount} 门课本轮未扫到，可能有遗漏）'
                  : '暂时没有待做作业',
              icon: Icons.check_circle_outline,
            )
          else
            for (final work in preview) _workRow(work),
          if (open.length > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                '还有 ${open.length - preview.length} 条未显示',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              ),
            ),
        ],
      ),
      // 「通知里的作业提醒」（用户 2026-09-20 选定的 B 方案）：作业是学习通里唯一
      // 没有统一接口的数据，只能逐课扫；扫不到时（往期课不扫 / 撞风控收手）用**统一
      // 接口的通知**兜底 —— 老师发布作业时平台会自动发一条 `作业:《课程名》标题`。
      // 已经扫到的那些在 `chaoxingNoticeWorkHints` 里按标题包含关系去重，不会重复。
      if (hints.isNotEmpty)
        ChaoxingSectionCard(
          title: '通知里的作业提醒',
          trailing: _countChip('${hints.length} 条'),
          children: [
            for (final notice in hints.take(kChaoxingPreviewWorkHints))
              ChaoxingNoticeRow(
                notice: notice,
                now: _now,
                onTap: () => showChaoxingNoticeDetail(
                  context,
                  notice,
                  courseName: chaoxingCourseNameOf(snapshot, notice.courseId),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                '这些作业在通知里，但作业列表还没扫到 —— 可能属于往期课程，或这一轮没跑到。',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              ),
            ),
          ],
        ),
      if (finished.isNotEmpty)
        ChaoxingSectionCard(
          title: '最近完成',
          trailing: _countChip('${finished.length} 条'),
          children: [
            for (final work in finished.take(3)) _workRow(work),
          ],
        ),
      if (busy && snapshot.works.isEmpty)
        ChaoxingSectionCard(
          title: '作业',
          children: const [ChaoxingEmptyHint(text: '正在扫描各门课程的作业…')],
        ),
    ];
  }

  Widget _buildNoticeSection(ChaoxingSnapshot snapshot, bool busy) {
    final notices = snapshot.notices;
    return ChaoxingSectionCard(
      title: '通知消息',
      trailing: notices.isEmpty ? null : _countChip('${notices.length} 条'),
      onSeeAll: notices.isEmpty ? null : () => _openChild(const ChaoxingNoticesScreen()),
      seeAllLabel: '查看全部通知',
      children: [
        if (notices.isEmpty)
          ChaoxingEmptyHint(
            text: snapshot.noticesAvailable
                ? (busy ? '正在读取通知…' : '暂时没有通知')
                : '通知暂不可用（本次会话没取到收件箱 token）',
            icon: Icons.notifications_none,
          )
        else
          for (final notice in notices.take(kChaoxingPreviewNotices))
            ChaoxingNoticeRow(
              notice: notice,
              now: _now,
              // 主页区块里的行**直接可点看详情**（此前只有「全部通知」页能点，
              // 用户 2026-09-19：「我希望消息可以点击看详情」）。
              onTap: () => showChaoxingNoticeDetail(
                context,
                notice,
                courseName: chaoxingCourseNameOf(snapshot, notice.courseId),
              ),
            ),
        if (notices.length > kChaoxingPreviewNotices)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              '还有 ${notices.length - kChaoxingPreviewNotices} 条未显示',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            ),
          ),
      ],
    );
  }

  Widget _buildCourseSection(ChaoxingSnapshot snapshot, bool busy) {
    final courses = snapshot.courses;
    final byCourse = chaoxingWorksByCourse(snapshot);
    return ChaoxingSectionCard(
      title: '我的课程',
      trailing: courses.isEmpty ? null : _countChip('${courses.length} 门'),
      onSeeAll: courses.isEmpty ? null : () => _openChild(const ChaoxingCoursesScreen()),
      seeAllLabel: '查看全部课程',
      children: [
        if (courses.isEmpty)
          ChaoxingEmptyHint(
            text: busy ? '正在读取课程…' : '没有读到课程（学习通侧可能没有本学期课程）',
            icon: Icons.school_outlined,
          )
        else
          for (final course in courses.take(kChaoxingPreviewCourses))
            ChaoxingCourseRow(
              course: course,
              workCount: byCourse[course.key]?.length ?? 0,
              todoCount:
                  byCourse[course.key]?.where((w) => w.status.isOpen).length ?? 0,
              note: chaoxingCourseScanNote(snapshot, course.key),
            ),
        if (courses.length > kChaoxingPreviewCourses)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              '还有 ${courses.length - kChaoxingPreviewCourses} 门未显示',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            ),
          ),
      ],
    );
  }

  /// 「签到记录」区块（用户 2026-10-09：「我希望还能接入学习通里的签到记录」）。
  ///
  /// 口径：
  /// - 进行中的签到排最前（那才是「现在要不要签」），其余按时间倒序；
  /// - **状态是「点开才查」的**（清单接口不给我的状态），所以这里显示「状态未知」
  ///   而不是「未签」；点开某条 → 弹窗里一键查（1 个请求）；
  /// - 区块底部给「查看全部签到」入口 → 那一页有**手动全量更新**（清单 + 状态）。
  Widget _buildSignSection(ChaoxingSnapshot snapshot, bool busy) {
    final now = _now;
    final open = snapshot.openSignsAt(now);
    final openIds = {for (final s in open) s.key};
    final rest = [
      for (final s in snapshot.signs)
        if (!openIds.contains(s.key)) s,
    ];
    final preview = [...open, ...rest].take(kChaoxingPreviewSigns).toList();
    final failedSignCourses = snapshot.failedSignCourseKeys.length;
    return ChaoxingSectionCard(
      title: '签到记录',
      trailing: _countChip(chaoxingSignSummary(snapshot, now)),
      onSeeAll: snapshot.signs.isEmpty && !busy
          ? null
          : () => _openChild(const ChaoxingSignsScreen()),
      seeAllLabel: '查看全部签到',
      children: [
        if (preview.isEmpty)
          ChaoxingEmptyHint(
            // ⚠ 「本轮没取到」与「这门课没有签到」必须分开说。
            text: busy
                ? '正在读取各门课程的签到…'
                : (failedSignCourses > 0
                      ? '暂时没有签到记录（另有 $failedSignCourses 门课的签到没取到，可能有遗漏）'
                      : '暂时没有签到记录'),
            icon: Icons.how_to_reg_outlined,
          )
        else
          for (final sign in preview) _signRow(sign),
        if (snapshot.signs.length > preview.length)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              '还有 ${snapshot.signs.length - preview.length} 条未显示',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            ),
          ),
      ],
    );
  }

  /// 一条作业行 + **点开详情**（`showChaoxingWorkDetail` 是全模块唯一实现）。
  Widget _workRow(ChaoxingWork work) => ChaoxingWorkRow(
    work: work,
    now: _now,
    onTap: () => showChaoxingWorkDetail(context, work, now: _now),
  );

  /// 一条签到行 + **点开详情**（状态未知时弹窗里会给「查询我的状态」按钮）。
  Widget _signRow(ChaoxingSign sign) => ChaoxingSignRow(
    sign: sign,
    now: _now,
    onTap: () => showChaoxingSignDetail(
      context,
      sign,
      now: _now,
      onRefresh: () => _loadSignStatus(sign),
    ),
  );

  /// 按需取这条签到的「我的状态」（1 个请求）—— 取完刷新本页。
  Future<void> _loadSignStatus(ChaoxingSign sign) async {
    await ref.read(chaoxingControllerProvider.notifier).loadSignDetail(sign);
    if (mounted) setState(() {});
  }

  Widget _countChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.tint(context, appCardAccent(context), 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: appCardAccent(context),
      ),
    ),
  );

  String? _progressText(ChaoxingProgress? progress) {
    if (progress == null) return null;
    return switch (progress.phase) {
      ChaoxingPhase.session => '正在用统一认证换取学习通会话…',
      ChaoxingPhase.courses => '正在读取课程列表…',
      ChaoxingPhase.works => '正在扫描作业 ${progress.done}/${progress.total} 门课',
      ChaoxingPhase.signs => '正在更新签到 ${progress.done}/${progress.total} 步',
      ChaoxingPhase.notices => '正在读取通知…',
      ChaoxingPhase.done => '正在整理数据…',
    };
  }

  String _hmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
