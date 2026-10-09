import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_body.dart';
import 'package:smarter_jxufe/features/data_center/presentation/widgets/data_center_common.dart';
import 'package:smarter_jxufe/design/settings_section.dart';

/// 数据中台子页面图标（按标题给一个，认不出用通用图标）。
IconData dzjSubPageIcon(String title) {
  if (title.contains('关联同学') || title.contains('同学')) return Icons.groups_outlined;
  if (title.contains('教师')) return Icons.school_outlined;
  if (title.contains('学业') || title.contains('成绩')) return Icons.menu_book_outlined;
  if (title.contains('奖助') || title.contains('贷')) return Icons.card_giftcard_outlined;
  // ⚠ 「数字活动」也含「活动」二字 —— 数字/上网/门禁要排在「活动」之前判，
  // 否则它会和「校内活动」撞成同一个图标。
  if (title.contains('数字') || title.contains('上网') || title.contains('门禁')) {
    return Icons.sensors_outlined;
  }
  if (title.contains('活动') || title.contains('竞赛')) return Icons.emoji_events_outlined;
  if (title.contains('住宿') || title.contains('宿舍')) return Icons.bed_outlined;
  if (title.contains('消费') || title.contains('一卡通')) return Icons.receipt_long_outlined;
  if (title.contains('图书') || title.contains('借阅')) return Icons.local_library_outlined;
  if (title.contains('基本')) return Icons.badge_outlined;
  return Icons.dashboard_customize_outlined;
}

/// 一行明细最多铺几条（超出给「还有 N 条」）。
///
/// 用户 2026-09-20 七轮：「就只能看到参加几次，看不到每次参加的内容」—— 明细要真的铺开，
/// 20 条太紧（选课 37 条 / 任课教师 37 条 / 消费明细上百条都被截在 20）。改 50，
/// 与中台单次取数上限（pageSize 60）同一档。
const int dzjBlockRowLimit = 50;

/// 一个「数据中台子页面」（如 关联同学 / 指导教师 / 学业信息 …）。
///
/// 页面内容**不硬编码**：进页面时拉该页的 amis 定义
/// （`searchBodyByVersion`）→ [DzjPageBody.parse] 解析出数据块 → 逐块取数
/// （聚合 `data/get` / 明细 `data/list`）→ 通用渲染。
/// 因此学校改页面、加卡片，App 不用改代码。
class DzjSubPageScreen extends ConsumerStatefulWidget {
  const DzjSubPageScreen({super.key, required this.pageKey, required this.title});

  final String pageKey;
  final String title;

  @override
  ConsumerState<DzjSubPageScreen> createState() => _DzjSubPageScreenState();
}

class _DzjSubPageScreenState extends ConsumerState<DzjSubPageScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dzjSubPageProvider(widget.pageKey));

    return Scaffold(
      appBar: paneAppBar(
        context,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(widget.title),
        settingsSections: const [SettingsSection.platformGuid],
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '刷新数据',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(dzjSubPageProvider(widget.pageKey)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在读取该页数据…'),
            ],
          ),
        ),
        error: (error, _) => AppErrorState(
          title: '加载失败',
          error: error,
          retryKey: const Key('dzjSubRetry'),
          onRetry: () => ref.invalidate(dzjSubPageProvider(widget.pageKey)),
        ),
        data: (data) => _buildContent(context, data),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DzjSubPageData data) {
    final shown = data.shown;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
            '数据来源：学校「个人数据中心 › ${data.title}」'
            '${shown.isEmpty ? '' : ' · ${data.valueCount} 项指标 / ${data.tableCount} 张明细'}'
            '${data.truncated > 0 ? ' · 另有 ${data.truncated} 个模块未展开' : ''}',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted(context)),
          ),
        ),
        if (shown.isEmpty) _emptyCard(context, data),
        for (final b in shown) ...[
          _blockCard(context, b),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _emptyCard(BuildContext context, DzjSubPageData data) {
    final text = data.blocks.isEmpty
        ? '这一页暂时没有可展示的数据'
        : '这一页的模块学校侧暂无数据';
    return Card(
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted(context)),
            ),
            const SizedBox(height: 6),
            Text(
              '共识别 ${data.blocks.length} 个模块（跳过 ${data.skipped} 个排版 / 占位组件）',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// 一个数据块的卡片：聚合值走「标签 + 值」，明细走「行列表」。
  Widget _blockCard(BuildContext context, DzjBlockData b) {
    final accent = Theme.of(context).colorScheme.primary;
    // 名单类组件同一个 id 下有多路（`slot`）—— key 必须带上路号，否则六张卡撞 key。
    final keySuffix = b.block.slot >= 0 ? '#${b.block.slot}' : '';
    return Card(
      key: Key('dzjBlock-${b.block.id}$keySuffix'),
      shape: appCardShape(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            dcCardHeader(
              context,
              icon: b.rows.isEmpty
                  ? Icons.insights_outlined
                  : Icons.table_rows_outlined,
              title: b.block.title.isEmpty ? '数据' : b.block.title,
              accent: AppColors.tone(context, accent),
              trailing: b.rows.isNotEmpty
                  ? Text(
                      '${b.rows.length} 条',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted(context),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            if (b.fields.isNotEmpty) _fields(context, b),
            if (b.rows.isNotEmpty) _rows(context, b),
          ],
        ),
      ),
    );
  }

  /// 聚合值：单字段给一行大号值（卡片标题就是它的名字），多字段给标签/值列表。
  Widget _fields(BuildContext context, DzjBlockData b) {
    final single = b.fields.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in b.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: single ? null : 108,
                  child: single
                      ? null
                      : Text(
                          f.key,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted(context),
                          ),
                        ),
                ),
                if (!single) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.value,
                    style: TextStyle(
                      fontSize: single ? 20 : 13,
                      fontWeight: single ? FontWeight.w700 : FontWeight.w500,
                      color: single ? AppColors.tone(context, Theme.of(context).colorScheme.primary) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 明细：每行 = 序号 + 首列（加粗）+ 其余列拼一行小字。
  Widget _rows(BuildContext context, DzjBlockData b) {
    final rows = b.rows.take(dzjBlockRowLimit).toList();
    final more = b.rows.length - rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) Divider(height: 14, color: AppColors.hairline(context)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.first.value,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (row.length > 1) ...[
                      const SizedBox(height: 3),
                      Text(
                        row.skip(1).map((e) => '${e.key} ${e.value}').join(' · '),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
        if (more > 0) ...[
          const SizedBox(height: 8),
          Text(
            '共 ${b.rows.length} 条，此处列出前 $dzjBlockRowLimit 条',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted(context)),
          ),
        ],
      ],
    );
  }
}
