/// `settings_cards.dart` 的「schedule」一组（2026-10-08 架构审计第三轮 · 按类拆文件）。
///
/// 拆分自 `settings_cards.dart`（2297 行 / 20 个 widget 类）：调用方**不用改** —— 桶文件
/// `export` 了本文件。共用顶层件（`settingsClearSentinel` / `SettingsSubLabel`）留在桶里，
/// 故这里反向 import 桶文件（Dart 允许互相 import，见 AGENTS.md §33.4.4 ②）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/live_class_screen.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'settings_cards.dart';

/// 「上课实况窗」入口卡（2026-09-15 从首页宫格迁到设置页，用户裁定「主页不要显示」）。
///
/// 页面本体 `LiveClassScreen` 与 Android 常驻通知完全没变，只是入口换了地方。
class SettingsLiveClassCard extends StatelessWidget {
  const SettingsLiveClassCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LiveClassScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, fp(context).cardAccent, 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.podcasts_outlined,
                  color: fp(context).cardAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '上课实况窗',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '上课中与下一节课 · 通知栏常驻倒计时'
                      '（Android；Windows 暂不支持常驻通知）',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 校历偏好卡：角标风格 + 军训角标 + 人群过滤。
///
/// 判定口径见 `lib/features/school_calendar/domain/calendar_day_mark.dart`；
/// 三项都只影响「显示」，不改动任何缓存数据。
class SettingsCalendarDisplayCard extends ConsumerWidget {
  const SettingsCalendarDisplayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(calendarPrefsStoreProvider).prefs;
    final store = ref.read(calendarPrefsStoreProvider);
    final viewer =
        ref.watch(calendarViewerProvider).valueOrNull ?? CalendarViewer.unknown;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSubLabel(
              icon: Icons.label_outline,
              title: '角标风格',
              subtitle: '月历上「假 / 班 / 运 / 考」等角标的画法',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final style in CalendarBadgeStyle.values)
                  ChoiceChip(
                    label: Text(
                      style.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: prefs.badgeStyle == style,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        store.save(prefs.copyWith(badgeStyle: style)),
                  ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.alwaysShowMilitary,
              onChanged: (v) =>
                  store.save(prefs.copyWith(alwaysShowMilitary: v)),
              title: const Text('非新生也显示军训', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                viewer.enrollYear != null
                    ? '当前学籍：${viewer.label} —— 军训只在入学年对应的学年显示'
                    : '未获取到学籍：军训只按「入学年 == 学年」判断（当前不显示）',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.filterByCategory,
              onChanged: (v) => store.save(prefs.copyWith(filterByCategory: v)),
              title: const Text('按我的培养层次过滤', style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                viewer.hasInfo
                    ? '官方安排按「教职员工 / 本科生 / 研究生」分节，只显示本人相关的'
                          '运动会 / 考试等事件；放假与补课不受影响'
                    : '未获取到学籍，官方事件将全部显示',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '角标来自学校官方逐日安排（小程序校历，未配置 GUID 时用内置快照）；'
                    '教务校历的 workday/nonday 仅用于补寒暑假等学期外假期。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 课表显示卡：是否显示周六 / 周日（用户 2026-09-17 要求）+ 表格线。
///
/// **唯一入口**（工作区铁律 §3：新增偏好一律收拢到设置页，页面不另开弹层）。
/// 偏好存 Hive `schedulePrefs`，课表竖版 / 横版读同一个控制器实例，改完立即生效。
///
/// ⚠ **2026-10-08 口径修订**（用户原话：「隐藏生效仅当没课时才生效，如果某周周 x
/// 有课，但是设置又是隐藏周 x，那么此时这天还是显示的」）：开关从「一刀切不画那一天」
/// 改成「**这一周这一天没课**才收起这一列」。于是：
/// - 从前那个「关掉之后这些课就看不见了 / 要不要继续」的确认框**已删除** —— 它警告的
///   事不再可能发生（有课的列永远照常显示），留着只是白点一次；
/// - 开关副标题改成说明性的「本学期有 N 门课安排在这一天」，让用户知道这一天的分量
///   （计数口径见 `scheduleDayCourseCount`，是**不认校历**的粗计数）。
/// - ⚠ **粒度是一周、但冻结在分页器停稳那一刻**（同日二轮用户原话：「如果周六在第 5 周
///   因为补课而有课，但是其他周没有，那么在其他周的视图中，周六就不应该显示」）：
///   按周算才对，但**动画途中不许变列数**（否则整屏在飞行中重排 —— 用户报的「动画
///   错乱」）。口径由页面负责，见 `schedule_screen.dart` 的 `_layoutWeek`。
/// 判据实现见 `domain/schedule_board.dart` 的 `scheduleDaysWithClass`。
class SettingsScheduleDisplayCard extends ConsumerWidget {
  const SettingsScheduleDisplayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(scheduleDisplayPrefsStoreProvider).prefs;
    // 读的是**该学期**的课表缓存（不联网）：设置页拿不到课表页的学籍号，
    // 故用 `readCacheAnyStudent` 的「任一学生」口径。
    // 传了内置学期快照 → 一定命中当前学期（假期取下一学期），返回值非空。
    final term = currentSchoolTerm(
      DateTime.now(),
      terms: ref.watch(offlineSemesterTermsProvider),
    );
    final entries =
        ref.watch(scheduleCachedEntriesProvider(term)).valueOrNull ??
        const <ScheduleEntry>[];
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSubLabel(
              icon: Icons.calendar_view_week,
              title: '显示范围',
              subtitle: '是否显示周六 / 周日（竖版与横版课表都生效）',
            ),
            const SizedBox(height: 6),
            _daySwitch(
              ref,
              prefs: prefs,
              label: '显示周六',
              dayIndex: scheduleSaturdayIndex,
              value: prefs.showSaturday,
              entries: entries,
            ),
            _daySwitch(
              ref,
              prefs: prefs,
              label: '显示周日',
              dayIndex: scheduleSundayIndex,
              value: prefs.showSunday,
              entries: entries,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '关掉的只是「这一周这一天没课」时的那一列：有课的那一周照常显示，'
                    '课程、调课记录与统计也都不受影响，列数与列宽会自动按剩余天数铺满。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const SettingsSubLabel(
              icon: Icons.grid_on,
              title: '表格线',
              subtitle: '是否显示课表的网格线（竖版与横版都生效）',
            ),
            const SizedBox(height: 6),
            // 用户 2026-09-17：「我希望课表可以设置是否显示表格线」。
            // 不需要确认框（纯观感开关，点错了再点回来即可）。
            SwitchListTile(
              key: const Key('scheduleGridLinesSwitch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: prefs.showGridLines,
              title: const Text('显示表格线', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '关掉后不画任何网格线，课格靠自身底色区分（调课标记不受影响）',
                style: TextStyle(fontSize: 11.5),
              ),
              onChanged: (v) => ref
                  .read(scheduleDisplayPrefsStoreProvider)
                  .save(prefs.copyWith(showGridLines: v)),
            ),
          ],
        ),
      ),
    );
  }

  /// 一天一个开关。
  ///
  /// 2026-10-08 起**不再弹确认框**（口径修订见类头）：隐藏已经不可能让用户看不到课，
  /// 副标题只负责说明这一天在整学期里的分量。
  Widget _daySwitch(
    WidgetRef ref, {
    required ScheduleDisplayPrefs prefs,
    required String label,
    required int dayIndex,
    required bool value,
    required List<ScheduleEntry> entries,
  }) {
    final store = ref.read(scheduleDisplayPrefsStoreProvider);
    final count = scheduleDayCourseCount(entries, dayIndex);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      title: Text(label, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        count > 0
            // 「有课的那一周仍会显示」是这张卡最容易被误解的地方（用户 2026-10-08
            // 专门要求改掉旧的「隐藏就看不见了」），文案必须说清。
            ? '本学期有 $count 门课安排在这一天（有课的那一周仍会显示）'
            : '本学期这一天没有课',
        style: const TextStyle(fontSize: 11.5),
      ),
      onChanged: (v) => store.save(
        dayIndex == scheduleSaturdayIndex
            ? prefs.copyWith(showSaturday: v)
            : prefs.copyWith(showSunday: v),
      ),
    );
  }
}

/// 入馆教育卡：公共 / 后门模式切换。
///
/// **唯一入口**（用户 2026-09-11 裁定：「公共模式的切换和后门模式,不应该显示在
/// 任何页面,只能显示在设置页」）。模式落盘在 Hive `tsgxsPrefs`，答题页 / 章节页
/// 读同一个控制器实例，改完立即生效。
class SettingsLibraryEduModeCard extends ConsumerWidget {
  const SettingsLibraryEduModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(tsgxsExamPrefsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSubLabel(
              icon: Icons.menu_book_outlined,
              title: '闯关答题模式',
              subtitle: '入馆教育章节页与答题页的作答方式（仅此处可切换）',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 12),
            SegmentedButton<TsgxsAnswerMode>(
              segments: [
                for (final m in TsgxsAnswerMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(
                      m.label,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    icon: Icon(
                      m == TsgxsAnswerMode.normal
                          ? Icons.verified_user_outlined
                          : Icons.vpn_key_outlined,
                    ),
                  ),
              ],
              selected: {store.mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => store.save(s.first),
            ),
            const SizedBox(height: 12),
            for (final m in TsgxsAnswerMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m == store.mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: m == store.mode
                          ? fp(context).cardAccent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${m.label}：${m.hint}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: m == store.mode
                              ? null
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '后门模式下章节页不显示线索卡片,进入答题时会自动补全线索;'
                    '「一键探底」逐题收集正确答案,若被判闯关失败会自动重新开考继续,'
                    '直到通过(最多 6 轮)。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
