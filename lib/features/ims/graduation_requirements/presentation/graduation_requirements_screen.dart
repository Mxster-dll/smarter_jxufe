import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/graduation_requirements_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

/// 毕业学分要求数据 Provider。
final graduationRequirementsProvider =
    FutureProvider<List<GraduationRequirement>>((ref) async {
      final repo = await ref.watch(
        graduationRequirementsRepositoryProvider.future,
      );
      final result = await repo.getGraduationRequirements();
      return result.fold(
        (failure) => throw Exception(failure.message ?? '获取毕业学分要求失败'),
        (requirements) => requirements,
      );
    });

/// 毕业学分要求页面。
class GraduationRequirementsScreen extends ConsumerWidget {
  final bool showAppBar;

  const GraduationRequirementsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRequirements = ref.watch(graduationRequirementsProvider);
    final theme = Theme.of(context);

    final body = asyncRequirements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$e', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(graduationRequirementsProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (requirements) {
        if (requirements.isEmpty) {
          return const Center(child: Text('暂无数据'));
        }

        // 分离合计行和普通行
        final items = requirements.where((r) => !r.isTotal).toList();
        final total = requirements.where((r) => r.isTotal).toList();

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 表头
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 40,
                      child: Text(
                        '序号',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        '项目',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 80,
                      child: Text(
                        '学分',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 数据行
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                      right: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: items.length + total.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                    itemBuilder: (context, index) {
                      if (index < items.length) {
                        return _buildRow(context, items[index], theme);
                      } else {
                        final t = total[index - items.length];
                        return _buildTotalRow(context, t, theme);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('毕业学分要求'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: asyncRequirements.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: asyncRequirements.isLoading
                  ? null
                  : () => ref.invalidate(graduationRequirementsProvider),
            ),
          ],
        ),
        body: body,
      );
    }

    return body;
  }

  Widget _buildRow(
    BuildContext context,
    GraduationRequirement req,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: req.index.isOdd
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
          : Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${req.index}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(child: Text(req.item, style: const TextStyle(fontSize: 14))),
          SizedBox(
            width: 80,
            child: Text(
              req.credit.toStringAsFixed(2),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    BuildContext context,
    GraduationRequirement req,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.error.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              '合计',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              req.credit.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
