import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';

/// 「我的」页的一行字段 —— 带**学校个人数据中心那一份**的三种形态。
///
/// 用户 2026-09-20 七轮原话：「我的页不显示从数据中心添加的信息，我希望这部分数据要换
/// 个颜色显示，如果原来的地方就有数据，则不覆盖，如果与已有数据冲突，则显示为『冲突』，
/// 然后点击显示冲突详情」。
///
/// 形态（判定在 [DzjFieldMerge.state] 里，界面不再自己判断）：
/// - 本地有值 → 照旧（主题正文色）；
/// - 本地空、数据中心有 → 用数据中心的值，走 [FeaturePalette.dzjSource] 那个颜色 +
///   「数据中心」小标；
/// - 两边都有且不同 → 值仍用本地那一份 + 行尾一枚可点的「冲突」胶囊（[DzjConflictChip]）。
class DzjMyFieldRow extends StatelessWidget {
  const DzjMyFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.dzj,
    this.leadingIcon,
    this.labelWidth = 84,
  });

  final String label;

  /// 本地（学籍缓存）里的值。[dzj] 给出 `fromCenter` 时会改用数据中心的值。
  final String value;

  final DzjFieldMerge? dzj;

  final IconData? leadingIcon;

  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final merge = dzj;
    final fromCenter = merge?.usesCenterValue ?? false;
    final shown = fromCenter ? merge!.value : value;
    final isEmpty = shown.isEmpty;
    final labelColor = isEmpty
        ? scheme.onSurfaceVariant.withValues(alpha: 0.3)
        : scheme.onSurfaceVariant;
    final valueColor = isEmpty
        ? scheme.onSurface.withValues(alpha: 0.25)
        : (fromCenter ? fp(context).dzjSource : scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leadingIcon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(leadingIcon, size: 16, color: labelColor),
            ),
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: labelColor),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    isEmpty ? '（无）' : shown,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: 14,
                      color: valueColor,
                      fontWeight: fromCenter ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (fromCenter) ...[
                  const SizedBox(width: 6),
                  DzjSourceTag(source: merge?.source ?? ''),
                ],
                if (merge?.isConflict ?? false) ...[
                  const SizedBox(width: 6),
                  DzjConflictChip(merge: merge!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「数据中心」小标 —— 让「这条值不是学籍里的」一眼可见。
class DzjSourceTag extends StatelessWidget {
  const DzjSourceTag({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final color = fp(context).dzjSource;
    return Container(
      key: const Key('dzjSourceTag'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '数据中心',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// 「冲突」胶囊：学籍与数据中心两份值不一致时挂在行尾，点开看对照。
class DzjConflictChip extends StatelessWidget {
  const DzjConflictChip({super.key, required this.merge});

  final DzjFieldMerge merge;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.critical(context);
    return InkWell(
      key: Key('dzjConflict-${merge.label}'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => showDzjConflictDetail(context, merge),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.tint(context, color, 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_gmailerrorred_outlined, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              '冲突',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 冲突详情：把两份值连同各自的来源摆在一起。
///
/// ⚠ `AlertDialog` 里**不许放 ListView / GridView**（`IntrinsicWidth` 不支持 intrinsic
/// 尺寸 → 弹窗永不渲染、`showDialog` 永不返回），两块值直接用 `Column` 铺。
Future<void> showDzjConflictDetail(
  BuildContext context,
  DzjFieldMerge merge,
) {
  final scheme = Theme.of(context).colorScheme;
  Widget block(BuildContext ctx, String title, String value, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted(ctx),
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value.isEmpty ? '（无）' : value,
            style: TextStyle(fontSize: 14, color: color),
          ),
        ],
      );
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('dzjConflictDialog'),
      icon: Icon(Icons.compare_arrows, color: AppColors.critical(ctx)),
      title: Text('${merge.label} · 数据冲突'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          block(ctx, 'App 学籍（采用这一份）', merge.local, scheme.onSurface),
          const SizedBox(height: 14),
          block(
            ctx,
            '学校数据中心 › ${merge.source}（未采用）',
            merge.remote,
            fp(ctx).dzjSource,
          ),
          const SizedBox(height: 14),
          Text(
            '学校数据中心的值不会覆盖学籍里的值；两边不一致时以学籍为准。'
            '若学籍侧是旧的，可在设置页「教务会话」刷新后重进本页。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppColors.textMuted(ctx),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('dzjConflictOk'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
