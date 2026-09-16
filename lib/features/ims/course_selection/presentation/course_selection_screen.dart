/// 教务「选课」主页面 —— 网上选课 / 选课结果两个 Tab（入口在首页宫格）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
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
      appBar: AppBar(
        title: const Text('选课'),
        actions: [
          PopupMenuButton<_SelectionMore>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              final route = switch (value) {
                _SelectionMore.timetable => SelectionTimetableScreen(
                  channel: _channel,
                ),
                _SelectionMore.expand => SelectionExpandScreen(
                  channel: _channel,
                ),
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
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: FeaturePalette.cardAccent,
          labelColor: FeaturePalette.cardAccent,
          tabs: const [
            Tab(text: '网上选课'),
            Tab(text: '选课结果'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          SelectionOnlineView(
            channel: _channel,
            onChannelChanged: (value) => setState(() => _channel = value),
          ),
          const SelectionResultView(),
        ],
      ),
      backgroundColor: scheme.surface,
    );
  }
}

enum _SelectionMore { timetable, expand, cancelled }
