/// 网络服务各页面共用的展示件与格式化工具。
///
/// 卡片口径 = `lib/design/app_card.dart`（圆角 12 + 淡边框 + 纯白 + 无阴影），
/// 本文件只提供「网络服务」自己的排版件（信息行 / 空态 / 错误卡 / 数值格式），
/// **不要再在页面里另写一套圆角与边框**。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';

/// 纯格式化工具在 domain 层（`network_service_format.dart`），这里一并转出：
/// 各页面只 import 本文件即可用 `networkFormatFlow` / `networkFormatDate` 等。
export 'package:smarter_jxufe/features/network_service/domain/network_service_format.dart';

/// 网络服务段/子页的强调色 = **主题红**（`colorScheme.primary`）。
///
/// ⚠ 唯一口径见 `lib/design/app_card.dart` 与 AGENTS §16：**单色强调一律改主题红**
/// （用户 2026-09-15 裁定）。这里曾经用自注册的青蓝 `FeaturePalette.networkService`
/// （`#00838F`），结果**同一张「校园网」页里第一段（余额）是红、第二段是青蓝**，
/// 两套强调色并列 —— 已按口径收敛回主题红。要区分「网络服务」与「充值」两段，
/// 靠的是**分组标题 + 卡片结构**，不是换色。
///
/// 只有**状态语义**才用别的颜色：正常/在线 = `fp(context).networkServiceOk`，
/// 停机 = `fp(context).networkServiceStop`（深色下自动提亮，见 `feature_palette.dart`）。
Color networkAccent(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// 强调色的 10% 淡底（图标底板等，与首页磁贴口径一致）。
///
/// 深色侧由 [AppColors.tint] 抬到 `AppLadder.darkTintAlpha(0.10)`（= 0.22）——
/// 原来写死的 0.10 叠在深色卡片上等于看不见；**全应用 network 图标底板共用这一处**。
Color networkAccentSoft(BuildContext context) =>
    AppColors.tint(context, networkAccent(context), 0.10);

/// 网络服务卡片（可点击时传 [onTap]）。
Widget networkCard(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(kAppCardPadding),
  VoidCallback? onTap,
  Key? key,
}) {
  final scheme = Theme.of(context).colorScheme;
  final shape = appCardShape(context);
  // 卡片底一律走 AppColors.card(context)（浅色纯白 / 深色 #1A1A1A）：
  // 不能再写 app_card.dart 的 kAppCardColor 常量（那是固定 #FFFFFF，深色下成白块）。
  final cardColor = AppColors.card(context);
  if (onTap == null) {
    return Container(
      key: key,
      padding: padding,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(kAppCardRadius),
        border: Border.all(color: appCardBorderSide(scheme).color),
      ),
      child: child,
    );
  }
  return Material(
    key: key,
    color: cardColor,
    shape: shape,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// 节标题（3px 竖条 + 13.5 w600，与全应用同款；[trailing] 右对齐）。
Widget networkSectionTitle(
  BuildContext context,
  String text, {
  Widget? trailing,
  Color? accent,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(
    children: [
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: accent ?? networkAccent(context),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
          letterSpacing: 0.3,
        ),
      ),
      if (trailing != null) ...[const Spacer(), trailing],
    ],
  );
}

/// 加载中的占位卡。
Widget networkLoadingCard(BuildContext context, {String text = '正在读取网络服务…'}) {
  final scheme = Theme.of(context).colorScheme;
  return networkCard(
    context,
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

/// 错误卡（带重试）。[needGuid] 为真时文案提示去配置平台标识。
Widget networkErrorCard(
  BuildContext context,
  Object error, {
  required VoidCallback onRetry,
  VoidCallback? onConfigureGuid,
}) {
  final scheme = Theme.of(context).colorScheme;
  final text = error.toString().replaceFirst('Exception: ', '');
  final needGuid = onConfigureGuid != null && text.contains('GUID');
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: needGuid
          ? AppColors.tint(context, scheme.primary, 0.05)
          : AppColors.tint(context, scheme.error, 0.06),
      borderRadius: BorderRadius.circular(kAppCardRadius),
      border: Border.all(
        color: needGuid
            ? AppColors.tintBorder(context, scheme.primary, 0.3)
            : AppColors.tintBorder(context, scheme.error, 0.35),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          needGuid ? Icons.info_outline : Icons.error_outline,
          size: 18,
          color: needGuid ? scheme.primary : scheme.error,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: needGuid ? scheme.onSurface : scheme.error,
            ),
          ),
        ),
        if (needGuid)
          TextButton(
            onPressed: onConfigureGuid,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('去配置'),
          )
        else
          TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('重试'),
          ),
      ],
    ),
  );
}

/// 空态卡（无记录时用，明确说明「没有」而不是留白）。
Widget networkEmptyCard(
  BuildContext context, {
  required String text,
  IconData? icon,
}) {
  final scheme = Theme.of(context).colorScheme;
  return networkCard(
    context,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
    child: Column(
      children: [
        Icon(
          icon ?? Icons.inbox_outlined,
          size: 26,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// 左标签 + 右值的信息行（网络服务各页统一用它，值用等宽数字）。
Widget networkInfoRow(
  BuildContext context, {
  required String label,
  required String value,
  Color? valueColor,
  bool bold = false,
  double labelWidth = 90,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: valueColor ?? scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// 明细行的通用外壳（图标 + 标题/副标题 + 右侧值）。
Widget networkRecordTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  String? trailing,
  String? trailingNote,
  Color? accent,
  VoidCallback? onTap,
  Key? key,
}) {
  final scheme = Theme.of(context).colorScheme;
  final color = accent ?? networkAccent(context);
  final body = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tint(context, color, 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (trailingNote != null && trailingNote.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  trailingNote,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
        ],
      ],
    ),
  );
  return onTap == null
      ? KeyedSubtree(key: key, child: body)
      : Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(onTap: onTap, child: body),
        );
}

/// 强调数字（余额 / 用量大数）。
Widget networkMetric(
  BuildContext context, {
  required String label,
  required String value,
  String? unit,
  Color? color,
  Key? key,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            key: key,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: color ?? scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (unit != null && unit.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              unit,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    ],
  );
}

/// 状态胶囊（账号正常 / 停机 / 在线 / 离线）。
///
/// 淡底走 [AppColors.statusFill]（浅色 12% / 深色 22%）—— 深色下固定 10% 的
/// 状态淡底在深底上看不出来。状态色由调用方经 `fp(context).networkServiceOk`
/// / `fp(context).networkServiceStop` 传入（已按亮度提亮）。
Widget networkBadge(BuildContext context, String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
  decoration: BoxDecoration(
    color: AppColors.statusFill(context, color),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
  ),
);

/// 写操作前的二次确认（危险操作用红按钮 + 说明后果）。
Future<bool> networkConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  bool danger = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        danger ? Icons.warning_amber_outlined : Icons.help_outline,
        color: danger ? scheme.error : scheme.primary,
      ),
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 13, height: 1.6)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.errorFill(context),
                  foregroundColor: AppColors.onErrorFill(context),
                )
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return ok ?? false;
}
