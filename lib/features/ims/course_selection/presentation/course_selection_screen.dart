/// 教务「选课」主页面 —— 网上选课 / 选课结果两个 Tab（入口在首页宫格）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/selection_extra_screens.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/selection_online_view.dart';
import 'package:smarter_jxufe/features/ims/course_selection/presentation/selection_result_view.dart';

class CourseSelectionScreen extends ConsumerStatefulWidget {
  const CourseSelectionScreen({super.key});

  @override
  ConsumerState<CourseSelectionScreen> createState() =>
      _CourseSelectionScreenState();
}

class _CourseSelectionScreenState extends ConsumerState<CourseSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  SelectionChannel _channel = SelectionChannel.plan;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // 原导航栏里的三样东西：标题（侧栏已高亮当前服务，不再重复）、「更多」菜单、
      // 两个页签。侧栏内嵌模式（面板首路由）整条导航栏不画 —— `paneAppBar` 返回
      // null，页签与「更多」一起下沉到内容首行（用户 2026-09-16 裁定，见 §19）。
      appBar: paneAppBar(
        context,
        title: const Text('选课'),
        actions: [_moreAction(context)],
        bottom: _buildTabs(context),
        settingsSections: const [SettingsSection.imsSession],
      ),
      body: Column(
        children: [
          PaneActionRow(
            actions: [_moreAction(context)],
            leading: _buildTabs(context),
            height: kTextTabBarHeight,
            padding: EdgeInsets.zero,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                SelectionOnlineView(
                  channel: _channel,
                  onChannelChanged: (value) => setState(() => _channel = value),
                ),
                const SelectionResultView(),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: scheme.surface,
    );
  }

  /// 两个页签（整页模式是 `AppBar.bottom`，内嵌模式下沉到内容首行）。
  TabBar _buildTabs(BuildContext context) => TabBar(
    controller: _tabs,
    indicatorColor: fp(context).cardAccent,
    labelColor: fp(context).cardAccent,
    tabs: const [
      Tab(text: '网上选课'),
      Tab(text: '选课结果'),
    ],
  );

  /// 原导航栏的「更多」菜单（查询课表 / 申请扩容 / 被取消课程）。
  Widget _moreAction(BuildContext context) => PopupMenuButton<_SelectionMore>(
    tooltip: '更多',
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      final route = switch (value) {
        _SelectionMore.timetable => SelectionTimetableScreen(channel: _channel),
        _SelectionMore.expand => SelectionExpandScreen(channel: _channel),
        _SelectionMore.cancelled => const SelectionCancelledScreen(),
      };
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => route));
    },
    itemBuilder: (context) => const [
      PopupMenuItem(
        value: _SelectionMore.timetable,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.table_chart_outlined),
          title: Text('查询课表'),
        ),
      ),
      PopupMenuItem(
        value: _SelectionMore.expand,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.unfold_more_outlined),
          title: Text('申请扩容'),
        ),
      ),
      PopupMenuItem(
        value: _SelectionMore.cancelled,
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.block_outlined),
          title: Text('被取消课程'),
        ),
      ),
    ],
  );
}

enum _SelectionMore { timetable, expand, cancelled }
