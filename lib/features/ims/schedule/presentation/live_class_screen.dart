import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/live_session.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/reschedule_marks.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

/// 上课实况窗 —— 「上课中 / 下一节课」的常驻倒计时。
///
/// 本页既是**开关与预览**，也是形态验证台：顶部那张卡就是通知栏胶囊的放大版，
/// 用来确认「课程名 + 教室 + 倒计时 + 进度」这套信息密度是否成立。
///
/// ## 为什么不需要后台常驻
/// 通知的倒计时交给 Android 的 `usesChronometer`，由**系统时钟**推进，
/// 与鸿蒙实况窗的「计时型胶囊由系统推进」同思路。App 只在这几个时刻需要动作：
/// 状态切换（上课/下课/换课）—— 而那完全可由课表 + 作息表**离线预计算**得出。
class LiveClassScreen extends ConsumerStatefulWidget {
  const LiveClassScreen({super.key});

  @override
  ConsumerState<LiveClassScreen> createState() => _LiveClassScreenState();
}

class _LiveClassScreenState extends ConsumerState<LiveClassScreen> {
  // ---- 数据 ----
  List<ScheduleEntry>? _entries;
  PeriodTable _table = PeriodTable.builtin;
  TeachingWeek? _teachingWeek;
  String _serialNo = '';
  int _year = 0;
  String _semester = '0';

  // ---- 加载状态 ----
  bool _loading = true;
  String? _error;

  /// 课表来自本地缓存（未联网或联网失败后降级）。
  bool _fromCache = false;

  /// 联网刷新失败的原因；非空时界面提示「显示的是缓存」。
  String? _refreshError;

  // ---- 实况窗 ----
  bool _notifyEnabled = true;
  DateTime _now = DateTime.now();
  Timer? _ticker;

  /// 上一次推送的标识（`状态键#已上课分钟`），用于通知去重。
  String? _lastPushedKey;

  // ---- 调课（与课表页共享同一个 store，改完立刻影响倒计时与通知）----
  RescheduleStore? _rescheduleStore;
  RescheduleTerm? _rescheduleTerm;
  List<Reschedule> _reschedules = const [];

  @override
  void initState() {
    super.initState();
    _rescheduleStore = ref.read(rescheduleStoreProvider);
    _rescheduleStore!.addListener(_onReschedulesChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _syncNotification();
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rescheduleStore?.removeListener(_onReschedulesChanged);
    super.dispose();
  }

  /// 调课记录变了（本页或课表页改的）→ 立刻按新安排重推通知。
  void _onReschedulesChanged() {
    if (!mounted) return;
    final t = _rescheduleTerm;
    setState(() {
      _reschedules = t == null ? const [] : _rescheduleStore!.recordsOf(t);
    });
    _syncNotification(force: true);
  }

  // ---- 数据加载 ----

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final studentInfoRepo = await ref.read(
        studentInfoRepositoryProvider.future,
      );
      StudentInfo? info;
      studentInfoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      if (info == null) throw Exception('未获取到学籍信息，请先登录教务系统');

      final si = info!;
      _serialNo = si.serialNo;

      // 学年学期口径与校历一致（校历区间优先，月份兜底）
      final term = currentSchoolTerm(
        DateTime.now(),
        terms: ref.read(offlineSemesterTermsProvider),
      );
      _year = term.xn;
      _semester = '${term.xq}';

      // 本地调课记录（纯本地，离线可得）
      final rescheduleTerm = RescheduleTerm('$_year', _semester);
      final store = _rescheduleStore;
      if (store != null) {
        await store.ensureLoaded(rescheduleTerm);
        if (!mounted) return;
        setState(() {
          _rescheduleTerm = rescheduleTerm;
          _reschedules = store.recordsOf(rescheduleTerm);
        });
      }

      // 教学周：纯离线，立即可得
      final tw = resolveTeachingWeek(
        DateTime.now(),
        terms: ref.read(offlineSemesterTermsProvider),
      );

      // 作息表：先用缓存/内置兜底渲染，再后台刷新
      final periodRepo = ref.read(periodTableRepositoryProvider);
      final cachedTable = await periodRepo.cachedOrBuiltin();
      if (!mounted) return;
      setState(() {
        _teachingWeek = tw;
        _table = cachedTable;
      });

      // 课表：cache-first，离线可用
      final cacheRepo = await ref.read(scheduleCacheRepositoryProvider.future);
      final result = await cacheRepo.load(
        year: '$_year',
        semester: _semester,
        studentId: _serialNo,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _entries = result.entries;
        _fromCache = result.fromCache;
        _refreshError = result.refreshError;
        _loading = false;
      });

      unawaited(_refreshPeriodTable());
      _syncNotification(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 后台刷新作息表（免登录接口，失败保留缓存/内置表，不打扰用户）。
  Future<void> _refreshPeriodTable() async {
    try {
      final t = await ref.read(currentPeriodTableProvider.future);
      if (!mounted || !t.isUsable) return;
      setState(() => _table = t);
    } catch (_) {}
  }

  // ---- 实况窗状态 ----

  LiveSession? _resolve() {
    final tw = _teachingWeek;
    final entries = _entries;
    if (tw == null || entries == null) return null;
    return resolveLiveSession(
      entries: entries,
      table: _table,
      teachingWeek: tw.week,
      now: _now,
      reschedules: _reschedules,
    );
  }

  /// 把最新状态同步到系统通知；[force] 用于刷新/切开关后强制重推。
  void _syncNotification({bool force = false}) {
    final state = _resolve();
    if (state == null) return;

    final service = NotificationService.instance;

    if (!_notifyEnabled) {
      if (force || _lastPushedKey != 'disabled') {
        service.cancelLiveClass();
        _lastPushedKey = 'disabled';
      }
      return;
    }

    final content = liveNotificationContent(state, _now);
    if (content == null) {
      // 今日无更多课 —— 撤销实况窗
      if (force || _lastPushedKey != 'idle') {
        service.cancelLiveClass();
        _lastPushedKey = 'idle';
      }
      return;
    }

    // 去重：状态未变且已上课分钟未变则不重推。
    // `countdownTo` 始终不变，故重推不会重置系统计时器，只更新进度条。
    final key = '${liveSessionKey(state)}#${content.elapsedMinutes}';
    if (!force && key == _lastPushedKey) return;
    _lastPushedKey = key;

    service.showLiveClass(
      title: content.title,
      body: content.body,
      countdownTo: content.countdownTo,
      elapsedMinutes: content.elapsedMinutes,
      totalMinutes: content.totalMinutes,
    );
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上课实况窗'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新课表',
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      children: [
        _buildCapsulePreview(context),
        const SizedBox(height: 12),
        _buildSwitchCard(context),
        const SizedBox(height: 12),
        _buildContextCard(context),
        const SizedBox(height: 12),
        _buildTodayCard(context),
        const SizedBox(height: 16),
        _buildFootnote(context),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => _load(refresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 通知栏胶囊的放大预览。
  Widget _buildCapsulePreview(BuildContext context) {
    final state = _resolve();
    final content = state == null ? null : liveNotificationContent(state, _now);

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '实况窗预览',
              accent: FeaturePalette.cardAccent,
            ),
            const SizedBox(height: 14),
            _capsule(context, content, state),
          ],
        ),
      ),
    );
  }

  Widget _capsule(
    BuildContext context,
    LiveNotificationContent? content,
    LiveSession? state,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final inClass = state is LiveInClass;
    final accent = content == null ? scheme.outline : FeaturePalette.cardAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            content == null
                ? Icons.nightlight_outlined
                : (inClass ? Icons.school : Icons.schedule),
            size: 22,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content?.title ?? '今日无课',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  content?.body ?? '实况窗已收起，有新课时会自动出现',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (content != null) ...[
            const SizedBox(width: 10),
            Text(
              formatCountdown(content.countdownTo.difference(_now)),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: _notifyEnabled,
        onChanged: (v) {
          setState(() {
            _notifyEnabled = v;
            _lastPushedKey = null;
          });
          _syncNotification(force: true);
        },
        secondary: const Icon(Icons.notifications_active_outlined, size: 22),
        title: const Text('在通知栏常驻', style: TextStyle(fontSize: 14)),
        subtitle: const Text(
          '倒计时由系统时钟推进，熄屏后仍会走',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildContextCard(BuildContext context) {
    final tw = _teachingWeek;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '当前教学周',
              accent: FeaturePalette.cardAccent,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  tw?.label ?? '未知',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (tw != null && !tw.isBeforeTerm) ...[
                  const SizedBox(width: 10),
                  Text(
                    tw.isOdd ? '单周' : '双周',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tw == null
                  ? '未匹配到学期'
                  : '${tw.term.term} 学期 · 第 1 教学周自 '
                        '${_ymd(tw.firstMonday)} 起',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const Divider(height: 24),
            _kv(
              context,
              '作息表',
              '${_table.label}（${_table.source == 'remote' ? '教务实时' : '内置兜底'}）',
            ),
            const SizedBox(height: 6),
            _kv(
              context,
              '学年学期',
              '$_year · ${_semester == '0' ? '第一学期' : '第二学期'}',
            ),
            const SizedBox(height: 6),
            _kv(
              context,
              '课表来源',
              _fromCache
                  ? '本地缓存${_refreshError == null ? '' : '（联网失败）'}'
                  : '教务系统',
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            k,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _buildTodayCard(BuildContext context) {
    final tw = _teachingWeek;
    final sessions = tw == null
        ? const <ScheduledSession>[]
        : _sessionsOfToday(tw.week);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '今日课程',
              accent: FeaturePalette.cardAccent,
              trailing: Text(
                '${sessions.length} 节',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    tw?.isBeforeTerm == true ? '尚未开学' : '今天没有课',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (final s in sessions) _sessionTile(context, s),
          ],
        ),
      ),
    );
  }

  List<ScheduledSession> _sessionsOfToday(int week) {
    final entries = _entries;
    if (entries == null) return const [];
    return sessionsOfDay(
      entries: entries,
      table: _table,
      teachingWeek: week,
      day: _now,
      reschedules: _reschedules,
    );
  }

  Widget _sessionTile(BuildContext context, ScheduledSession s) {
    final scheme = Theme.of(context).colorScheme;
    final ongoing = s.isInClassAt(_now);
    final done = !ongoing && !s.startAt.isAfter(_now);
    final markBadge = rescheduleBadge(s.mark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              formatHhmm(s.startAt),
              style: TextStyle(
                fontSize: 13,
                fontWeight: ongoing ? FontWeight.w700 : FontWeight.w500,
                color: ongoing ? FeaturePalette.cardAccent : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.courseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: ongoing
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: done || s.isCancelled
                              ? scheme.onSurfaceVariant
                              : null,
                          decoration: s.isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (markBadge != null) ...[
                      const SizedBox(width: 6),
                      markBadge,
                    ],
                    if (ongoing) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: FeaturePalette.cardAccent.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '上课中',
                          style: TextStyle(
                            fontSize: 11,
                            color: FeaturePalette.cardAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.isCancelled
                      ? '${s.periodLabel} ${s.clockLabel} · 本次停课'
                      : '${s.periodLabel} ${s.clockLabel} · ${s.classroom}'
                            '${s.campus == null ? '' : ' · ${s.campus}'}'
                            '${(s.teacherOverride ?? '').isEmpty ? '' : ' · ${s.teacherOverride}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootnote(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '作息表取自教务公开页 SchoolTimetable.jsp（免登录），按学期缓存；'
      '课表缓存于本地，断网时倒计时依然准确。'
      '倒计时由系统时钟推进，因此本 App 无需常驻后台。',
      style: TextStyle(
        fontSize: 11.5,
        color: scheme.onSurfaceVariant,
        height: 1.6,
      ),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
