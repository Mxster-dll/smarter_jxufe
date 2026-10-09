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

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_center.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/library_sync/presentation/libsp_sync_card.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_settings_section.dart';

// 各节卡片的强调色：2026-09-15 全应用统一为综测卡样式 → 一律主题红；
// 2026-09-16 深色适配起**改为随主题解析**（`fp(context).cardAccent`：
// 浅色校红 #C3282E / 深色亮红 #F2555A），不再用 const。

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
    final store = ref.watch(myCampusStoreProvider);
    final mine = store.campus;
    // 数据中心那一份（`所属校区`）：**只补空**——从没手选过时由
    // `myCampusStoreProvider` 自动写进 store（见 `my_campus_center.dart`），
    // 手选过的以手选为准，这里只把它当提示显示。
    final centerCampus = ref.watch(myCampusHintProvider);
    // 全部分节（顺序 = 完整设置页里的顺序）。
    final blocks = <({SettingsSection section, Widget title, Widget card})>[
      // 外观（跟随系统 / 浅色 / 深色）：2026-09-16 深色模式适配新增。
      // 用户裁定「全局偏好入口 = 设置页」，故不另开弹层；排在第一节。
      // 2026-10-09 同一节再加一张「窗口标题栏」（三键风格 / logo 与三键左右互换）：
      // 两者都是外观，分成两节会让「外观」这一节只剩主题、看着像漏了东西。
      (
        section: SettingsSection.appearance,
        title: geCardTitle(
          context,
          text: '外观',
          accent: fp(context).cardAccent,
        ),
        card: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsAppearanceCard(),
            // 卡片自带 12 的上边距（非 Windows 平台它整块是 shrink，不留空）。
            SettingsWindowBarCard(),
          ],
        ),
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
        card: SettingsMyCampusTile(
          mine: mine,
          source: store.source,
          center: centerCampus,
          onTap: () => _pickCampus(context, ref, mine),
        ),
      ),      (
        section: SettingsSection.scope,
        title: geCardTitle(context, text: '生效范围', accent: fp(context).cardAccent),
        card: SettingsEffectCard(mine: mine),
      ),
      // 主页布局（宫格 / 左侧导航栏）：用户 2026-09-15 裁定「只在设置页切换 + 记住」。
      (
        section: SettingsSection.homeLayout,
        title: geCardTitle(context, text: '主页布局', accent: fp(context).cardAccent),
        card: const SettingsHomeLayoutCard(),
      ),
      (
        section: SettingsSection.calendar,
        title: geCardTitle(context, text: '校历', accent: fp(context).cardAccent),
        card: const SettingsCalendarDisplayCard(),
      ),
      // 课表显示（是否显示周六 / 周日）：用户 2026-09-17 要求，入口按铁律收拢在设置页
      // （课表页齿轮进本节，页面上不另开弹层）。
      (
        section: SettingsSection.schedule,
        title: geCardTitle(context, text: '课表', accent: fp(context).cardAccent),
        card: const SettingsScheduleDisplayCard(),
      ),
      // 课前提醒（上课前 X 分钟起的常驻通知）：2026-09-22 用户立项，
      // 偏好与排期口径见 `docs/agents/35-上课提醒（课前常驻通知）.md`。
      (
        section: SettingsSection.classReminder,
        title: geCardTitle(
          context,
          text: '上课提醒',
          accent: fp(context).cardAccent,
        ),
        card: const SettingsClassReminderCard(),
      ),
      (
        section: SettingsSection.libraryEdu,
        title: geCardTitle(context, text: '入馆教育', accent: fp(context).cardAccent),
        card: const SettingsLibraryEduModeCard(),
      ),
      // 入口 2026-09-11 从首页宫格迁到设置页（用户裁定）。
      (
        section: SettingsSection.platformGuid,
        title: geCardTitle(context, text: '平台标识', accent: fp(context).cardAccent),
        card: const SettingsPlatformGuidCard(),
      ),
      // 「上课实况窗」入口 2026-09-15 从首页宫格迁到设置页（用户裁定：主页不要显示）。
      (
        section: SettingsSection.liveClass,
        title: geCardTitle(context, text: '上课实况窗', accent: fp(context).cardAccent),
        card: const SettingsLiveClassCard(),
      ),
      // 教务登录令牌（JSESSIONID）的探活 / 手动换票入口（用户 2026-09-15 要求）。
      (
        section: SettingsSection.imsSession,
        title: geCardTitle(context, text: '教务会话', accent: fp(context).cardAccent),
        card: const SettingsImsSessionCard(),
      ),
      // 公共查询（找空闲教室 / 找无课时间）的默认值入口 —— 默认教学楼在这里设
      // （用户 2026-09-19 要求）。
      (
        section: SettingsSection.publicQuery,
        title: geCardTitle(context, text: '公共查询', accent: fp(context).cardAccent),
        card: const SettingsPublicQueryCard(),
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
        card: const SettingsHomeWidgetCard(),
      ),
    ];
    final visible = [
      for (final b in blocks)
        if (sections.isEmpty || sections.contains(b.section)) b,
    ];
    return Scaffold(
      // ⚠ 用 `paneAppBar` 而不是裸 `AppBar`（2026-10-09 五轮）：侧栏视图下设置页是
      // **内嵌在右栏**显示的（`HomeDetailPane` 注入 `PaneScope(embedded: true)`），
      // 那时整条导航栏都不该画 —— 侧栏已高亮「设置」，再画一条就只有重复信息。
      // 整页模式（宫格视图的齿轮 / 首页标题栏的齿轮）照旧返回真 AppBar。
      appBar: paneAppBar(
        context,
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
              onTap: () => Navigator.of(sheetContext).pop(settingsClearSentinel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return; // 用户取消
    await ref
        .read(myCampusStoreProvider)
        .save(picked == settingsClearSentinel ? null : MyCampus.fromName(picked));
  }
}


