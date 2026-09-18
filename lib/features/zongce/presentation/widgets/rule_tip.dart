import 'dart:async';

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
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

/// 浮层卡片的 Key（测试用：量它的真实矩形）。
const Key ruleTipCardKey = Key('ruleTipCard');

/// 浮层与按钮之间的间距 / 与屏幕边缘的最小留白。
const double _tipGap = 6;
const double _tipMargin = 8;

/// 浮层定位：贴着按钮下方，放不下就翻到上方，横向夹取在屏幕内。
///
/// 用 `CustomSingleChildLayout` 而不是 `Positioned`：只有 delegate 的
/// `getPositionForChild(size, child)` 同时拿得到**屏幕尺寸**与**卡片真实尺寸**，
/// 才能既不越界、又紧贴按钮（不再靠 `maxHeight` 估高）。
///
/// **两条硬约束**：
/// ① 卡片与悬停目标不相交（用户 2026-09-18：「综测的悬浮显示不能遮盖悬停的地方」）
///    —— 定位一律按**原始锚点** + `gap`（≥6px，天然不压住按钮），且高度上限取
///    「较大一侧的实际可用空间」→「放不下就翻面」永远成立；
/// ② 卡片不越出屏幕（横向夹取、纵向贴着锚点那一侧）。
class _TipPositionDelegate extends SingleChildLayoutDelegate {
  const _TipPositionDelegate({
    required this.anchor,
    required this.gap,
    required this.margin,
  });

  /// 按钮矩形（**build 时**算好传进来）。
  ///
  /// ⚠ 不能在 `getPositionForChild` 里现算（`localToGlobal` 会读祖先 `RenderBox.size`，
  /// 布局期读取被禁 → `RenderBox.size accessed beyond the scope of resize, layout…`
  /// 断言 + 卡片被扔到屏幕外）。滚动的跟随靠 `markNeedsBuild` 重建（重建期合法）。
  final Rect anchor;
  final double gap;
  final double margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // 卡片高度上限 = **较大那一侧的实际可用空间**，于是「放不下就翻面」这条
    // 永远成立 → 卡片绝不可能压到悬停处（用户 2026-09-18：「悬浮显示不能
    // 遮盖悬停的地方」）。旧版固定 clamp(120, 460)，矮窗口下靠
    // `(size.height - margin - child.height).clamp(margin, belowTop)` 兜底，
    // 那一夹就把卡片夹到了按钮上。
    final maxW = (constraints.maxWidth - margin * 2).clamp(200.0, 420.0);
    final availBelow = _availBelow(constraints.maxHeight);
    final availAbove = _availAbove();
    final best = availBelow > availAbove ? availBelow : availAbove;
    final maxH = best <= 0 ? 0.0 : (best > 460 ? 460.0 : best);
    return BoxConstraints(maxWidth: maxW, maxHeight: maxH);
  }

  double _availBelow(double screenHeight) =>
      screenHeight - margin - (anchor.bottom + gap);

  double _availAbove() => (anchor.top - gap) - margin;

  @override
  Offset getPositionForChild(Size size, Size child) {
    final availBelow = _availBelow(size.height);
    final availAbove = _availAbove();
    final belowTop = anchor.bottom + gap;
    final aboveTop = anchor.top - gap - child.height;
    double top;
    if (child.height <= availBelow) {
      top = belowTop; // 下方放得下：紧贴按钮下沿
    } else if (child.height <= availAbove) {
      top = aboveTop; // 翻到上方：贴着按钮上沿
    } else if (availBelow >= availAbove) {
      // 兜底（理论上进不来：maxHeight 已按较大一侧约束）：选空间大的一侧。
      top = belowTop;
    } else {
      top = aboveTop < margin ? margin : aboveTop;
    }
    final maxLeft = size.width - margin - child.width;
    final left = maxLeft < margin
        ? margin
        : (anchor.center.dx - child.width / 2).clamp(margin, maxLeft);
    // 最终不遮挡保证（用户 2026-09-18：「不能覆盖」）：上面所有分支算完后，若卡片
    // 仍与锚点（外扩半个 gap）相交，就按「有空间的一侧」再挪一次；两侧都塞不下时
    // 宁可贴屏幕边，也绝不回压到按钮上。
    final guard = anchor.inflate(gap / 2);
    var rect = Rect.fromLTWH(left, top, child.width, child.height);
    if (rect.overlaps(guard)) {
      final above = anchor.top - gap - child.height;
      final below = anchor.bottom + gap;
      rect = above >= margin
          ? Rect.fromLTWH(left, above, child.width, child.height)
          : Rect.fromLTWH(left, below, child.width, child.height);
    }
    return rect.topLeft;
  }

  @override
  bool shouldRelayout(_TipPositionDelegate old) =>
      old.gap != gap || old.margin != margin || old.anchor != anchor;
}

class _RuleTipState extends State<RuleTip> with WidgetsBindingObserver {
  OverlayEntry? _entry;
  Timer? _closeTimer;
  ScrollPosition? _scrollPosition;
  bool _repositionScheduled = false;

  /// 浮层可见期间的**逐帧跟随**开关（用户 2026-09-18：「每个都有可能，会随着
  /// 滚动，原来不遮挡的可能也会遮挡」）。
  ///
  /// 只挂滚动监听不够：卡片高度变化（点开/收起分区、材料增删）、页面转场动画、
  /// 键盘弹出、父级 `AnimatedSize` 等都会让按钮**在不滚动的情况下**移动 →
  /// 浮层停原地，于是就压住了按钮。逐帧比对锚点矩形（一次 `localToGlobal`，
  /// 只在浮层可见时跑）是唯一能保证「永远贴着、永远不压」的做法。
  bool _watching = false;
  Rect? _lastAnchor;

  /// 视口尺寸（= Overlay 尺寸）；用于判断按钮是否已经滚出屏幕。
  Size _viewportSize = Size.zero;

  /// 窗口尺寸变化（改窗口大小 / 旋转 / 键盘）也要重新定位。
  @override
  void didChangeMetrics() {
    if (mounted) _viewportSize = MediaQuery.sizeOf(context);
    _syncAnchor(force: true);
  }

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
    _stopWatch();
    WidgetsBinding.instance.removeObserver(this);
    _detachScrollListener();
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
    if (!_anchorAttached) return;
    _viewportSize = MediaQuery.sizeOf(context);
    _lastAnchor = null;
    _entry = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: CustomSingleChildLayout(
          // 位置交给 delegate 算：只有它拿得到**卡片的真实尺寸**
          // （用户 2026-09-17：「悬浮提示位置不对，我希望显示在悬浮按钮周围，
          //  并且不能超出屏幕外」——旧版按 maxHeight 估高，翻到上方时会离按钮很远）。
          delegate: _TipPositionDelegate(
            anchor: _anchorRect(),
            gap: _tipGap,
            margin: _tipMargin,
          ),
          child: _RuleTipCard(
            key: ruleTipCardKey,
            blocks: [
              for (final id in _ids)
                if (zcTipBlocks[id] != null) zcTipBlocks[id]!,
            ],
            maxHeight: MediaQuery.of(ctx).size.height,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    _attachScrollListener();
    WidgetsBinding.instance.addObserver(this);
    _startWatch();
  }

  bool get _anchorAttached {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize;
  }

  /// 按钮当前在屏幕上的矩形；**每次布局都重新读** → 滚动 / 改窗口大小后跟着走。
  Rect _anchorRect() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _attachScrollListener() {
    _detachScrollListener();
    _scrollPosition = Scrollable.maybeOf(context)?.position
      ?..addListener(_reposition);
  }

  void _detachScrollListener() {
    _scrollPosition?.removeListener(_reposition);
    _scrollPosition = null;
  }

  /// 触发一次重排（delegate 会重读按钮位置）。
  ///
  /// ⚠ 必须等**这一帧布局落地**再重排：`ScrollPosition` 的通知是在新偏移应用
  /// **之前**同步发出的，此刻 `localToGlobal` 读到的还是旧位置 → 卡片会停在原地
  /// 不动（实测滚动 40 后卡片纹丝不动）。
  void _reposition() {
    if (!mounted || _entry == null || _repositionScheduled) return;
    _repositionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repositionScheduled = false;
      _syncAnchor();
    });
  }

  /// 逐帧跟随（浮层可见期间）。
  void _startWatch() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addPostFrameCallback(_tick);
  }

  void _stopWatch() => _watching = false;

  void _tick(Duration _) {
    if (!mounted || _entry == null || !_watching) return;
    _syncAnchor();
    if (mounted && _entry != null && _watching) {
      WidgetsBinding.instance.addPostFrameCallback(_tick);
    }
  }

  /// 把浮层对齐到按钮**当前**位置；按钮滚出屏幕就收起浮层。
  void _syncAnchor({bool force = false}) {
    if (!mounted || _entry == null) return;
    if (!_anchorAttached) {
      _hide();
      return;
    }
    final rect = _anchorRect();
    if (!_anchorVisible(rect)) {
      _hide();
      return;
    }
    if (force || _lastAnchor != rect) {
      _lastAnchor = rect;
      _entry!.markNeedsBuild();
    }
  }

  /// 按钮至少露出一半才继续显示：只露一条缝时（贴屏幕边）浮层只能被夹到很远，
  /// 与其「离得远」不如直接收起（用户 2026-09-18：「不要离悬停区太远，但是
  /// 又不能覆盖」）。
  bool _anchorVisible(Rect rect) {
    final viewport = Offset.zero & _viewportSize;
    final shown = rect.intersect(viewport);
    if (shown.isEmpty) return false;
    return shown.height >= rect.height * 0.5 &&
        shown.width >= rect.width * 0.5;
  }

  void _hide() {
    _closeTimer?.cancel();
    _stopWatch();
    WidgetsBinding.instance.removeObserver(this);
    _detachScrollListener();
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
  const _RuleTipCard({
    super.key,
    required this.blocks,
    required this.maxHeight,
  });

  final List<ZcTipBlock> blocks;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.hairline(context, 0.9),
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
      color: AppColors.hairline(context, 0.7),
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
