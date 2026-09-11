/// 阅读学分明细页（普通阅读 / 经典阅读 / 入馆教育 / 信息素养）。
///
/// 平台列名由服务端决定，各 kind 不同（阅读类=书名/完成时间/总阅读时长(秒)/
/// 所属厂商；入馆教育=闯关结束时间/是否通过；信息素养=视频数量/时长(秒)/
/// 完成时间），故按「列名 → 值」通用渲染，并跳过逐行重复的本人身份列。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

class ReadCreditDetailScreen extends ConsumerWidget {
  const ReadCreditDetailScreen({super.key, required this.kind});

  final ReadCreditKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(readCreditDetailProvider(kind));
    return Scaffold(
      appBar: AppBar(title: Text('${kind.label}明细'), centerTitle: true),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _message(
          context,
          icon: Icons.error_outline,
          title: '明细读取失败',
          body: '$error',
          onRetry: () => ref.invalidate(readCreditDetailProvider(kind)),
        ),
        data: (detail) {
          if (detail.isEmpty) {
            return _message(
              context,
              icon: Icons.inbox_outlined,
              title: '平台暂无明细记录',
              body: '该账号在「${kind.label}」下还没有可展示的明细。',
              onRetry: () => ref.invalidate(readCreditDetailProvider(kind)),
            );
          }
          return _detailBody(context, ref, detail);
        },
      ),
    );
  }

  Widget _detailBody(
    BuildContext context,
    WidgetRef ref,
    ReadCreditDetail detail,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final highlights = _highlights(detail);
    final identity = _identityOf(detail);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
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
            IconButton(
              tooltip: '刷新',
              onPressed: () => ref.invalidate(readCreditDetailProvider(kind)),
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
                    color: FeaturePalette.jhRead.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FeaturePalette.jhRead,
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
                color: FeaturePalette.jhRead,
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

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onRetry,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
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
    if (seconds > 0) out.add('累计阅读 ${_hoursText(seconds)}');
  }
  if (detail.indexOfHeader('视频数量') >= 0) {
    out.add('视频 ${detail.sumColumn('视频数量')} 个');
    final seconds = detail.sumColumn('时长');
    if (seconds > 0) out.add('累计学习 ${_hoursText(seconds)}');
  }
  if (detail.indexOfHeader('是否通过') >= 0) {
    final passed = detail.columnValues('是否通过').where((v) => v == '是').length;
    out.add('通过 $passed 次');
  }
  return out;
}

String _hoursText(int seconds) {
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
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: child,
  );
}
