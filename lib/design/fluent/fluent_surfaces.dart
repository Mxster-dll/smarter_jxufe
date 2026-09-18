import 'package:flutter/material.dart';

import 'fluent_tokens.dart';

/// Fluent 页面底：Mica 等效实色 + 内容宽度上限。
///
/// Win11 真正的 Mica 需要桌面端透明窗口（Flutter 侧要 `flutter_acrylic` 之类的原生能力），
/// 本项目不引额外依赖，因此用 Fluent 的**等效实色** `fluent(context).bgBase`
/// （浅色 `#F3F3F3` / 深色 `#121212`）打底 —— 视觉结果一致，不涉及平台 API。
class FluentPageBackground extends StatelessWidget {
  const FluentPageBackground({
    super.key,
    required this.child,
    this.maxContentWidth = 880,
  });

  final Widget child;

  /// 宽窗口下的内容宽度上限（Fluent 的「内容填满窗口」不等于拉伸到 4K 全宽）。
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: fluent(context).bgBase,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Fluent 卡片：填充 + 1px 描边 + 8px 圆角。
///
/// Win11 的卡片**静止态没有阴影**（[elevated] 默认 false），阴影只给浮层用。
class FluentCard extends StatelessWidget {
  const FluentCard({
    super.key,
    required this.child,
    this.padding,
    this.fill,
    this.stroke,
    this.radius = FluentRadius.overlay,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Color? stroke;
  final double radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill ?? p.cardDefault,
        border: Border.all(color: stroke ?? p.strokeCard),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated ? FluentShadows.card : null,
      ),
      child: child,
    );
  }
}

/// Fluent 分隔线：1px `fluent(context).strokeDivider`，可缩进对齐文字起点。
class FluentDivider extends StatelessWidget {
  const FluentDivider({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: indent, right: endIndent),
      color: fluent(context).strokeDivider,
    );
  }
}

/// 节标题：20/600 主标题 + 可选 12/400 说明 + 可选尾部控件。
class FluentSectionHeader extends StatelessWidget {
  const FluentSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    this.padding = const EdgeInsets.only(
      left: FluentSpacing.xs,
      right: FluentSpacing.xs,
      bottom: FluentSpacing.sm,
    ),
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FluentType.subtitle.copyWith(color: p.textPrimary),
                ),
                if (description != null) ...[
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    description!,
                    style: FluentType.caption.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// InfoBar 的语义等级。
enum FluentInfoSeverity { informational, success, warning, error }

/// Fluent InfoBar：状态提示条（成功 / 警告 / 错误 / 信息）。
///
/// 用于替代 Material 的 `SnackBar` 式反馈与裸文本错误页：底色 = 状态淡色、
/// 1px 状态色描边、左侧状态图标。
class FluentInfoBar extends StatelessWidget {
  const FluentInfoBar({
    super.key,
    required this.message,
    this.severity = FluentInfoSeverity.informational,
    this.title,
    this.action,
  });

  final String message;
  final FluentInfoSeverity severity;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final (Color bg, Color stroke, Color tint, IconData icon) = switch (severity) {
      FluentInfoSeverity.informational => (
        p.neutralBg,
        p.strokeControlDefault,
        p.neutral,
        Icons.info_outline,
      ),
      FluentInfoSeverity.success => (
        p.successBg,
        p.success,
        p.success,
        Icons.check_circle_outline,
      ),
      FluentInfoSeverity.warning => (
        p.cautionBg,
        p.strokeControlDefault,
        p.cautionDeep,
        Icons.warning_amber_outlined,
      ),
      FluentInfoSeverity.error => (
        p.criticalBg,
        p.critical,
        p.critical,
        Icons.error_outline,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(FluentSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: stroke),
        borderRadius: FluentRadius.overlayAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: FluentSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: FluentType.bodyStrong.copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: FluentSpacing.xs),
                ],
                Text(
                  message,
                  style: FluentType.body.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: FluentSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 全页加载态：Fluent ProgressRing + 说明文字。
class FluentLoading extends StatelessWidget {
  const FluentLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: p.accent),
          ),
          if (message != null) ...[
            const SizedBox(height: FluentSpacing.lg),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: FluentType.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fluent 指标卡：顶部标签 + 关键数字（40/600）+ 单位 + 说明 + 自定义页脚。
///
/// 对应 Win11 设置页里「卡片左上角是设置名、右下角是值」的层级。
class FluentMetricCard extends StatelessWidget {
  const FluentMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.description,
    this.trailing,
    this.footer,
  });

  final String label;
  final String value;
  final String? unit;
  final String? description;

  /// 右上角控件（刷新按钮等）。
  final Widget? trailing;

  /// 数字下方的自定义内容（占比条等）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return FluentCard(
      padding: const EdgeInsets.all(FluentSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: FluentType.caption.copyWith(color: p.textSecondary),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: FluentSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: FluentType.titleLarge.copyWith(color: p.textPrimary),
              ),
              if (unit != null) ...[
                const SizedBox(width: FluentSpacing.xs),
                Text(
                  unit!,
                  style: FluentType.body.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: FluentSpacing.xs),
            Text(
              description!,
              style: FluentType.caption.copyWith(color: p.textSecondary),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: FluentSpacing.lg),
            footer!,
          ],
        ],
      ),
    );
  }
}
