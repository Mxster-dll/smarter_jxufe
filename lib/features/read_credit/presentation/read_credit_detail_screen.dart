/// 阅读学分明细页（普通阅读 / 入馆教育 / 信息素养）。
///
/// ⚠ 经典阅读**不再从这里进入**（用户 2026-09-15 裁定：「取消畅想之星的独立
/// 入口…删除目前点击蛟湖阅读-经典阅读的界面，而是把点击后跳转的页面改成畅想
/// 之星」）；学分平台侧的经典阅读明细已归并进 `CxstarScreen` 页内展示（同一
/// 渲染件 [ReadCreditDetailView]）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/widgets/read_credit_detail_view.dart';

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              ReadCreditDetailView(
                detail: detail,
                onRefresh: () => ref.invalidate(readCreditDetailProvider(kind)),
              ),
            ],
          );
        },
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
