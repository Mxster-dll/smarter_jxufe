import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_tip_data.dart';

/// 规则悬浮提示按钮（复刻《2026 综测计算器.html》的 .sub-info 悬浮卡片）：
/// 鼠标悬停（桌面）或点按（触屏）显示条款依据浮层——规则行(k: v) + 内嵌分值
/// 表格(tip-table)。浮层内容来自 [zcTipBlocks]，挂载映射 [zcTipRefs]。
///
/// 用法: [tipKey] 传 zcTipRefs 里的挂载键（如 'd-2-ping'），或直接传 [ids]
/// 规则点 id 列表（如材料加分行的 ['r22']）；两者都不给则不渲染任何东西。
class RuleTip extends StatefulWidget {
  const RuleTip({super.key, this.tipKey, this.ids, this.color, this.size = 14});

  final String? tipKey;
  final List<String>? ids;
  final Color? color;
  final double size;

  @override
  State<RuleTip> createState() => _RuleTipState();
}

class _RuleTipState extends State<RuleTip> {
  OverlayEntry? _entry;
  Timer? _closeTimer;

  List<String> get _ids {
    final ids = widget.ids;
    if (ids != null) return ids;
    final key = widget.tipKey;
    if (key == null) return const [];
    return zcTipRefs[key] ?? const [];
  }

  bool get _hasContent {
    for (final id in _ids) {
      if (zcTipBlocks[id] != null) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _scheduleClose([int ms = 350]) {
    _closeTimer?.cancel();
    _closeTimer = Timer(Duration(milliseconds: ms), _hide);
  }

  void _show() {
    _closeTimer?.cancel();
    if (_entry != null || !_hasContent) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final anchor = box.localToGlobal(Offset.zero);
    final anchorBottom = box.localToGlobal(Offset(0, box.size.height));

    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final cardMaxW = (mq.size.width - 32).clamp(280.0, 420.0);
        final cardMaxH = (mq.size.height - 24).clamp(200.0, 400.0);
        final below = anchorBottom.dy + 10 + cardMaxH <= mq.size.height;
        final left = (anchor.dx + box.size.width / 2 - cardMaxW / 2).clamp(
          8.0,
          mq.size.width - cardMaxW - 8,
        );
        final top = below
            ? anchorBottom.dy + 6
            : (anchor.dy - 6 - cardMaxH).clamp(8.0, double.infinity);
        return Positioned(
          left: left,
          top: top,
          width: cardMaxW,
          child: _RuleTipCard(
            blocks: [
              for (final id in _ids)
                if (zcTipBlocks[id] != null) zcTipBlocks[id]!,
            ],
            maxHeight: cardMaxH,
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _closeTimer?.cancel();
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _hide();
    } else {
      _show();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _show(),
      onExit: (_) => _scheduleClose(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Tooltip(
            message: '查看条款依据',
            waitDuration: const Duration(milliseconds: 600),
            child: Icon(
              Icons.info_outline_rounded,
              size: widget.size,
              color: scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮层卡片：白底圆角描边阴影；多块时块间虚线分隔。
class _RuleTipCard extends StatelessWidget {
  const _RuleTipCard({required this.blocks, required this.maxHeight});

  final List<ZcTipBlock> blocks;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 14,
                    thickness: 0.7,
                    indent: 2,
                    endIndent: 2,
                  ),
                _block(context, blocks[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, ZcTipBlock b) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          b.title,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        for (final part in b.parts)
          if (part is ZcTipRow)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 92),
                    child: Text(
                      part.k,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      part.v,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (part is ZcTipTable)
            Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 2),
              child: _tipTable(context, part),
            ),
      ],
    );
  }

  Widget _tipTable(BuildContext context, ZcTipTable t) {
    final scheme = Theme.of(context).colorScheme;
    final border = TableBorder.all(
      color: scheme.outlineVariant.withValues(alpha: 0.7),
      width: 0.6,
    );
    TableRow headRow() => TableRow(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      children: [
        for (final h in t.head)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
            child: Text(
              h,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
    TableRow dataRow(List<String> r) => TableRow(
      children: [
        for (var c = 0; c < r.length; c++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              r[c],
              textAlign: c == 0 && r.length > 2
                  ? TextAlign.left
                  : TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.3,
              ),
            ),
          ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Table(
        border: border,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var c = 0; c < t.head.length; c++)
            c: c == 0 && t.head.length >= 3
                ? const IntrinsicColumnWidth()
                : const FlexColumnWidth(),
        },
        children: [headRow(), for (final r in t.rows) dataRow(r)],
      ),
    );
  }
}
