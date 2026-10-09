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
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_common.dart';

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
          dcCardHeader(
            context,
            icon: module.icon,
            title: module.title,
            accent: accent,
            trailing: block != null && block.total > 0
                ? Text(
                    '${block.total} 条',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(context),
                    ),
                  )
                : (block == null && async.hasError
                      ? IconButton(
                          key: Key('dzjExtraRetry-${module.key}'),
                          tooltip: '重新读取',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh, size: 17),
                          onPressed: () => ref.invalidate(dzjExtraProvider),
                        )
                      : null),
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

// ---- 校内关系（融合后的 8 目 · 一张卡 · 点人数看名单）----

/// 名单卡里一枚关系方格的**固定宽度**。
///
/// 固定宽是为了让占比条彼此可比 —— 宽度随文字长短变的话，条长就不再是比例了。
/// 108 ≈ 一行放得下 6 个字的目名（「同年级同专业」），390 宽的手机一行三枚。
const double dcPeerTileWidth = 108;

/// 「校内关系」卡：**一份网格 8 目**（融合了从前的「校内关系」与「相关人员」两张卡）。
///
/// 用户 2026-10-09 原话：「这两个功能本身就很极高的相似度，那不如直接融合为一个功能。
/// 所有的卡片统一样式，然后重复的卡片不重复显示，可以归并的信息就归并显示」
/// → 一个关系只出现一次（[DzjPeerRelation]）：人数取主口径（行里带学号 / 班级 / 年级），
/// 主口径没取到才回落到另一份；点开弹层可切换另一份口径，两套系统的名单差一眼可见。
///
/// 四态（一张卡只有一份，判据看**两份**取数）：
/// - 有目可铺 → 网格；某一份失败时**脚注如实说「那一份没取到」**（不静默）；
/// - 没有目可铺且失败 → 「读取失败：…」；
/// - 还有一份在飞 → 「正在读取…」；两份都到、一个目都没有 → 「暂无关系数据」。
///
/// 卡头那枚「重新读取」把**三路**一起重取（两份人数 + 派生的「同年级同学院」）。
Widget dcRelationCard(BuildContext context, WidgetRef ref) {
  final peerAsync = ref.watch(dzjPeerCountsProvider);
  final relatedAsync = ref.watch(dzjRelatedCountsProvider);
  final gradeCollege = ref.watch(dzjGradeCollegeCountProvider).valueOrNull;

  final relationCounts = peerAsync.valueOrNull;
  final entries = DzjPeerEntry.build(
    relationCounts: relationCounts,
    relatedCounts: relatedAsync.valueOrNull,
    gradeCollege: gradeCollege,
  );
  final gradeCount = relationCounts?[DzjPeerDimension.grade.key];
  final failureNotes = <String>[
    if (peerAsync.hasError)
      '「校内关系」那一份没取到：${friendlyErrorText(peerAsync.error!)}',
    if (relatedAsync.hasError)
      '「相关人员」那一份没取到：${friendlyErrorText(relatedAsync.error!)}',
  ];

  // 合并名单（同班 / 舍友）自己那一份失败时：方格回落成主口径人数，这里如实交代。
  // ⚠ 这里 watch 的是与方格**同一个** provider（同一份缓存，不会多发请求）。
  final mergeNotes = <String>[];
  for (final e in entries) {
    if (!e.relation.merges) continue;
    final merged = ref.watch(dzjPeerMergedProvider(e.relation));
    if (merged.hasError) {
      mergeNotes.add(
        '「${e.relation.label}」的合并名单没取到：'
        '${friendlyErrorText(merged.error!)}'
        '（方格显示的是「校内关系」那一份的人数）',
      );
    }
  }

  final muted = TextStyle(fontSize: 11, color: AppColors.textMuted(context));
  final Widget body;
  if (entries.isNotEmpty) {
    final hasBar = entries.any(
      (e) =>
          dzjPeerGradeRatio(
            e.dimension,
            count: e.count,
            gradeCount: gradeCount,
          ) !=
          null,
    );
    body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in entries)
              dcPeerTile(context, ref, entry: e, gradeCount: gradeCount),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 画得出条就意味着分母拿到了（[dzjPeerGradeRatio] 的判据）→ 直接印，
              // 不写「分母未知」那种会被误读成 0 人的话。
              Text(
                [
                  '点人数可查看名单',
                  // 同义的两对是**合并**显示的（不是二选一），脚注交代一句。
                  if (entries.any((e) => e.relation.merges))
                    '同班 / 舍友 = 两份名单已合并去重（人数为合并后）',
                  if (hasBar) '占比条 = 占同年级 $gradeCount 人',
                ].join(' · '),
                style: muted,
              ),
              for (final note in [...failureNotes, ...mergeNotes])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(note, style: muted),
                ),
            ],
          ),
        ),
      ],
    );
  } else {
    body = Text(
      dcPeerStateText(
        errorText: peerAsync.hasError
            ? friendlyErrorText(peerAsync.error!)
            : (relatedAsync.hasError
                  ? friendlyErrorText(relatedAsync.error!)
                  : null),
        loading: peerAsync.isLoading || relatedAsync.isLoading,
        emptyLabel: '暂无关系数据',
      ),
      style: TextStyle(fontSize: 12, color: AppColors.textMuted(context)),
    );
  }

  return Card(
    shape: appCardShape(context),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dcCardHeader(
            context,
            icon: Icons.people_outline,
            title: '校内关系',
            accent: AppColors.tone(context, Colors.pink[400]!),
            trailing: IconButton(
              // 融合后只剩这一枚「重新读取」：它把两份人数一起重取。
              key: const Key('dzjPeerRetry'),
              tooltip: '重新读取',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 17),
              onPressed: () {
                ref.invalidate(dzjPeerCountsProvider);
                ref.invalidate(dzjRelatedCountsProvider);
                ref.invalidate(dzjGradeCollegeCountProvider);
              },
            ),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    ),
  );
}

/// 没有目可铺时的四态文案（一张卡只有一份，所以判据看**两份**取数）。
///
/// 顺序是刻意的：**失败优先于「正在读取」**（一份死了、另一份还在飞 —— 先说失败，
/// 等另一份到了自然会变成网格，失败原因转由脚注继续交代，不静默）。
String dcPeerStateText({
  required String? errorText,
  required bool loading,
  required String emptyLabel,
}) {
  if (errorText != null) return '读取失败：$errorText';
  if (loading) return '正在读取…';
  return emptyLabel;
}

/// 一个关系目的的方格：`45 人` + 目名 +（可选）占比条。
///
/// 整格可点 → 该关系的名单弹层（[showDzjPeerSheet]）。
///
/// **同义的两对（同班 / 舍友）显示的是两份名单合并去重后的真实人数**
/// （用户 2026-10-09：「做成信息归并式的」+ 拍板「方格预取并显示合并后的真实人数」）：
/// 数据来自 [dzjPeerMergedProvider] —— 那两份进页面就取，与弹层用的是**同一份缓存**，
/// 所以方格上的数与点开的名单永远一致，且弹层秒开。合并还没到就画「… 人」
/// （**不拿主口径的数冒充**）；万一合并那一份失败，回落主口径人数并由卡片脚注交代。
Widget dcPeerTile(
  BuildContext context,
  WidgetRef ref, {
  required DzjPeerEntry entry,
  int? gradeCount,
}) {
  final relation = entry.relation;
  final tone = AppColors.tone(context, Colors.pink[400]!);
  final muted = AppColors.textMuted(context);

  final mergedAsync = relation.merges
      ? ref.watch(dzjPeerMergedProvider(relation))
      : null;
  final mergedCount = mergedAsync?.valueOrNull?.count;
  final value = relation.merges
      ? (mergedCount ?? (mergedAsync!.hasError ? entry.count : null))
      : entry.count;

  final ratio = dzjPeerGradeRatio(
    entry.dimension,
    count: value ?? 0,
    gradeCount: gradeCount,
  );
  return InkWell(
    key: Key('dzjPeer-${relation.key}'),
    borderRadius: BorderRadius.circular(10),
    onTap: () => showDzjPeerSheet(
      context,
      dimension: entry.dimension,
      count: value,
    ),
    child: Container(
      width: dcPeerTileWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.statusFill(context, tone),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ellipsis：人数可能四位数（如「7716 人」），大字号 / 无障碍放大时也要能缩，
          // 不能把方格撑破。
          Text(
            value == null ? '… 人' : '$value 人',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: (value ?? 0) > 0 ? tone : muted,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            relation.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: muted),
          ),
          if (ratio != null) ...[
            const SizedBox(height: 6),
            dcPeerRatioBar(
              context,
              ratio: ratio,
              color: tone,
              barKey: Key('dzjPeerBar-${relation.key}'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// 占比条：底槽 + 按比例的填充。
///
/// 长度只在自己这一行内横比（同一组里每枚方格都是 [dcPeerTileWidth] 宽），
/// 分母与「只对哪几维画」的口径在 [dzjPeerGradeRatio] 里，别在这里另判一次。
Widget dcPeerRatioBar(
  BuildContext context, {
  required double ratio,
  required Color color,
  Key? barKey,
}) {
  return SizedBox(
    key: barKey,
    height: 3,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: ColoredBox(
        color: AppColors.stroke(context),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: ratio.clamp(0.0, 1.0),
            heightFactor: 1,
            child: ColoredBox(color: color.withValues(alpha: 0.55)),
          ),
        ),
      ),
    ),
  );
}
