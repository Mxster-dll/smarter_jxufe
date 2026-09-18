import 'package:flutter/material.dart';

import 'fluent_tokens.dart';

/// Fluent 列表行：可选前置件 + 标题 + 说明 + 尾部值，带 hover / pressed 填充。
///
/// ⚠️ hover 只做**增强**：手势挂在真实指针事件上（`GestureDetector`），触摸设备
/// 没有 hover 也能点（AGENTS.md §3 的硬约定，别再改成 `MouseRegion` 门控）。
class FluentListRow extends StatefulWidget {
  const FluentListRow({
    super.key,
    required this.title,
    this.leading,
    this.description,
    this.trailing,
    this.onTap,
    this.minHeight = 52,
  });

  final String title;

  /// 标题左侧（序号徽标、图标等）。
  final Widget? leading;

  /// 标题下方的 12/400 说明。
  final String? description;

  /// 行尾（数值、开关、箭头等）。
  final Widget? trailing;

  final VoidCallback? onTap;

  /// 行最小高度（44 起，触摸友好）。
  final double minHeight;

  @override
  State<FluentListRow> createState() => _FluentListRowState();
}

class _FluentListRowState extends State<FluentListRow> {
  bool _hovered = false;
  bool _pressed = false;

  void _set({bool? hovered, bool? pressed}) {
    if (!mounted) return;
    setState(() {
      if (hovered != null) _hovered = hovered;
      if (pressed != null) _pressed = pressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final fill = _pressed
        ? p.controlTertiary
        : (_hovered ? p.controlSecondary : Colors.transparent);

    final row = AnimatedContainer(
      duration: FluentMotion.fast,
      curve: FluentMotion.easyEase,
      margin: const EdgeInsets.symmetric(horizontal: FluentSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.md,
        vertical: FluentSpacing.sm,
      ),
      constraints: BoxConstraints(minHeight: widget.minHeight),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: FluentRadius.controlAll,
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: FluentSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: FluentType.body.copyWith(color: p.textPrimary),
                ),
                if (widget.description != null) ...[
                  const SizedBox(height: FluentSpacing.xs),
                  Text(
                    widget.description!,
                    style: FluentType.caption.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: FluentSpacing.md),
            widget.trailing!,
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => _set(hovered: true),
      onExit: (_) => _set(hovered: false, pressed: false),
      child: widget.onTap == null
          ? row
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _set(pressed: true),
              onTapUp: (_) => _set(pressed: false),
              onTapCancel: () => _set(pressed: false),
              onTap: widget.onTap,
              child: row,
            ),
    );
  }
}

/// 序号徽标：24×24、4px 圆角、accent 8% 淡染底 + accent 字。
class FluentIndexBadge extends StatelessWidget {
  const FluentIndexBadge({super.key, required this.index, this.size = 24});

  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accentSubtle,
        borderRadius: FluentRadius.controlAll,
      ),
      child: Text(
        '$index',
        style: FluentType.bodyStrong.copyWith(color: p.accent),
      ),
    );
  }
}

/// Fluent 图标按钮：36×36 命中区、4px 圆角、hover / pressed 填充。
class FluentIconButton extends StatefulWidget {
  const FluentIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  State<FluentIconButton> createState() => _FluentIconButtonState();
}

class _FluentIconButtonState extends State<FluentIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _set({bool? hovered, bool? pressed}) {
    if (!mounted) return;
    setState(() {
      if (hovered != null) _hovered = hovered;
      if (pressed != null) _pressed = pressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final enabled = widget.onPressed != null;
    final fill = !enabled
        ? Colors.transparent
        : _pressed
        ? p.controlTertiary
        : (_hovered ? p.controlSecondary : Colors.transparent);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => _set(hovered: true),
        onExit: (_) => _set(hovered: false, pressed: false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _set(pressed: true) : null,
          onTapUp: enabled ? (_) => _set(pressed: false) : null,
          onTapCancel: enabled ? () => _set(pressed: false) : null,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: FluentMotion.fast,
            curve: FluentMotion.easyEase,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: FluentRadius.controlAll,
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: enabled ? p.textPrimary : p.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}

/// Fluent 按钮：标准（填充 + 描边）与强调（accent 实心）两种。
class FluentButton extends StatefulWidget {
  const FluentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.accent = false,
    this.dense = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// true = AccentButton（accent 实心 + 白字）。
  final bool accent;

  /// true = 32 高（默认 36）。
  final bool dense;

  final IconData? icon;

  @override
  State<FluentButton> createState() => _FluentButtonState();
}

class _FluentButtonState extends State<FluentButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _set({bool? hovered, bool? pressed}) {
    if (!mounted) return;
    setState(() {
      if (hovered != null) _hovered = hovered;
      if (pressed != null) _pressed = pressed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final enabled = widget.onPressed != null;
    final height = widget.dense ? 32.0 : 36.0;

    final Color fill;
    final Color stroke;
    final Color label;
    if (!enabled) {
      fill = widget.accent ? p.accentDisabled : p.controlDisabled;
      stroke = widget.accent ? Colors.transparent : p.strokeControlDefault;
      label = widget.accent ? p.textOnAccentSecondary : p.textDisabled;
    } else if (widget.accent) {
      fill = _pressed
          ? p.accentTertiary
          : (_hovered ? p.accentSecondary : p.accent);
      stroke = Colors.transparent;
      label = p.textOnAccentPrimary;
    } else {
      fill = _pressed
          ? p.controlTertiary
          : (_hovered ? p.controlSecondary : p.controlDefault);
      stroke = p.strokeControlDefault;
      label = p.textPrimary;
    }

    final textStyle = widget.accent
        ? FluentType.bodyStrong
        : FluentType.body;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _set(hovered: true),
      onExit: (_) => _set(hovered: false, pressed: false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(pressed: true) : null,
        onTapUp: enabled ? (_) => _set(pressed: false) : null,
        onTapCancel: enabled ? () => _set(pressed: false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: FluentMotion.fast,
          curve: FluentMotion.easyEase,
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? FluentSpacing.md : FluentSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: stroke),
            borderRadius: FluentRadius.controlAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: label),
                const SizedBox(width: FluentSpacing.sm),
              ],
              Text(widget.label, style: textStyle.copyWith(color: label)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 占比条的一段。
class FluentShareSegment {
  const FluentShareSegment({required this.weight, this.tooltip});

  /// 权重（如学分），非负。
  final double weight;

  /// 长按 / 悬停提示。
  final String? tooltip;
}

/// Fluent 占比条：一条细分段进度条，按权重分配宽度，accent 单色深浅区分各段。
///
/// 顺序**保持调用方给定顺序**（与列表一一对应），不做排序 —— 免得条与表对不上。
class FluentShareBar extends StatelessWidget {
  const FluentShareBar({
    super.key,
    required this.segments,
    this.height = 4,
    this.gap = 2,
  });

  final List<FluentShareSegment> segments;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    final accent = fluent(context).accent;
    final n = segments.length;
    final children = <Widget>[];
    for (var i = 0; i < n; i++) {
      final segment = segments[i];
      final alpha = n == 1 ? 0.9 : 0.9 - (i / (n - 1)) * 0.55;
      final flex = (segment.weight * 1000).round().clamp(1, 1 << 20);
      if (i > 0) children.add(SizedBox(width: gap));
      children.add(
        Expanded(
          flex: flex,
          child: Tooltip(
            message: segment.tooltip ?? '',
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: children);
  }
}
