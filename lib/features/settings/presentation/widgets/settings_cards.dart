/// 设置页的 14 个分节卡（2026-09-20 从 `settings_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 原同文件的**全部顶层私有类**（12 个分节卡 + 它们各自的 State + 共享件 `_SubLabel` +
/// 顶层哨兵 `_clearSentinel`）整体搬到本文件，并改为 `Settings` 前缀的公开名
/// （`_` 是库私有，跨文件不可见）。`SettingsScreen` 本体仍留在 `settings_screen.dart`
/// （它只负责按 `sections:` 过滤并组装这些卡）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';

import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';

import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';

import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';

import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';

import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';

import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';

import 'package:smarter_jxufe/features/ims/auth/domain/ims_token_refresh.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/live_class_screen.dart';

import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';

import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';

import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';

import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';

import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';

/// 「不设置」在选择面板里的哨兵值。
///
/// 面板返回 `null` 表示用户取消（下滑关闭），要区分于「选择清空」，
/// 故清空走一个显式哨兵。
const settingsClearSentinel = '__clear__';

/// 「我的校区」选择入口卡。
///
/// 副标题讲清**这个值是谁给的**（用户 2026-09-20 要求校区设置接数据中心）：
/// - 手选过 → 以手选为准；数据中心那一份如果不一样，多一行提示（不自动改）；
/// - 从没设过 → 由数据中心的值自动补空（[MyCampusSource.center]）；
/// - 数据中心也取不到 → 「未设置 · 点击选择」，照旧手选（这就是「获取失败再手动设置」）。
class SettingsMyCampusTile extends StatelessWidget {
  final MyCampus? mine;
  final MyCampusSource? source;
  final MyCampus? center;
  final VoidCallback onTap;

  const SettingsMyCampusTile({
      super.key,
    
    required this.mine,
    required this.source,
    required this.center,
    required this.onTap,
  });

  /// 值来源的角标文案。
  ///
  /// 老存档（本功能之前设的）只写了 `campus` 一个键 → 没有来源标记；那时候的值
  /// 只可能是用户在设置页手选的，故照样标「手动设置」（别显示成一片空白）。
  String get _sourceBadge =>
      source == MyCampusSource.center ? '数据中心' : '手动设置';

  /// 校区名下面那一行小字。
  String get _subtitle {
    final mine = this.mine;
    final hint = center;
    if (mine == null) {
      return hint == null ? '未设置 · 点击选择' : '正在采用数据中心的值…';
    }
    final head = '${mine.label} · $_sourceBadge';
    if (hint != null && hint != mine) {
      return '$head（数据中心显示：${hint.label}）';
    }
    return head;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  Icons.place_outlined,
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
                      '我的校区',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: mine == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
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

/// 「生效范围」说明卡：把设置后的三处影响讲清楚。
class SettingsEffectCard extends StatelessWidget {
  final MyCampus? mine;

  const SettingsEffectCard({
      super.key,
      required this.mine});

  @override
  Widget build(BuildContext context) {
    // 先落到局部变量：公开字段无法参与空提升（non-promo public field）。
    final mine = this.mine;
    final lines = <String>[
      if (mine == null) ...[
        '电费绑定：进入更换面板时自动预选该校区，仍可手动更改',
        '学校地址：该校区条目置顶',
        '校区地图：该校区相关地图置顶',
      ] else ...[
        mine.supportsElectricity
            ? '电费绑定：自动预选「${mine.shortLabel}」，仍可手动更改'
            : '电费绑定：青山园校区无宿舍电费服务，绑定需手动选校区',
        '学校地址：「${mine.label}」已置顶',
        mine.mapEntryNames.isEmpty
            ? '校区地图：无对应地图条目'
            : '校区地图：「${mine.mapEntryNames.join('、')}」已置顶',
      ],
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine == null ? '设置后将在三处生效：' : '当前已生效：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: fp(context).cardAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(fontSize: 13, height: 19 / 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「主页布局」卡：宫格视图 / 左侧导航栏（用户 2026-09-15 裁定）。
///
/// 切换入口**只在这里**（不往顶栏加按钮），选择落 Hive `homePrefs`
/// （`HomeLayoutStore`，改动即时通知 → 主页无需重进即跟随）；
/// 手机端恒为宫格，判定集中在 `features/home/domain/home_layout.dart`。
/// 「外观」节：跟随系统 / 浅色 / 深色（用户 2026-09-16 拍板，默认跟随系统）。
///
/// - 选择存 Hive（`features/settings/data/theme_prefs.dart`），`MaterialApp.themeMode`
///   直接 `watch` 同一个 store → 点一下立即整树重建，中间没有「先闪一次旧值」的空窗。
/// - 深色配色 = **A 中性深灰** + 亮红强调（`lib/design/app_ladder.dart` /
///   `lib/design/app_theme.dart`），取值来自用户过目过的
///   `design_preview/dark_mode_preview.html`。
class SettingsAppearanceCard extends ConsumerWidget {
  const SettingsAppearanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(themeModeStoreProvider);
    final accent = fp(context).cardAccent;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final mode in ThemeMode.values)
            InkWell(
              key: Key('themeModeOption-${mode.name}'),
              onTap: () => store.save(mode),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      mode == store.mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: mode == store.mode
                          ? accent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            themeModeLabel(mode),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            themeModeDescription(mode),
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              '深色外观为中性深灰底 + 亮红强调色，卡片、文字、分隔线会一并切换；'
              '首次安装默认跟随系统。',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsHomeLayoutCard extends ConsumerWidget {
  const SettingsHomeLayoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(homeLayoutStoreProvider);
    final gridStore = ref.watch(homeGridStoreProvider);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final value in HomeLayout.values)
            InkWell(
              key: Key('homeLayoutOption-${value.name}'),
              onTap: () => store.save(value),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      value == store.layout
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: value == store.layout
                          ? fp(context).cardAccent
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.label,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value.description,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              '侧栏视图只在电脑端生效（窗口宽度 ≥ '
              '${homeSidebarMinWidth.toInt()}px）；手机端始终是宫格视图。',
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          // 宫格聚合（用户 2026-09-21 需求）：拖动说明 + 恢复默认布局。
          // 拖动/合并发生在**主页宫格**上，这里只放口径说明与兜底按钮
          // （用户 2026-09-11 裁定「偏好入口一律收在设置页」）。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '宫格聚合',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '长按某一格只拖动这一个功能；长按卡片其余部分（格与格之间的缝）'
                  '拖动整张卡片。拖到另一张卡片的边缘（最外侧约三分之一）'
                  '松手即合并成一张卡片，拖到卡片中间不会合并。'
                  '聚合卡片可以是不规则形状，互补的形状能相互嵌合。'
                  '顶栏的剪刀按钮可以进入拆解模式：卡片里出现分割线，点分割线断开这一处，'
                  '退出时仍然连着的会自动接回去。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _gridSummary(gridStore),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      key: const Key('homeGridReset'),
                      onPressed: () => unawaited(gridStore.reset()),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('恢复默认布局'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 聚合布局现状（给用户一句「现在是什么状态」）。
  String _gridSummary(HomeGridStore store) {
    final layout = store.layout;
    if (layout == null) return '当前为默认布局（未自定义）。';
    final groups = layout.groupCount;
    return '已自定义：${layout.tiles.length} 张卡片'
        '${groups > 0 ? '，其中 $groups 张是聚合卡片' : ''}。';
  }
}

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

/// 课表显示卡：是否显示周六 / 周日（用户 2026-09-17 要求）。
///
/// **唯一入口**（工作区铁律 §3：新增偏好一律收拢到设置页，页面不另开弹层）。
/// 偏好存 Hive `schedulePrefs`，课表竖版 / 横版读同一个控制器实例，改完立即生效。
/// 关闭某天时若**该学期**那天有课 → 先弹确认框（用户原话「当周六/周日有课时，
/// 关闭对应显示要弹出确认框提示用户」）：课程本身与调课记录都不受影响，只是课表
/// 里不再画那一天，随时可以打开。
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
              context,
              ref,
              prefs: prefs,
              label: '显示周六',
              dayIndex: scheduleSaturdayIndex,
              value: prefs.showSaturday,
              entries: entries,
            ),
            _daySwitch(
              context,
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
                    '关掉的只是「不显示」：课程、调课记录与统计都不受影响，'
                    '课表里的列数与列宽会自动按剩余天数重新铺满。',
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

  /// 一天一个开关：关闭前先看该学期这一天有没有课（有则确认）。
  Widget _daySwitch(
    BuildContext context,
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
            ? '本学期有 $count 门课安排在这一天'
            : '本学期这一天没有课',
        style: const TextStyle(fontSize: 11.5),
      ),
      onChanged: (v) async {
        if (!v && count > 0) {
          final confirmed = await _confirmHide(
            context,
            dayName: scheduleDayNames[dayIndex],
            count: count,
          );
          if (!confirmed) return;
        }
        await store.save(
          dayIndex == scheduleSaturdayIndex
              ? prefs.copyWith(showSaturday: v)
              : prefs.copyWith(showSunday: v),
        );
      },
    );
  }

  /// 隐藏有课的那一天 → 先确认（用户要求）。
  Future<bool> _confirmHide(
    BuildContext context, {
    required String dayName,
    required int count,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.visibility_off_outlined),
        title: Text('隐藏$dayName？'),
        content: Text(
          '$dayName 这一学期有 $count 门课，隐藏后课表里就看不到它们了。\n'
          '课程本身与调课记录都不受影响，随时可以重新打开。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('仍然隐藏'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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

/// 「公共查询」节：默认教学楼（找空闲教室 / 找无课时间用的默认值）。
///
/// 用户 2026-09-19 要求：「教学楼默认选哪个是可以设置的」。偏好落在
/// `features/ims/public_query/data/public_query_prefs.dart`（Hive box
/// `publicQueryPrefs`），本卡只读写它、**不发任何请求**；校区 / 楼房候选来自公共查询
/// 既有的两个下拉 provider，进弹层才取。
class SettingsPublicQueryCard extends ConsumerWidget {
  const SettingsPublicQueryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = AppColors.textMuted(context);
    final building = ref.watch(publicQueryPrefsStoreProvider).defaultBuilding;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('settingsDefaultBuilding'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => const SettingsBuildingPickerSheet(),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 18,
                    color: fp(context).cardAccent,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '默认教学楼',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      building?.label ?? '未设置',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: building == null
                            ? muted
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '「找空闲教室」打开时会自动选中这栋楼；若它不在当前校区，就不预选。',
                style: TextStyle(fontSize: 12, height: 1.5, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 默认教学楼选择弹层：**先选校区、再选楼房**（楼房码只在所属校区内才有意义）。
///
/// 预选口径 = ① 已存的默认教学楼（校区 + 楼房原样回填）；② 否则「我的校区」按名匹配
/// （`matchPublicQueryOption`，与 `classroom_free_screen.dart` 的
/// `_applyCampusDefault` 同口径）；③ 都拿不到就留空，绝不猜。
/// ⚠ 「**拿到值才落闸**」：`myCampusStoreProvider` 是异步加载的，首帧还没值就置位会让
/// 「我的校区」永远匹配不上（照 `classroom_free_screen.dart:158-167`）。
class SettingsBuildingPickerSheet extends ConsumerStatefulWidget {
  const SettingsBuildingPickerSheet({super.key});

  @override
  ConsumerState<SettingsBuildingPickerSheet> createState() =>
      SettingsBuildingPickerSheetState();
}

class SettingsBuildingPickerSheetState extends ConsumerState<SettingsBuildingPickerSheet> {
  /// 当前选中的校区码 / 楼房码（`''` = 未选）。
  String _campus = '';
  String _building = '';

  /// 是否已做过一次预选 —— `build` 每帧都会跑，重复预选会冲掉用户刚做的选择。
  bool _defaultsApplied = false;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMuted(context);
    final store = ref.watch(publicQueryPrefsStoreProvider);
    final campuses = ref.watch(publicQueryCampusesProvider).valueOrNull ?? [];
    if (!_defaultsApplied && _campus.isEmpty && campuses.isNotEmpty) {
      final saved = store.defaultBuilding;
      if (saved != null &&
          saved.campusCode.isNotEmpty &&
          campuses.any((c) => c.code == saved.campusCode)) {
        _defaultsApplied = true;
        _campus = saved.campusCode;
        _building = saved.buildingCode;
      } else {
        final myCampus = ref.read(myCampusStoreProvider).campus?.label ?? '';
        if (myCampus.isNotEmpty) {
          _defaultsApplied = true;
          final matched = matchPublicQueryOption(campuses, myCampus);
          if (matched != null) _campus = matched.code;
        }
      }
    }
    final buildingsAsync = _campus.isEmpty
        ? null
        : ref.watch(publicQueryBuildingsProvider(_campus));
    final buildings = buildingsAsync?.valueOrNull ?? [];
    // 只认列表里真有的码 —— `DropdownButton.value` 必须是某个 item，否则直接断言。
    final selected = buildings.any((b) => b.code == _building) ? _building : '';
    final buildingHint = buildingsAsync == null
        ? '请先选择校区'
        : (buildingsAsync.hasError ? '楼房列表加载失败' : '请选择楼房');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '默认教学楼',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _row(
              context,
              icon: Icons.location_city_outlined,
              label: '校区',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('settingsBuildingCampusPicker'),
                  isExpanded: true,
                  value: _campus.isEmpty ? null : _campus,
                  hint: Text(
                    '请选择校区',
                    style: TextStyle(fontSize: 13.5, color: muted),
                  ),
                  items: [
                    for (final c in campuses)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text(c.displayName),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _campus = v ?? '';
                    _building = '';
                  }),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _row(
              context,
              icon: Icons.apartment_outlined,
              label: '楼房',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('settingsBuildingPicker'),
                  isExpanded: true,
                  value: selected.isEmpty ? null : selected,
                  hint: Text(
                    buildingHint,
                    style: TextStyle(fontSize: 13.5, color: muted),
                  ),
                  items: [
                    for (final b in buildings)
                      DropdownMenuItem(
                        value: b.code,
                        child: Text(b.displayName),
                      ),
                  ],
                  onChanged: (v) => setState(() => _building = v ?? ''),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '「找空闲教室」打开时会自动选中这栋楼；若它不在当前校区，就不预选。',
              style: TextStyle(fontSize: 12, height: 1.5, color: muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  key: const Key('settingsBuildingClear'),
                  onPressed: store.defaultBuilding == null
                      ? null
                      : _clearSelection,
                  child: const Text('清除'),
                ),
                const Spacer(),
                FilledButton(
                  key: const Key('settingsBuildingSave'),
                  onPressed: selected.isEmpty ? null : _saveSelection,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 弹层里的一行：图标 + 定宽标签 + 控件（与 `classroom_free_screen.dart` 的 `_row`
  /// 同款，两处保持一种观感）。
  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) => Row(
    children: [
      Icon(icon, size: 17, color: AppColors.textMuted(context)),
      const SizedBox(width: 8),
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted(context)),
        ),
      ),
      Expanded(child: child),
    ],
  );

  /// 保存默认教学楼（校区名 / 楼房名一并落库 —— 找空闲教室只认 code，名字是给人看的）。
  Future<void> _saveSelection() async {
    final campuses = ref.read(publicQueryCampusesProvider).valueOrNull ?? [];
    final buildings =
        ref.read(publicQueryBuildingsProvider(_campus)).valueOrNull ?? [];
    var campusName = '';
    for (final c in campuses) {
      if (c.code == _campus) campusName = c.displayName;
    }
    var buildingName = '';
    for (final b in buildings) {
      if (b.code == _building) buildingName = b.displayName;
    }
    await ref.read(publicQueryPrefsStoreProvider).saveBuilding(
      PublicQueryBuilding(
        campusCode: _campus,
        campusName: campusName,
        buildingCode: _building,
        buildingName: buildingName,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 清除默认教学楼（`saveBuilding(null)`）—— 之后「找空闲教室」回到「我的校区」口径。
  Future<void> _clearSelection() async {
    await ref.read(publicQueryPrefsStoreProvider).saveBuilding(null);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

/// 平台标识（GUID）卡：展示当前配置状态并进入获取向导。
///
/// 用户 2026-09-11 裁定：「首页宫格里的获取 GUID 应该放到设置里」——宫格磁贴已删，
/// 设置页是本入口的唯一位置（网费实时源 / 请假记录 / 校历官方安排都依赖该标识）。
class SettingsPlatformGuidCard extends ConsumerWidget {
  const SettingsPlatformGuidCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final guid = ref.watch(platformGuidProvider).valueOrNull;
    final configured = guid != null && guid.isNotEmpty;
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
              icon: Icons.vpn_key_outlined,
              title: '微信平台标识（GUID）',
              subtitle: '校园网实时源 / 请假记录 / 校历官方安排 都依赖它',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: configured
                        ? AppColors.successFill(context)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    configured ? '已配置' : '未配置',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: configured
                          ? AppColors.success(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    configured
                        ? '当前：${_maskGuid(guid)}'
                        : '未配置时相关功能自动回退离线 / 门户数据源',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GuidGuideScreen(),
                  ),
                ),
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: Text(configured ? '查看 / 更新' : '去获取'),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GUID 由微信授权「智慧江财」下发，等同账号标识，一次获取长期有效；'
                    'App 内可一键抓取，也可从剪贴板或手动粘贴保存。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 只露出前 8 位，避免把账号级标识完整铺在界面上。
  String _maskGuid(String guid) =>
      guid.length <= 8 ? guid : '${guid.substring(0, 8)}…';
}

/// 「教务会话」卡 —— 教务登录令牌（JSESSIONID）的探活与手动换票。
///
/// 用户 2026-09-15：要求「在设置里加一个刷新 IMS 登录令牌的按钮」，并裁定语义为
/// **先探活、失效才换**——业务页面遇到「凭证已失效」本来就会自动换票
/// （`ImsAuthInterceptor` → `ImsSession.renew()`），这个按钮是给「怪状态」兜底的
/// 手动通道，不该每次按都白烧一次 CAS 往返。
///
/// 卡片状态全部来自本会话实例（`imsSessionProvider`，切号即重建）：
/// 令牌掩码 / 签发时间 / 失败原因都是**只读展示**，只有按钮会发网络。
class SettingsImsSessionCard extends ConsumerStatefulWidget {
  const SettingsImsSessionCard({super.key});

  @override
  ConsumerState<SettingsImsSessionCard> createState() => SettingsImsSessionCardState();
}

class SettingsImsSessionCardState extends ConsumerState<SettingsImsSessionCard> {
  bool _busy = false;
  bool _loading = true;
  ImsProbeResult? _probe;
  String? _error;
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocal());
  }

  /// 首屏只读本地（内存 → 磁盘）令牌：**一个请求都不发，更不会顺手换票**
  /// （`ensureReady()` 在本地没有令牌时会走 CAS 换票，打开设置页不该触发登录）。
  Future<void> _loadLocal() async {
    await ref.read(imsSessionProvider).peek();
    if (mounted) setState(() => _loading = false);
  }

  /// 按一下按钮：探活 → 只有「失效 / 本机没有 / 判不出」才换票。
  Future<void> _refresh() async {
    final session = ref.read(imsSessionProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    var probe = ImsProbeResult.unknown;
    var success = false;
    try {
      probe = await session.probe();
      if (imsTokenRefreshActionFor(probe) == ImsTokenRefreshAction.renew) {
        await session.renew();
      }
      success = true;
    } catch (e) {
      if (mounted) setState(() => _error = _shortError(e));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _loading = false;
      _probe = probe;
      _checkedAt = DateTime.now();
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(imsRefreshOutcomeText(probe: probe, success: success)),
      ),
    );
  }

  /// 失败原因只给一行，别把整段堆栈铺到卡片上。
  String _shortError(Object e) {
    final text = e.toString().replaceAll('\n', ' ');
    return text.length <= 140 ? text : '${text.substring(0, 140)}…';
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  ({String label, Color tint, Color text}) _status(
    ColorScheme scheme, {
    required bool ready,
    required bool failed,
  }) {
    if (_busy) {
      return (
        label: '刷新中',
        tint: AppColors.tint(context, fp(context).cardAccent, 0.12),
        text: fp(context).cardAccent,
      );
    }
    if (_loading) {
      return (
        label: '读取中',
        tint: AppColors.tint(context, fp(context).cardAccent, 0.12),
        text: fp(context).cardAccent,
      );
    }
    if (ready) {
      return (
        label: '已就绪',
        tint: AppColors.successFill(context),
        text: AppColors.success(context),
      );
    }
    if (failed) {
      return (
        label: '不可用',
        tint: AppColors.statusFill(context, scheme.error),
        text: scheme.error,
      );
    }
    return (
      label: '未就绪',
      tint: scheme.surfaceContainerHighest,
      text: scheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(imsSessionProvider);
    // 切号 = 会话实例重建：卡片上的「最近探活」等本地状态必须跟着清掉。
    ref.listen(imsSessionProvider, (prev, next) {
      if (prev?.account != next.account) {
        setState(() {
          _probe = null;
          _error = null;
          _checkedAt = null;
          _loading = true;
        });
        unawaited(_loadLocal());
      }
    });

    final token = session.jsessionId ?? '';
    final ready = token.isNotEmpty;
    final status = _status(
      scheme,
      ready: ready,
      failed: !ready && session.phase == ImsSessionPhase.failed,
    );
    final issued = session.issuedAt;
    final meta =
        '账号 ${session.account.isEmpty ? '—' : session.account} · '
        '${issued == null ? '签发时间未知（本次启动尚未换票）' : '签发 ${_clock(issued)}'}';

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
              icon: Icons.verified_user_outlined,
              title: '教务登录令牌（IMS 会话）',
              subtitle: '成绩 / 课表 / 选课 / 公共查询 共用同一张令牌',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: status.tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: status.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ready ? '当前：${maskImsToken(token)}' : '本机暂无令牌，点下方按钮获取',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              meta,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            if (_probe != null) ...[
              const SizedBox(height: 2),
              Text(
                '最近探活 ${_clock(_checkedAt ?? DateTime.now())}：'
                '${imsProbeLabel(_probe!)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 2),
              Text(
                '最近一次失败：$_error',
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _refresh,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_busy ? '刷新中…' : '刷新登录令牌'),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点击后先探活：令牌仍有效就只提示、不重复换票；确认失效'
                    '（或本机没有、判不出）才走统一身份认证重新取票并落盘。'
                    '业务页面遇到「凭证已失效」会自动换票重试，平时不必手动点。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
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

/// 卡片内的小节标题（图标 + 标题 + 说明）。
class SettingsSubLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 强调色；`null` = 用随主题解析的主题红（浅色校红 / 深色亮红）。
  final Color? accent;

  const SettingsSubLabel({
      super.key,
    
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tint = accent ?? fp(context).cardAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 6),
            Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 桌面小组件卡：一键把「数据一览 / 电费余额 / 课程加权」的八档尺寸固定到桌面。
///
/// 走系统 `AppWidgetManager.requestPinAppWidget`（API 26+）。**桌面分页归启动器管，
/// App 没有任何接口能命令桌面新建页面**：实测各渠道在「当前页放不下」时，小米 /
/// OPPO / vivo / 三星会自动新建一页放置，**华为 / honor 不会**，只提示「当前页面
/// 空间不足」（桌面自己弹的，App 拦不掉）。
///
/// 用户 2026-09-11 裁定：**不做任何「满页引导」**——取消确认框与桌面满页在代码里
/// 无法区分，自动弹层会误报，宁可不要。只保留「已在桌面」标记：尺寸 chip 上的 ✓
/// 与底部图例，由原生 `HomeWidgetBridge.pinnedCounts()`（`getAppWidgetIds` 计数）
/// 驱动，纯查询、无副作用。
class SettingsHomeWidgetCard extends StatefulWidget {
  const SettingsHomeWidgetCard({super.key});

  @override
  State<SettingsHomeWidgetCard> createState() => SettingsHomeWidgetCardState();
}

class SettingsHomeWidgetCardState extends State<SettingsHomeWidgetCard>
    with WidgetsBindingObserver {
  /// 与原生 `WidgetSize.tag` 一一对应（宽 × 高，单位 = 桌面格子）。
  static const _sizes = <String>[
    '2x1',
    '3x1',
    '4x1',
    '5x1',
    '2x2',
    '3x2',
    '4x2',
    '5x2',
  ];

  /// 「已在桌面」的绿（与其他模块的达标绿一致）—— 现在随主题解析，
  /// 用 `AppColors.success(context)`（深色下自动提亮），不再是固定 const。

  /// 「指标:尺寸」→ 桌面上已放置的实例数（原生 `getAppWidgetIds`）。
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户去桌面加/删了小组件再回来 → 刷新「已在桌面」标记。
    if (state == AppLifecycleState.resumed) _loadCounts();
  }

  static IconData _icon(HomeWidgetMetric metric) => switch (metric) {
    HomeWidgetMetric.dashboard => Icons.dashboard_outlined,
    HomeWidgetMetric.electricity => Icons.bolt_outlined,
    HomeWidgetMetric.grades => Icons.school_outlined,
  };

  static Color _color(BuildContext context, HomeWidgetMetric metric) =>
      switch (metric) {
        HomeWidgetMetric.dashboard => fp(context).dashboard,
        HomeWidgetMetric.electricity => fp(context).electricity,
        HomeWidgetMetric.grades => fp(context).grade,
      };

  Future<void> _loadCounts() async {
    final counts = await HomeWidgetBridge.pinnedCounts();
    if (!mounted) return;
    setState(() => _counts = counts);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 5)),
      );
  }

  Future<void> _pin(HomeWidgetMetric metric, String size) async {
    final label = '${metric.defaultLabel} ${size.replaceAll('x', '×')}';
    final result = await HomeWidgetBridge.requestPinWidget(
      metric: metric,
      size: size,
    );
    if (!mounted) return;
    final text = !result.supported
        ? '当前桌面不支持一键添加，请长按应用图标 → 服务卡片，选「$label」'
        : result.requested
        ? '已请求添加「$label」，请在系统弹窗中确认'
        : '添加请求未生效，请长按应用图标 → 服务卡片手动添加「$label」';
    _snack(text);
    // 用户确认后 ✓ 标记要跟上：先延迟刷一次（确认框不暂停本页的情况），
    // 回前台时 didChangeAppLifecycleState 还会再刷一次。
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) _loadCounts();
    });
  }

  Widget _chip(HomeWidgetMetric metric, String size) {
    final placed = _counts[homeWidgetPinKey(metric, size)] ?? 0;
    return ActionChip(
      avatar: placed > 0
          ? Icon(
              Icons.check_circle,
              size: 15,
              color: AppColors.success(context),
            )
          : null,
      label: Text(
        size.replaceAll('x', '×'),
        style: const TextStyle(fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      tooltip: placed > 0 ? '已在桌面 $placed 个，再点会再加一个' : '点一下请求添加到桌面',
      onPressed: () => _pin(metric, size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placedTotal = _counts.values
        .where((c) => c > 0)
        .fold<int>(0, (sum, c) => sum + c);
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
              icon: Icons.widgets_outlined,
              title: '添加到桌面',
              subtitle: '点尺寸即请求系统固定该小组件，已放置的尺寸带 ✓',
              accent: fp(context).cardAccent,
            ),
            for (final metric in HomeWidgetMetric.values) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(_icon(metric), size: 15, color: _color(context, metric)),
                  const SizedBox(width: 6),
                  Text(
                    metric.defaultLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [for (final size in _sizes) _chip(metric, size)],
              ),
            ],
            const SizedBox(height: 10),
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
                    '共 8 档：2×1 / 3×1 / 4×1 / 5×1 是单行条（只放数值，最窄档自动改用短标题'
                    '与短数值），2×2 及以上带副文本；「数据一览」在小尺寸只显示前几项。'
                    '数据随 App 打开、手机解锁与后台任务刷新，点小组件直达对应页面。',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
            if (placedTotal > 0) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 15, color: AppColors.success(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '带 ✓ 的尺寸已经在桌面上，共 $placedTotal 个。',
                      style: const TextStyle(fontSize: 11.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
