/// 设置页 —— 全局偏好的集中入口（首页右上角齿轮进入）。
///
/// 目前承载「我的校区」与「校历」两组偏好：校区一旦设置，电费绑定免手动选校区、
/// 学校地址与校区地图把该校区条目置顶；校历偏好控制月历「假/班」角标的画法与
/// 事件过滤口径（判定规则见 `domain/calendar_day_mark.dart`）。
/// 后续偏好项（通知等）一律收拢到本页，不再散落到各页的 feature-local 弹层。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/domain/ims_token_refresh.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/live_class_screen.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/library_sync/presentation/libsp_sync_card.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_settings_section.dart';

// 各节卡片的强调色：2026-09-15 全应用统一为综测卡样式 → 一律主题红；
// 2026-09-16 深色适配起**改为随主题解析**（`fp(context).cardAccent`：
// 浅色校红 #C3282E / 深色亮红 #F2555A），不再用 const。

/// 「不设置」在选择面板里的哨兵值。
///
/// 面板返回 `null` 表示用户取消（下滑关闭），要区分于「选择清空」，
/// 故清空走一个显式哨兵。
const _clearSentinel = '__clear__';

/// 设置页的分节（定义在 `domain/settings_section.dart`，页面只引那个小文件）。
///
/// 用户 2026-09-16 裁定：**每个服务主页的标题栏右上角都显示设置按钮**，从主页
/// 进入 = 完整设置页；从某个功能页进入 = **只显示该页相关的这一节**。页面把
/// 自己要显示的节交给 `paneAppBar(..., settingsSections: […])`（见
/// `settings_entry.dart`），没有对应节的页面就传空 = 完整设置页。
/// 设置页。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.sections = const <SettingsSection>[]});

  /// 只显示这些节；**空 = 完整设置页**（主页 / 无对应节的页面进入）。
  final List<SettingsSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myCampusStoreProvider).campus;
    // 全部分节（顺序 = 完整设置页里的顺序）。
    final blocks = <({SettingsSection section, Widget title, Widget card})>[
      // 外观（跟随系统 / 浅色 / 深色）：2026-09-16 深色模式适配新增。
      // 用户裁定「全局偏好入口 = 设置页」，故不另开弹层；排在第一节。
      (
        section: SettingsSection.appearance,
        title: geCardTitle(
          context,
          text: '外观',
          accent: fp(context).cardAccent,
        ),
        card: const _AppearanceCard(),
      ),
      // 内置 AI 助手（用户 2026-09-19 立项）：供应商预设 / 多套配置 / 悬浮球开关。
      // 整块的实现放在 `features/ai/presentation/widgets/ai_settings_section.dart`，
      // 设置页只挂一个入口（避免 1600 行的设置页再涨）。
      (
        section: SettingsSection.aiAssistant,
        title: geCardTitle(context, text: 'AI 助手', accent: fp(context).cardAccent),
        card: const AiAssistantSettingsCard(),
      ),
      (
        section: SettingsSection.campus,
        title: geCardTitle(context, text: '校区', accent: fp(context).cardAccent),
        card: _MyCampusTile(
          mine: mine,
          onTap: () => _pickCampus(context, ref, mine),
        ),
      ),      (
        section: SettingsSection.scope,
        title: geCardTitle(context, text: '生效范围', accent: fp(context).cardAccent),
        card: _EffectCard(mine: mine),
      ),
      // 主页布局（宫格 / 左侧导航栏）：用户 2026-09-15 裁定「只在设置页切换 + 记住」。
      (
        section: SettingsSection.homeLayout,
        title: geCardTitle(context, text: '主页布局', accent: fp(context).cardAccent),
        card: const _HomeLayoutCard(),
      ),
      (
        section: SettingsSection.calendar,
        title: geCardTitle(context, text: '校历', accent: fp(context).cardAccent),
        card: const _CalendarDisplayCard(),
      ),
      // 课表显示（是否显示周六 / 周日）：用户 2026-09-17 要求，入口按铁律收拢在设置页
      // （课表页齿轮进本节，页面上不另开弹层）。
      (
        section: SettingsSection.schedule,
        title: geCardTitle(context, text: '课表', accent: fp(context).cardAccent),
        card: const _ScheduleDisplayCard(),
      ),
      (
        section: SettingsSection.libraryEdu,
        title: geCardTitle(context, text: '入馆教育', accent: fp(context).cardAccent),
        card: const _LibraryEduModeCard(),
      ),
      // 入口 2026-09-11 从首页宫格迁到设置页（用户裁定）。
      (
        section: SettingsSection.platformGuid,
        title: geCardTitle(context, text: '平台标识', accent: fp(context).cardAccent),
        card: const _PlatformGuidCard(),
      ),
      // 「上课实况窗」入口 2026-09-15 从首页宫格迁到设置页（用户裁定：主页不要显示）。
      (
        section: SettingsSection.liveClass,
        title: geCardTitle(context, text: '上课实况窗', accent: fp(context).cardAccent),
        card: const _LiveClassCard(),
      ),
      // 教务登录令牌（JSESSIONID）的探活 / 手动换票入口（用户 2026-09-15 要求）。
      (
        section: SettingsSection.imsSession,
        title: geCardTitle(context, text: '教务会话', accent: fp(context).cardAccent),
        card: const _ImsSessionCard(),
      ),
      // 云同步（用图书馆「我的订阅」当存储面；协议见
      // `reverse_engineering/图书馆订阅词云同步方案.md`）。用户 2026-09-17 裁定
      // 做成正式功能（所有装了 App 的同学都能同步），故入口收拢在设置页。
      (
        section: SettingsSection.cloudSync,
        title: geCardTitle(context, text: '云同步', accent: fp(context).cardAccent),
        card: const LibspSyncCard(),
      ),
      (
        section: SettingsSection.homeWidget,
        title: geCardTitle(context, text: '桌面小组件', accent: fp(context).cardAccent),
        card: const _HomeWidgetCard(),
      ),
    ];
    final visible = [
      for (final b in blocks)
        if (sections.isEmpty || sections.contains(b.section)) b,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(sections.length == 1 ? sections.first.label : '设置'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            visible[i].title,
            const SizedBox(height: 12),
            visible[i].card,
            if (i != visible.length - 1) const SizedBox(height: 26),
          ],
        ],
      ),
    );
  }

  /// 底部选择面板：4 个校区 + 不设置。
  Future<void> _pickCampus(
    BuildContext context,
    WidgetRef ref,
    MyCampus? current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                '我的校区',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in MyCampus.values)
              ListTile(
                leading: Icon(
                  c == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: c == current
                      ? fp(context).cardAccent
                      : Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
                title: Text(c.label),
                subtitle: c.supportsElectricity
                    ? null
                    : const Text(
                        '无宿舍电费服务，其余功能正常',
                        style: TextStyle(fontSize: 12),
                      ),
                onTap: () => Navigator.of(sheetContext).pop(c.name),
              ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.clear,
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
              title: const Text('不设置'),
              enabled: current != null,
              onTap: () => Navigator.of(sheetContext).pop(_clearSentinel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return; // 用户取消
    await ref
        .read(myCampusStoreProvider)
        .save(picked == _clearSentinel ? null : MyCampus.fromName(picked));
  }
}

/// 「我的校区」选择入口卡。
class _MyCampusTile extends StatelessWidget {
  final MyCampus? mine;
  final VoidCallback onTap;

  const _MyCampusTile({required this.mine, required this.onTap});

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
                      mine?.label ?? '未设置 · 点击选择',
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
class _EffectCard extends StatelessWidget {
  final MyCampus? mine;

  const _EffectCard({required this.mine});

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
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

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

class _HomeLayoutCard extends ConsumerWidget {
  const _HomeLayoutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final store = ref.watch(homeLayoutStoreProvider);
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
        ],
      ),
    );
  }
}

/// 「上课实况窗」入口卡（2026-09-15 从首页宫格迁到设置页，用户裁定「主页不要显示」）。
///
/// 页面本体 `LiveClassScreen` 与 Android 常驻通知完全没变，只是入口换了地方。
class _LiveClassCard extends StatelessWidget {
  const _LiveClassCard();

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
class _CalendarDisplayCard extends ConsumerWidget {
  const _CalendarDisplayCard();

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
            _SubLabel(
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
class _ScheduleDisplayCard extends ConsumerWidget {
  const _ScheduleDisplayCard();

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
            const _SubLabel(
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
            const _SubLabel(
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
class _LibraryEduModeCard extends ConsumerWidget {
  const _LibraryEduModeCard();

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
            _SubLabel(
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

/// 平台标识（GUID）卡：展示当前配置状态并进入获取向导。
///
/// 用户 2026-09-11 裁定：「首页宫格里的获取 GUID 应该放到设置里」——宫格磁贴已删，
/// 设置页是本入口的唯一位置（网费实时源 / 请假记录 / 校历官方安排都依赖该标识）。
class _PlatformGuidCard extends ConsumerWidget {
  const _PlatformGuidCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final guid = ref.watch(wxGuidProvider).valueOrNull;
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
            _SubLabel(
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
class _ImsSessionCard extends ConsumerStatefulWidget {
  const _ImsSessionCard();

  @override
  ConsumerState<_ImsSessionCard> createState() => _ImsSessionCardState();
}

class _ImsSessionCardState extends ConsumerState<_ImsSessionCard> {
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
            _SubLabel(
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
class _SubLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// 强调色；`null` = 用随主题解析的主题红（浅色校红 / 深色亮红）。
  final Color? accent;

  const _SubLabel({
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
class _HomeWidgetCard extends StatefulWidget {
  const _HomeWidgetCard();

  @override
  State<_HomeWidgetCard> createState() => _HomeWidgetCardState();
}

class _HomeWidgetCardState extends State<_HomeWidgetCard>
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
            _SubLabel(
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
