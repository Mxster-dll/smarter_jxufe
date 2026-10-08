/// 数据中台 · 同班 / 相关 / 扩展模块卡
///
/// 「别人」与「扩展」这两组：同班同学 / 相关维度 / 扩展模块行。与本人数据卡没有任何交叉引用。
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
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';
import 'package:smarter_jxufe/features/data_center/presentation/dzj_peer_sheet.dart';

// ---- 补充模块（本学期课程 / 图书馆座位预约 / 助学金与勤工助学）----

/// 每个模块一张卡。
///
/// 用户 2026-09-19 三轮原话「其他的，都显示在数据中心内」→ **三张卡恒定渲染**
/// （正在读取 / 读取失败 / 本期没有记录 / 条目），悄悄不画会让人以为没接上。
/// 数据来自按需 provider [dzjExtraProvider]（3 个请求，不进首屏）。
List<Widget> dcExtraCards(
  BuildContext context,
  WidgetRef ref,
  List<DzjExtraModule> modules,
) {
  final async = ref.watch(dzjExtraProvider);
  return [
    for (final m in modules)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: dcExtraCard(context, ref, m, async),
      ),
  ];
}

/// 一个补充模块卡上最多列几条（其余靠「共 N 条」交代）。
///
/// 原先挂在 `DataCenterScreen` 上（`static const int _extraRowsShown = 8`）：
/// 唯一用户就是本文件的 [dcExtraCard]，所以跟着代码走 —— §33.4.4 ② 说的
/// 「常量留在原类」只针对**测试有运行时引用或源码断言钉着**的那些，
/// 这一个两样都没有（已 grep 确认全仓零引用）。
const int dcExtraRowsShown = 8;

Widget dcExtraCard(
  BuildContext context,
  WidgetRef ref,
  DzjExtraModule module,
  AsyncValue<DzjExtraInfo> async,
) {
  final block = async.valueOrNull?.block(module);
  final accent = AppColors.tone(context, module.accent);
  final muted = TextStyle(fontSize: 12, color: AppColors.textMuted(context));

  final Widget body;
  if (block == null && async.isLoading) {
    body = Text('正在读取…', style: muted);
  } else if (block == null && async.hasError) {
    body = Text(
      '读取失败：${friendlyErrorText(async.error!)}',
      style: muted,
    );
  } else if (block == null || block.isEmpty) {
    body = Text(module.emptyText, style: muted);
  } else {
    final rows = block.items.take(dcExtraRowsShown).toList();
    body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final it in rows) dcExtraRow(context, it),
        if (block.total > rows.length)
          Text(
            '共 ${block.total} 条 · 只列最近 ${rows.length} 条',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted(context),
            ),
          ),
      ],
    );
  }

  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(module.icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (block != null && block.total > 0)
                Text(
                  '${block.total} 条',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted(context),
                  ),
                ),
              if (block == null && async.hasError)
                IconButton(
                  key: Key('dzjExtraRetry-${module.key}'),
                  tooltip: '重新读取',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 17),
                  onPressed: () => ref.invalidate(dzjExtraProvider),
                ),
            ],
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    ),
  );
}

/// 一条补充信息：左标签 + 右值 +（可选）下一行小字说明。
Widget dcExtraRow(BuildContext context, DzjInfoItem item) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            if (item.value.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                item.value,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        if (item.detail.isNotEmpty)
          Text(
            item.detail,
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted(context),
              height: 1.3,
            ),
          ),
      ],
    ),
  );
}

// ---- 校内关系 / 相关人员（点人数看名单）----

/// 「校内关系」卡（组件 `u:fcd2d17a9131`，5 维 + 派生 1 维）。
///
/// 五维人数来自 [dzjPeerCountsProvider]（**2026-10-01 从概览里拆出**：
/// 它们是五条 `count(distinct …)` 关联子查询，压在首屏就等于让"进页面
/// 先见人"看这五条查询的脸色）；派生那一维（「同年级同学院」）走
/// [dzjGradeCollegeCountProvider]。
///
/// 额外挂一枚 **「同年级同学院」**（用户 2026-09-20 立项）：它不在服务端五路里，
/// 是「同年级」行集按本人学院过滤出来的（[dzjCollegeFilterSql] 一次请求拿 total），
/// 排在同年级后面；取不到就整枚不画（不谎报 0 人）。
///
/// 四态与「相关人员」卡同口径：**没到 = 「正在读取…」、失败 = 说失败 +
/// 一枚重试**（从前失败会整块空白，用户看不出是没数据还是没取到）。
Widget dcPeerCard(BuildContext context, WidgetRef ref) {
  final async = ref.watch(dzjPeerCountsProvider);
  final counts = async.valueOrNull;
  final visible = DzjPeerDimension.relationDims
      .where((d) => (counts?[d.key] ?? -1) >= 0)
      .toList();
  final gradeCollege = ref.watch(dzjGradeCollegeCountProvider).valueOrNull;
  if (gradeCollege != null && gradeCollege > 0) {
    final at = visible.indexOf(DzjPeerDimension.grade);
    visible.insert(at < 0 ? 0 : at + 1, DzjPeerDimension.gradeCollege);
  }
  // 有哪一枚就画哪一枚：五维来自 `dzjPeerCountsProvider`，「同年级同学院」
  // 来自它自己那条过滤查询 —— 后者拿到了就该显示，哪怕五维那一份整体没取到。
  final String? emptyText;
  if (async.hasError) {
    emptyText = '读取失败：${friendlyErrorText(async.error!)}';
  } else if (visible.isEmpty) {
    emptyText = async.isLoading ? '正在读取…' : '暂无关系数据';
  } else {
    emptyText = null;
  }
  return dcRosterCard(
    context,
    icon: Icons.people_outline,
    accent: Colors.pink[400]!,
    title: '校内关系',
    visible: visible,
    countOf: (d) => d == DzjPeerDimension.gradeCollege
        ? (gradeCollege ?? 0)
        : (counts?[d.key] ?? 0),
    hint: '点人数可查看名单（含学号 / 班级 / 年级）',
    emptyText: emptyText,
    retryKey: const Key('dzjPeerRetry'),
    onRetry: () => ref.invalidate(dzjPeerCountsProvider),
  );
}

/// 「相关人员」卡（组件 `u:af43933a919c`，6 维）。
///
/// 用户 2026-09-19 二轮原话点名了学校第二个页面（`228583a5077f`）——
/// 「这两个部分的同学名单我都要，但是后者可以查看学号班级和年级，前者只能看姓名学院」
/// → 与「校内关系」并列的第二张名单卡；这六个维度**只有姓名 / 性别 / 校园卡号 / 学院**，
/// 所以名单行里不会有班级年级（那是服务端本来就没给的列）。
///
/// 人数单独按需取（[dzjRelatedCountsProvider]）：首屏 19 个请求已经够重，
/// 这张卡先画「正在读取…」，到了再填数；失败给「重试」，不谎报 0 人。
Widget dcRelatedCard(BuildContext context, WidgetRef ref) {
  final async = ref.watch(dzjRelatedCountsProvider);
  final counts = async.valueOrNull;
  final visible = DzjPeerDimension.relatedDims
      .where((d) => (counts?[d.key] ?? -1) >= 0)
      .toList();
  final String? emptyText;
  if (async.hasError) {
    emptyText = '读取失败：${friendlyErrorText(async.error!)}';
  } else if (visible.isEmpty) {
    emptyText = async.isLoading ? '正在读取…' : '暂无相关人员数据';
  } else {
    emptyText = null;
  }
  return dcRosterCard(
    context,
    icon: Icons.hub_outlined,
    accent: Colors.indigo[400]!,
    title: '相关人员',
    visible: visible,
    countOf: (d) => counts?[d.key] ?? 0,
    hint: '点人数可查看名单（该名单只有姓名 / 学院）',
    emptyText: emptyText,
    retryKey: const Key('dzjRelatedRetry'),
    onRetry: () => ref.invalidate(dzjRelatedCountsProvider),
  );
}

/// 名单卡外壳：标题 + 人数胶囊（可点）+ 脚注。
///
/// 两张名单卡（校内关系 / 相关人员）只有**来源组件与配色**不同，壳子共用一份
/// —— 免得胶囊的圆角、点击区、key 规则在两边各写一遍后慢慢分叉。
Widget dcRosterCard(
  BuildContext context, {
  required IconData icon,
  required Color accent,
  required String title,
  required List<DzjPeerDimension> visible,
  required int Function(DzjPeerDimension) countOf,
  required String hint,
  required String? emptyText,
  Key? retryKey,
  VoidCallback? onRetry,
}) {
  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.tone(context, accent)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (onRetry != null)
                IconButton(
                  // 两张名单卡各给各的 key（同页两个「重新读取」按钮不能撞 key）。
                  key: retryKey,
                  tooltip: '重新读取',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 17),
                  onPressed: onRetry,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (emptyText != null)
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted(context),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in visible)
                  dcPeerPill(
                    context,
                    dimension: d,
                    value: countOf(d),
                    accent: accent,
                  ),
              ],
            ),
          if (emptyText == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                hint,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 人数胶囊：`3 人 / 舍友`，整格可点 → 该维度的名单弹层。
Widget dcPeerPill(
  BuildContext context, {
  required DzjPeerDimension dimension,
  required int value,
  required Color accent,
}) {
  final tone = AppColors.tone(context, accent);
  return InkWell(
    key: Key('dzjPeer-${dimension.key}'),
    borderRadius: BorderRadius.circular(10),
    onTap: () =>
        showDzjPeerSheet(context, dimension: dimension, count: value),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.statusFill(context, tone),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value 人',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: value > 0 ? tone : AppColors.textMuted(context),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            dimension.label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted(context),
            ),
          ),
        ],
      ),
    ),
  );
}
