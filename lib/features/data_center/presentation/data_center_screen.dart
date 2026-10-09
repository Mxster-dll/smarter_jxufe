import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_common.dart';
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_overview_cards.dart';
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_social_cards.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/design/settings_section.dart';

/// 学生个人数据中心（dzj.jxufe.edu.cn）原生聚合页。
///
/// 与网页「个人首页」等价的全量概览：
/// 学籍概要 / 班主任 / 本周课程 / 学业（成绩·绩点·学分）/
/// 基础指标 / 校园卡消费与明细 / 奖助贷勤 / 教材 / 图书借阅 / 门户登录趋势。
class DataCenterScreen extends ConsumerWidget {
  const DataCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(dataCenterOverviewProvider);
    final overview = overviewAsync.valueOrNull;
    // 概览那几张卡：数据到了就画；还没到画骨架（**不画假 0**、也不悄悄不画）；
    // 失败则由顶部那一张错误卡统一交代（9 张卡各画一个错误块只是噪音）。
    final failed = overviewAsync.hasError;

    Widget slot(
      String title,
      IconData icon,
      Widget Function(DataCenterOverview o) build, {
      bool lead = false,
    }) {
      if (overview != null) return build(overview);
      if (failed) return const SizedBox.shrink();
      return dcSkeletonCard(context, title: title, icon: icon, lead: lead);
    }

    return Scaffold(
      appBar: paneAppBar(
        context,
        // 内嵌进主页右侧面板时（该面板路由栈的首页）整条导航栏都不画，见 §17.7 / §19。
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('学生个人数据中心'),
        // 本页数据（校园网余额等）依赖平台标识（GUID）。
        settingsSections: const [SettingsSection.platformGuid],
        centerTitle: true,
      ),
      // ⚠ 2026-10-01：整页**不再被一个 Future 挡住**。
      // 从前这里是 `overviewAsync.when(loading: …)`，于是「子页面清单 / 补充模块 /
      // 校内关系 / 相关人员」这四组请求要等概览那一批（19 个并发 + 冷连接实测
      // 6.5 秒）回来之后才开始发 —— 用户看到的就是一个转了很久的空页，而转圈
      // 期间真正在等什么完全不可见。现在页面一开就画：只依赖自己 provider 的卡
      // 立刻取数并渲染，等概览的卡各自画骨架。
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (failed) ...[
            dcOverviewErrorCard(context, ref, overviewAsync.error!),
            const SizedBox(height: 12),
          ],
          slot(
            '学籍概要',
            Icons.badge_outlined,
            (o) => dcStudentCard(context, o),
            lead: true,
          ),
          const SizedBox(height: 12),
          dcSubPageCard(context, ref),
          const SizedBox(height: 12),
          slot('本周课程', Icons.event_note, (o) => dcWeekCard(context, o)),
          const SizedBox(height: 12),
          slot(
            '学业情况',
            Icons.menu_book,
            (o) => dcAcademicCard(context, o),
          ),
          const SizedBox(height: 12),
          ...dcExtraCards(context, ref, const [DzjExtraModule.courses]),
          // 「校内关系」与「相关人员」已合成一张两组卡（用户 2026-10-09：
          // 「整合…并增强显示」）—— 两组各自取数、各自四态，见 data_center_social_cards.dart。
          dcRelationCard(context, ref),
          const SizedBox(height: 12),
          slot('基础指标', Icons.speed, (o) => dcMetricsCard(context, o)),
          const SizedBox(height: 12),
          slot(
            '校园卡消费',
            Icons.credit_card,
            (o) => dcCardSpendCard(context, o),
          ),
          const SizedBox(height: 12),
          slot(
            '本学期教材',
            Icons.menu_book_outlined,
            (o) => dcTextbookCard(context, o),
          ),
          const SizedBox(height: 12),
          slot(
            '图书借阅',
            Icons.local_library,
            (o) => dcBorrowCard(context, o),
          ),
          const SizedBox(height: 12),
          ...dcExtraCards(context, ref, const [DzjExtraModule.seat]),
          slot(
            '奖助贷勤',
            Icons.emoji_events_outlined,
            (o) => dcAwardCard(context, o),
          ),
          const SizedBox(height: 12),
          ...dcExtraCards(context, ref, const [DzjExtraModule.aid]),
          slot(
            '登录趋势',
            Icons.timeline,
            (o) => dcLoginTrendCard(context, o),
          ),
        ],
      ),
    );
  }
}
