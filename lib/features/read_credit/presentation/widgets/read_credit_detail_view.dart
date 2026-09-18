/// 阅读学分明细的通用渲染件（学分平台侧的个人明细表）。
///
/// 平台列名由服务端决定，各 kind 不同（阅读类=书名/完成时间/总阅读时长(秒)/
/// 所属厂商；入馆教育=闯关结束时间/是否通过；信息素养=视频数量/时长(秒)/
/// 完成时间），故按「列名 → 值」通用渲染，并跳过逐行重复的本人身份列。
///
/// 两处共用（用户 2026-09-15 裁定：「取消畅想之星的独立入口…原页面所对应的
/// 数据源不删除，而是把信息归并到畅想之星功能内」）：
/// - `ReadCreditDetailScreen`（普通阅读 / 入馆教育 / 信息素养）；
/// - `CxstarScreen` 的「学分平台 · 经典阅读明细」节（经典阅读不再从蛟湖阅读
///   进入原明细页，数据改为在畅想之星页内展示）。
///
/// ⚠ 输出的是 **Column（自身不滚动）**，调用方负责放进自己的滚动容器
/// （`ListView` / `SingleChildScrollView`）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

class ReadCreditDetailView extends StatelessWidget {
  const ReadCreditDetailView({super.key, required this.detail, this.onRefresh});

  final ReadCreditDetail detail;

  /// 刷新回调；为 null 时不显示刷新按钮。
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlights = _highlights(detail);
    final identity = _identityOf(detail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '共 ${detail.rows.length} 条记录',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: '刷新',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final text in highlights)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tint(
                      context,
                      fp(context).cardAccent,
                      0.10,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fp(context).cardAccent,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (identity.isNotEmpty) ...[
          const SizedBox(height: 12),
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in identity)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 58,
                          child: Text(
                            entry.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final row in detail.rows) ...[
          _rowCard(context, detail, row),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _rowCard(
    BuildContext context,
    ReadCreditDetail detail,
    List<String> row,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final titleIndex = _titleIndex(detail, row);
    final entries = <({String label, String value})>[];
    for (var i = 0; i < detail.headers.length && i < row.length; i++) {
      if (i == titleIndex) continue;
      final header = detail.headers[i];
      if (kReadCreditIdentityHeaders.contains(header)) continue;
      final value = row[i].trim();
      if (value.isEmpty) continue;
      entries.add((label: header, value: readCreditCellText(header, value)));
    }
    final title = titleIndex >= 0 ? row[titleIndex].trim() : '记录';
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bookmark_outline,
                size: 16,
                color: fp(context).cardAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? '记录' : title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        entry.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 明细行标题列：优先「书名」，其次「所属厂商」，最后取首个非空非身份列。
int _titleIndex(ReadCreditDetail detail, List<String> row) {
  for (final keyword in ['书名', '所属厂商', '厂商']) {
    final i = detail.indexOfHeader(keyword);
    if (i >= 0 && i < row.length && row[i].trim().isNotEmpty) return i;
  }
  for (var i = 0; i < detail.headers.length && i < row.length; i++) {
    if (kReadCreditIdentityHeaders.contains(detail.headers[i])) continue;
    if (row[i].trim().isNotEmpty) return i;
  }
  return -1;
}

/// 本人身份信息（各行重复，只在页首展示一次）。
List<({String label, String value})> _identityOf(ReadCreditDetail detail) {
  if (detail.rows.isEmpty) return const [];
  final first = detail.rows.first;
  final out = <({String label, String value})>[];
  for (var i = 0; i < detail.headers.length && i < first.length; i++) {
    if (!kReadCreditIdentityHeaders.contains(detail.headers[i])) continue;
    final value = first[i].trim();
    if (value.isEmpty) continue;
    out.add((label: detail.headers[i], value: value));
  }
  return out;
}

/// 页首统计（册数 / 累计时长 / 视频数 / 通过次数）。
List<String> _highlights(ReadCreditDetail detail) {
  final out = <String>[];
  if (detail.indexOfHeader('书名') >= 0) {
    final books = detail.columnValues('书名').where((v) => v.isNotEmpty).length;
    out.add('已读 $books 册');
    final seconds = detail.sumColumn('时长');
    if (seconds > 0) out.add('累计阅读 ${readCreditHoursText(seconds)}');
  }
  if (detail.indexOfHeader('视频数量') >= 0) {
    out.add('视频 ${detail.sumColumn('视频数量')} 个');
    final seconds = detail.sumColumn('时长');
    if (seconds > 0) out.add('累计学习 ${readCreditHoursText(seconds)}');
  }
  if (detail.indexOfHeader('是否通过') >= 0) {
    final passed = detail.columnValues('是否通过').where((v) => v == '是').length;
    out.add('通过 $passed 次');
  }
  return out;
}

/// 秒 → 「N 小时」（≥10 小时取整，否则一位小数）。
String readCreditHoursText(int seconds) {
  final hours = seconds / 3600;
  return hours >= 10
      ? '${hours.toStringAsFixed(0)} 小时'
      : '${hours.toStringAsFixed(1)} 小时';
}

Widget _card(BuildContext context, {required Widget child}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.hairline(context, 0.6)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: child,
  );
}
