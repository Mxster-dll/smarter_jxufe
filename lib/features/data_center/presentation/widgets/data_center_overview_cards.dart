/// 数据中台 · 本人数据卡
///
/// 「我的」这一组卡：子页面入口 / 学籍 / 周次 / 学业 / 指标 / 一卡通消费 / 教材 / 借阅 / 获奖 / 登录趋势。全部是 `(context, overview)` 的纯渲染件。
///
/// 拆分自 `data_center_screen.dart`（2026-10-08 架构审计第三轮）：
/// 原文件是一个 1389 行的 `ConsumerWidget`，49 个成员里没有一个碰状态，
/// 全部是 `(context, …)` 的纯渲染件 —— 因此**整组外提为顶层函数**，
/// 屏幕文件只留壳（口径见 AGENTS.md §33.4.4 ①②）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_sub_page_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_common.dart';

// ---- 子页面入口（学校「个人数据中心」下的九个页面） ----

/// 「个人数据中心 · 子页面」卡：学校那十个子页面的入口（除「基本信息」）。
///
/// 用户 2026-09-19 五轮原话：「我希望个人数据中心里加子页面 … 一共有十个这样的
/// 子页面，我希望你找到获取这十个子页面链接的方式，并把这十个子页面中除了
/// 『基本信息』整合到我的里面，其余九个子页面都做成 app 数据中心里的子页面」。
///
/// 清单**不在 App 里写死**：watch [dzjPageTreeProvider]（服务端
/// `manageTreeByVersion` 的页面树）→ [DzjPageTree.subPages] 已剔除首页与
/// 「基本信息」（后者并入「我的」页）。学校加页面，这里自动多一行。
Widget dcSubPageCard(BuildContext context, WidgetRef ref) {
  final async = ref.watch(dzjPageTreeProvider);
  final tree = async.valueOrNull;
  final pages = tree?.subPages ?? const <DzjPageNode>[];
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.account_tree_outlined,
            title: '个人数据中心',
            accent: AppColors.tone(context, Colors.teal[400]!),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pages.isNotEmpty)
                  Text(
                    '共 ${pages.length} 个子页面',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                if (async.hasError)
                  IconButton(
                    key: const Key('dzjSubPageTreeRetry'),
                    tooltip: '重新读取子页面清单',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => ref.invalidate(dzjPageTreeProvider),
                  ),
              ],
            ),
          ),
          if (pages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(
                async.hasError
                    ? '子页面清单读取失败：${friendlyErrorText(async.error!)}'
                    : (async.isLoading ? '正在读取子页面清单…' : '没有读到子页面'),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted(context),
                ),
              ),
            )
          else
            for (final p in pages)
              ListTile(
                key: Key('dzjSubPage-${p.pageKey}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  dzjSubPageIcon(p.title),
                  size: 20,
                  color: AppColors.tone(context, Colors.teal[400]!),
                ),
                title: Text(p.title, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  '学校「个人数据中心」子页面',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted(context),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DzjSubPageScreen(
                      pageKey: p.pageKey,
                      title: p.title,
                    ),
                  ),
                ),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 8, 4),
            child: Text(
              '「基本信息」已并入「我的」页；页面清单来自学校中台，改版后自动更新。',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- 学籍概要 ----

Widget dcStudentCard(BuildContext context, DataCenterOverview o) {
  final name = o.username.isEmpty ? '?' : o.username;
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.infoFill(context),
            child: Text(
              name.characters.first,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.info(context),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.username,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '校园卡号 ${o.userid}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                ),
                Text(
                  o.college,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
                ),
                if (o.advisorName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 13,
                        color: AppColors.textMuted(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '班主任 ${o.advisorName}${o.advisorPhone.isNotEmpty ? ' · ${o.advisorPhone}' : ''}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- 本周课程 ----

Widget dcWeekCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.event_note,
            title: o.weekTitle.isEmpty ? '本周课程' : o.weekTitle,
            accent: AppColors.info(context),
            trailing: o.weekDays.isNotEmpty
                ? Text(
                    '今日 ${o.todayClassCount} 节',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(context),
                    ),
                  )
                : null,
          ),
          if (o.weekDays.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '暂无课程安排',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: o.weekDays.map((d) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.infoFill(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.info(
                          context,
                        ).withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      d.weekday,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    ),
  );
}

// ---- 学业情况 ----

Widget dcAcademicCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          dcCardHeader(
            context,
            icon: Icons.menu_book,
            title: '学业情况',
            accent: AppColors.tone(context, Colors.deepPurple[500]!),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              dcScoreCell(
                context,
                label: '加权平均',
                value: dcFmt(o.weightedScore),
                unit: '分',
                color: AppColors.tone(context, Colors.deepPurple[600]!),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '平均绩点',
                value: dcFmt(o.gpa),
                unit: '',
                color: AppColors.tone(context, Colors.indigo[600]!),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '修读学分',
                value: dcFmt(o.semesterCredit),
                unit: '本学年',
                color: AppColors.tone(context, Colors.teal[600]!),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '已获学分',
                value: dcFmt(o.earnedCredit),
                unit: '初修',
                color: AppColors.caution(context),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---- 基础指标 ----

Widget dcMetricsCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          dcCardHeader(context, icon: Icons.speed, title: '基础指标'),
          const SizedBox(height: 10),
          Row(
            children: [
              dcScoreCell(
                context,
                label: '校园卡余额',
                value: dcFmt(o.cardBalance),
                unit: '元',
                color: AppColors.success(context),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '今日进出校门',
                value: dcFmt(o.gateToday),
                unit: '次',
                color: AppColors.info(context),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '今日登录门户',
                value: dcFmt(o.todayLoginCount),
                unit: '次',
                color: AppColors.caution(context),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '校园网余额',
                value: dcFmt(o.networkBalance),
                unit: '元',
                color: AppColors.tone(context, Colors.cyan[800]!),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---- 校园卡消费 ----

Widget dcCardSpendCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.credit_card,
            title: '校园卡消费',
            accent: AppColors.critical(context),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              dcScoreCell(
                context,
                label: '本年消费',
                value: dcFmt(o.spendYear),
                unit: '元',
                color: AppColors.critical(context),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '当月消费',
                value: dcFmt(o.spendMonth),
                unit: '元',
                color: AppColors.caution(context),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '本周消费',
                value: dcFmt(o.spendWeek),
                unit: '元',
                color: AppColors.caution(context),
              ),
            ],
          ),
          if (o.consumeRecords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '最近消费',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
            ),
            const SizedBox(height: 6),
            ...o.consumeRecords.take(5).map(
              (r) => dcConsumeTile(context, r),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget dcConsumeTile(BuildContext context, DzjConsumeRecord r) {
  return Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppColors.fillSoft(context),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.stroke(context)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.shopName, style: const TextStyle(fontSize: 12.5)),
              Text(
                r.time,
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '¥${dcFmt(r.amount)}',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppColors.critical(context),
          ),
        ),
      ],
    ),
  );
}

// ---- 教材 ----

Widget dcTextbookCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.menu_book_outlined,
            title: '本学期教材',
            accent: AppColors.tone(context, Colors.brown[600]!),
          ),
          const SizedBox(height: 10),
          // 两枚指标与「学业情况 / 基础指标 / 校园卡消费」同形制：**标题一行、
          // 指标一行**（从前它把标题与指标挤在同一行里，是这一页唯一的例外）。
          Row(
            children: [
              dcScoreCell(
                context,
                label: '教材费用',
                value: dcFmt(o.textbookFee),
                unit: '元',
                color: AppColors.tone(context, Colors.brown[600]!),
              ),
              dcScoreDivider(context),
              dcScoreCell(
                context,
                label: '教材数量',
                value: dcFmt(o.textbookCount),
                unit: '本',
                color: AppColors.tone(context, Colors.brown[700]!),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ---- 图书借阅 ----

Widget dcBorrowCard(BuildContext context, DataCenterOverview o) {
  const order = ['本周', '本月', '本年'];
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.local_library,
            title: '图书借阅',
            accent: AppColors.tone(context, Colors.teal[700]!),
          ),
          const SizedBox(height: 10),
          Row(
            children: order.map((label) {
              final count = o.borrowCounts[label] ?? 0;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      '$count 本',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: count > 0
                            ? AppColors.tone(context, Colors.teal[700]!)
                            : AppColors.textMuted(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}

// ---- 奖助贷勤 ----

Widget dcAwardCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.emoji_events_outlined,
            title: '奖助贷勤',
            accent: AppColors.caution(context),
          ),
          const SizedBox(height: 10),
          if (o.awards.isEmpty)
            Text(
              '暂无奖助贷勤记录',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            )
          else
            ...o.awards.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.arrow_right,
                      size: 15,
                      color: AppColors.textMuted(context),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        a,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// ---- 门户登录趋势 ----

Widget dcLoginTrendCard(BuildContext context, DataCenterOverview o) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.timeline,
            title: '门户登录趋势（本周）',
            accent: AppColors.tone(context, Colors.indigo[400]!),
          ),
          const SizedBox(height: 14),
          if (o.loginTrend.isEmpty)
            Text(
              '暂无登录数据',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: o.loginTrend.map((d) {
                final max = o.loginTrend.fold<int>(
                  1,
                  (m, x) => x.count > m ? x.count : m,
                );
                final height = 60.0 * (d.count / max);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Text(
                          '${d.count}',
                          style: TextStyle(
                            fontSize: 10,
                            color: d.count > 0
                                ? AppColors.tone(context, Colors.indigo[700]!)
                                : AppColors.textMuted(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: 60,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: height.clamp(2, 60),
                            decoration: BoxDecoration(
                              color: d.count > 0
                                  ? AppColors.tone(context, Colors.indigo[400]!)
                                  : AppColors.fillStrong(context),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.weekday.replaceAll('星期', '周'),
                          style: TextStyle(
                            fontSize: 9.5,
                            color: AppColors.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    ),
  );
}
