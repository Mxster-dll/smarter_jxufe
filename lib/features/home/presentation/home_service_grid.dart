/// 服务宫格（主页宫格视图）。
///
/// 用户 2026-09-15 裁定（第 2 条）：「电脑端宫格视图下，每个卡片要一样宽高，
/// 提示文本不足 1 行也显示为 2 行高，超过 2 行的显示省略号、只保留两行」。
///
/// 用户 2026-09-21 裁定（宫格聚合，逐字）：「宫格视图下，我希望增加聚合功能。现有的
/// 相当于每个宫格都是一个仅包含一个功能的卡片，我希望长按拖动后可以合并宫格，并且，
/// 宫格这样显示：宫格可以异形，长按拖动到其他卡片边边上时（必须要在某个边缘处，处于
/// 中间则此次拖动松手后不触发合并），松手后，合并到此边相邻的位置，然后并且未松手时，
/// 要在相应位置显示虚线框，如果没有与任何卡片相邻，则松手不触发合并。然后我们允许长按
/// 卡片调整位置（即使是异形的），并且要允许两个互补的卡片相互嵌套，例如一正一反两个
/// 大写 F 形的卡片可以相互插入空隙」。
///
/// 落地口径：
/// - **等高** = 每格外面套固定高度（[cardHeight] / [compactCardHeight] 由
///   [HomeGridMetrics] 按可用宽度算出），不靠 `IntrinsicHeight` 猜内容；
/// - **排版** = 不再用 `Wrap`，改成 `Stack` + `Positioned`：卡片位置来自
///   `HomeGridLayout`（绝对格坐标），因此可以异形、可以嵌进别人的空隙里；
/// - **聚合** = 长按抬起卡片 → 拖到别的卡片**边缘带**（[kHomeGridEdgeBand]）松手 →
///   落在那条边旁边并合并成一张卡（形状取并集）；拖到卡片**中间**不合并（用户口径）；
///   拖到空格 = 纯移动；落点不合法的松手 = 什么都不做；
/// - **虚线框** = 未松手时在落点画虚线轮廓（合并时目标卡也淡染一层）；
/// - 布局由外部传入并回写（[layout] / [onLayoutChanged]）—— 本组件刻意**不碰 Riverpod**，
///   这样既能被 `home_screen.dart` 接上持久化 store，也能在测试里裸 pump。
///
/// 用户 2026-09-21 四轮（逐字）：
/// 1. 「我希望功能与功能之间不显示分割线」→ 卡片内部**不再画分隔线**（[HomeGridCard.showDividers]
///    默认 false）；
/// 2. 「我希望可以进入拆解模式，此模式下，才显示分割线，点击分割线后，此边处不连接，
///    分成两部分，因此形成的边界，暂时显示为虚线。退出拆解模式时，如果有些分割线分开的
///    两边没有分开（还在其他地方相连），则恢复此处连接。」→ [splitMode] 打开时每个格缝上
///    画一条可点的分割线（[Key] `homeGridSeam-<a>-<b>`），点一下剪断 / 再接回；剪断后
///    卡片按连通块**当场分成几张卡**，被剪的那道边界画成虚线；退出时只有真的分成两块的缝
///    落盘（[homeGridEffectiveCuts]），绕路还连着的自动接回去；
/// 3. 「然后长按卡片也分为长按到功能部分，和卡片其余部分，前者不再移动整个卡片，而是改成
///    后者移动整个卡片，长按到功能部分时，只移动此功能，同样要用虚线展示预期效果」→
///    长按**某一格的脸** = 只拖这一个功能（[homeGridExtractCell] 把它从原卡里抠出来，
///    剩下部分留在原地；抠走长条中间那格会让两边断成两张卡）；长按**卡片其余部分**
///    （格与格之间的缝，[kHomeGridSeamHitPad] 加宽成 20px 命中带）= 拖整张卡（老行为）。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_split.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_card.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_metrics.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 「卡片其余部分」的手势带在缝的两侧各外扩这么多像素（12px 的缝 → 20px 的命中带）。
const double kHomeGridSeamHitPad = 4;

/// 服务宫格。
class HomeServiceGrid extends StatefulWidget {
  /// 目录条目（顺序 = 默认铺排顺序；聚合布局按标题与它们对齐）。
  final List<HomeServiceEntry> entries;

  /// 已保存的聚合布局；null = 还没自定义过 → 按目录顺序流式铺。
  final HomeGridLayout? layout;

  /// 拖动 / 合并产生新布局时回调（调用方负责落盘）。
  final ValueChanged<HomeGridLayout>? onLayoutChanged;

  /// 拆解模式：画分割线、点缝断开 / 接回（退出时把真分开的缝落盘）。
  final bool splitMode;

  const HomeServiceGrid({
    super.key,
    required this.entries,
    this.layout,
    this.onLayoutChanged,
    this.splitMode = false,
  });

  /// 窄屏断点（手机竖屏）：小于它走紧凑磁贴（图标在上、只留标题）。
  static const double compactBreakpoint = HomeGridMetrics.compactBreakpoint;

  /// 宽屏磁贴最小宽度（列数 = 可用宽度能摆几个这样的磁贴）。
  static const double minCard = HomeGridMetrics.minCard;

  /// 磁贴间距（横竖同值）。
  static const double gap = HomeGridMetrics.gap;

  /// 紧凑磁贴的目标宽度（等价 `SliverGridDelegateWithMaxCrossAxisExtent` 语义）。
  static const double compactExtent = HomeGridMetrics.compactExtent;

  /// 副标题单行高度（与 `TextStyle.height` 口径一致：12 × 16/12）。
  static const double subtitleLineHeight = HomeGridMetrics.subtitleLineHeight;

  /// 标题单行高度（15 × 20/15）。
  static const double titleLineHeight = HomeGridMetrics.titleLineHeight;

  /// 宽屏磁贴高度（= 86 + 2px 余量）。
  static const double cardHeight = HomeGridMetrics.cardHeight;

  /// 紧凑磁贴高度。
  static const double compactCardHeight = HomeGridMetrics.compactCardHeight;

  @override
  State<HomeServiceGrid> createState() => _HomeServiceGridState();
}

class _HomeServiceGridState extends State<HomeServiceGrid> {
  /// 网格自身（像素 ↔ 格子的坐标基准）。
  final GlobalKey _gridKey = GlobalKey();

  /// 正在被拖动的卡片身份（null = 没在拖）。拖单格时 = **抠出来那张单格卡**的 key。
  String? _dragKey;

  /// 正在被拖动的卡片。
  HomeGridTile? _dragTile;

  /// 正在被拖动的这一格是从哪张卡里抠出来的（null = 拖的是整张卡）。
  String? _extractFrom;

  /// 被抠出来的那一格。
  GridCell? _extractCell;

  /// 拆解模式里被剪断的缝（**只在拆解模式期间存在**，退出时结算：真分开的落盘）。
  Set<GridSeam> _cuts = <GridSeam>{};

  /// 起手抓住的格子（相对卡片包围盒左上角）。
  GridCell _grabCell = (x: 0, y: 0);

  /// 起手时指针相对卡片左上角的像素偏移（抬起的那张卡跟着手指走）。
  Offset _grabPixel = Offset.zero;

  /// 指针在网格内的位置。
  Offset? _pointerLocal;

  /// 当前落点方案（null = 松手什么都不会发生 → 不画虚线框）。
  HomeGridDropTarget? _plan;

  @override
  void didUpdateWidget(covariant HomeServiceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.splitMode && widget.splitMode) {
      // 进入拆解模式：从「全都连着」开始，每次进来都是新的一轮。
      _cuts = <GridSeam>{};
    } else if (oldWidget.splitMode && !widget.splitMode) {
      // 退出拆解模式：只有真把卡片分成两块的缝留下，其余接回去。
      // ⚠ 不能在 `didUpdateWidget` 里**同步**回调 `onLayoutChanged` —— 此刻父级正在
      //   build（当前构建目标是宫格下面的手势识别器），父级 setState 会被框架拒：
      //   `setState() or markNeedsBuild() called during build`。挪到帧末再回调。
      final cuts = _cuts;
      _cuts = <GridSeam>{};
      if (cuts.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _commitCuts(cuts),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final byTitle = <String, HomeServiceEntry>{
      for (final e in widget.entries) e.title: e,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = HomeGridMetrics.of(constraints.maxWidth);
        final layout = _displayLayout(metrics);
        final seams = _tileSeams(_savedLayout(metrics));
        final plan = _plan;
        final dragTile = _dragTile;
        final pointer = _pointerLocal;
        return SizedBox(
          key: _gridKey,
          height: metrics.heightOfRows(layout.rows),
          child: Stack(
            // 抬起的卡片 / 虚线框可以画到网格外面（长按拖到上方时不该被切掉）。
            clipBehavior: Clip.none,
            children: [
              for (final tile in layout.tiles)
                _card(tile, metrics, byTitle, hidden: tile.key == _dragKey),
              if (widget.splitMode)
                for (final seam in seams)
                  _seamHandle(seam.seam, metrics, context)
              else
                // 卡片其余部分（格与格之间的缝）= 拖整张卡的手势带；透明命中，
                // 轻点仍然穿透到下面那张脸（只有长按才起手）。
                // ⚠ 拖动中**不能**把这些手势带从树里摘掉 —— 摘掉会让长按识别器随
                //   Element 一起 dispose，move / end 再也送不到（卡片卡在半空、松手没反应）。
                for (final seam in seams)
                  _bodyHandle(seam.tile, seam.seam, metrics),
              if (plan != null) ..._preview(plan, metrics, context),
              if (dragTile != null && pointer != null)
                _lifted(dragTile, metrics, byTitle, pointer),
            ],
          ),
        );
      },
    );
  }

  /// 已保存布局 → 与当前目录对账 → 按当前列数贴合（**没有**抠格、**没有**拆缝）。
  HomeGridLayout _savedLayout(HomeGridMetrics metrics) {
    final titles = <String>[for (final e in widget.entries) e.title];
    final base =
        widget.layout ?? HomeGridLayout.flow(titles: titles, cols: metrics.cols);
    return base.reconcile(titles).fitTo(metrics.cols);
  }

  /// 计算基准布局 = 已保存布局 +（拖单格时）把那格从原卡里抠出来。
  ///
  /// 抠格只影响「这一次拖动」：被拖的是一张单格卡，剩下的部分留在原地（可能断成两张卡），
  /// 松手时合并 / 移动的结果直接落在这个基准布局上。
  HomeGridLayout _baseLayout(HomeGridMetrics metrics) {
    final base = _savedLayout(metrics);
    final from = _extractFrom;
    final cell = _extractCell;
    if (from == null || cell == null) return base;
    final tiles = <HomeGridTile>[];
    var found = false;
    for (final t in base.tiles) {
      if (t.key != from) {
        tiles.add(t);
        continue;
      }
      found = true;
      final extracted = homeGridExtractCell(t, cell);
      tiles
        ..add(extracted.moved)
        ..addAll(extracted.rest);
    }
    if (!found) return base;
    return HomeGridLayout(cols: base.cols, tiles: tiles);
  }

  /// 渲染布局 = 已保存布局 +（拆解模式）把剪断的缝两侧拆成各自的卡。
  ///
  /// ⚠ 拖单格时**不在这里**把那一格抠出来：抠格会让源卡片的 key 变掉（原卡换成
  ///   「抠出来那格 + 剩下的部分」）→ 那张卡的手势识别器随 Element 一起 dispose →
  ///   move / end 再也送不到（宫格拖动踩过两次的同款坑）。抠格只体现在抬起的卡
  ///   （[_dragTile]）与落点方案（[_baseLayout]）上，松手才真的改写布局。
  HomeGridLayout _displayLayout(HomeGridMetrics metrics) {
    final base = _savedLayout(metrics);
    final cuts = _cuts;
    if (!widget.splitMode || cuts.isEmpty) return base;
    return HomeGridLayout(
      cols: base.cols,
      tiles: homeGridSplitAll(base.tiles, cuts),
    );
  }

  /// 布局里每一条缝 + 它所属的卡（分割线图层与整卡拖动手势带共用）。
  List<({HomeGridTile tile, GridSeam seam})> _tileSeams(HomeGridLayout layout) => [
    for (final t in layout.tiles)
      for (final s in gridSeamsOf(t.cells)) (tile: t, seam: s),
  ];

  Widget _card(
    HomeGridTile tile,
    HomeGridMetrics metrics,
    Map<String, HomeServiceEntry> byTitle, {
    bool hidden = false,
  }) {
    final topLeft = metrics.topLeftOfTile(tile);
    final size = metrics.sizeOfTile(tile);
    final card = HomeGridCard(
      key: Key('homeGridCard-${tile.key}'),
      tile: tile,
      metrics: metrics,
      entriesByTitle: byTitle,
      // 长按手势挂在**每一格的脸**上（而不是整张卡的包围盒上）：
      // ① 异形卡片的包围盒里可能有别人嵌进来的格子，挂在外框上会把那格的手势吞掉；
      // ② 用户 2026-09-21 四轮：「长按到功能部分时，只移动此功能」→ 长按某一格 = 拖这一格。
      faceWrapper: (entry, cell, face) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _startDrag(tile, cell, d.globalPosition),
        onLongPressMoveUpdate: (d) => _updateDrag(d.globalPosition),
        onLongPressEnd: (_) => _finishDrag(),
        onLongPressCancel: _cancelDrag,
        child: face,
      ),
    );
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: size.width,
      height: size.height,
      // ⚠ 被拖动的那张卡**既不能从树里摘掉、也不能临时套一层新壳**：
      //   ① 摘掉（`if (tile.key != _dragKey)`）→ 长按识别器随 Element 一起 dispose；
      //   ② 临时 `Opacity(opacity: 0, child: card)`（只在 hidden 时才包）→ 单子节点
      //      的 reconciliation 不比 key，`HomeGridCard` 整个子树被重建 → 识别器同样换新。
      // 两种写法都会让 move / end 事件再也送不到（卡片卡在半空、松手没反应，实测）。
      // 所以包一层**恒存**的 Opacity，只切 0 / 1。
      child: Opacity(opacity: hidden ? 0 : 1, child: card),
    );
  }

  /// 缝的命中带：缝本身只有 12px 宽，向两侧各外扩 [kHomeGridSeamHitPad]。
  Rect _seamBand(GridSeam seam, HomeGridMetrics metrics) {
    const pad = kHomeGridSeamHitPad;
    const gap = HomeGridMetrics.gap;
    if (seam.a.x != seam.b.x) {
      // 竖缝（左右相邻）：a 在左。
      final x = seam.a.x * metrics.pitchX + metrics.cellWidth + gap / 2;
      final top = seam.a.y * metrics.pitchY;
      return Rect.fromLTRB(
        x - gap / 2 - pad,
        top,
        x + gap / 2 + pad,
        top + metrics.cellHeight,
      );
    }
    final y = seam.a.y * metrics.pitchY + metrics.cellHeight + gap / 2;
    final left = seam.a.x * metrics.pitchX;
    return Rect.fromLTRB(
      left,
      y - gap / 2 - pad,
      left + metrics.cellWidth,
      y + gap / 2 + pad,
    );
  }

  /// 缝的那条线（网格坐标）：竖缝取缝正中一条竖线，横缝同理；[inset] = 两端缩进
  /// （分割线风格 12；断开后通长 0）。
  (Offset, Offset) _seamLine(
    GridSeam seam,
    HomeGridMetrics metrics,
    double inset,
  ) {
    const gap = HomeGridMetrics.gap;
    if (seam.a.x != seam.b.x) {
      final x = seam.a.x * metrics.pitchX + metrics.cellWidth + gap / 2;
      final top = seam.a.y * metrics.pitchY;
      return (
        Offset(x, top + inset),
        Offset(x, top + metrics.cellHeight - inset),
      );
    }
    final y = seam.a.y * metrics.pitchY + metrics.cellHeight + gap / 2;
    final left = seam.a.x * metrics.pitchX;
    return (
      Offset(left + inset, y),
      Offset(left + metrics.cellWidth - inset, y),
    );
  }

  /// 拆解模式的分割线：**没断开** = 卡片描边同色的细实线；**断开了** = 主题红虚线
  /// （用户口径 2：「因此形成的边界，暂时显示为虚线」）。点一下切换断开 / 接回。
  Widget _seamHandle(
    GridSeam seam,
    HomeGridMetrics metrics,
    BuildContext context,
  ) {
    final cut = _cuts.contains(seam);
    final band = _seamBand(seam, metrics);
    final (a, b) = _seamLine(
      seam,
      metrics,
      cut ? 0 : kHomeGridDividerInset,
    );
    final path = Path()
      ..moveTo(a.dx - band.left, a.dy - band.top)
      ..lineTo(b.dx - band.left, b.dy - band.top);
    final color = cut
        ? appCardAccent(context)
        : appCardBorderSide(Theme.of(context).colorScheme).color;
    return Positioned(
      left: band.left,
      top: band.top,
      width: band.width,
      height: band.height,
      child: GestureDetector(
        key: Key('homeGridSeam-${gridSeamKey(seam)}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleCut(seam),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: CustomPaint(
            painter: HomeGridDashedPainter(
              path: path,
              color: color,
              strokeWidth: cut ? 1.8 : 1,
              dash: cut ? 5 : 1e6, // 一整段 = 实线（同一个画笔，不再引第二个 painter）
              dashGap: cut ? 4 : 0,
            ),
          ),
        ),
      ),
    );
  }

  /// 普通模式：**卡片其余部分**（格与格之间的缝）= 拖整张卡的手势带。
  /// 透明命中（[HitTestBehavior.translucent]）→ 轻点仍穿透到下面那张脸，只有长按才起手。
  Widget _bodyHandle(HomeGridTile tile, GridSeam seam, HomeGridMetrics metrics) {
    final band = _seamBand(seam, metrics);
    return Positioned(
      left: band.left,
      top: band.top,
      width: band.width,
      height: band.height,
      child: GestureDetector(
        key: Key('homeGridBody-${gridSeamKey(seam)}'),
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) => _startDrag(tile, null, d.globalPosition),
        onLongPressMoveUpdate: (d) => _updateDrag(d.globalPosition),
        onLongPressEnd: (_) => _finishDrag(),
        onLongPressCancel: _cancelDrag,
      ),
    );
  }

  /// 剪断 / 接回一条缝（拆解模式）。
  void _toggleCut(GridSeam seam) {
    setState(() {
      if (!_cuts.add(seam)) _cuts.remove(seam);
    });
    unawaited(HapticFeedback.selectionClick());
  }

  /// 退出拆解模式：**只有真把卡片分成两块的缝才落盘**，绕路还连着的接回去
  /// （用户口径 2）。从帧末回调进来，所以这里可以正常通知父级落盘。
  void _commitCuts(Set<GridSeam> cuts) {
    if (!mounted || cuts.isEmpty) return;
    final metrics = _metricsOf();
    final notify = widget.onLayoutChanged;
    if (metrics == null || notify == null) return;
    final base = _savedLayout(metrics);
    final effective = homeGridEffectiveCuts(base.tiles, cuts);
    if (effective.isEmpty) return;
    final next = HomeGridLayout(
      cols: base.cols,
      tiles: homeGridSplitAll(base.tiles, effective),
    );
    if (next.isValid) notify(next);
  }

  /// 虚线框：**合并后的整张卡**画虚线轮廓（不是贴在旁边的一个独立方框 ——
  /// 用户 2026-09-21 二轮：「虚线框要与将要连接的卡片**相连**，展示合并后的卡片形状」），
  /// 参与合并的每张卡各淡染一层。
  List<Widget> _preview(
    HomeGridDropTarget plan,
    HomeGridMetrics metrics,
    BuildContext context,
  ) {
    final accent = appCardAccent(context);
    final out = <Widget>[];
    final merged = plan.mergedResult;
    var index = 0;
    for (final tier in plan.joined) {
      out.add(
        _shapePreview(
          // 第一张沿用老 key（守卫与用例都在找它），其余按卡片 key 区分。
          key: index == 0
              ? const Key('homeGridPreviewTarget')
              : Key('homeGridPreviewTarget-${tier.key}'),
          tile: tier,
          metrics: metrics,
          path: homeGridShapePath(
            cells: tier.cells,
            origin: (x: tier.bounds.left, y: tier.bounds.top),
            metrics: metrics,
          ),
          color: accent.withValues(alpha: 0.55),
          fill: AppColors.tint(context, accent, 0.06),
          strokeWidth: 1.2,
          dash: 5,
          dashGap: 4,
        ),
      );
      index++;
    }
    final landing = merged ?? plan.landing;
    // 被**推开**（但不并入）的卡片：在它们的新位置上画一圈细实线 ——
    // 合并会把后续卡片往后顶一位，不提前画出来的话松手后那一跳会很突然。
    for (final pushed in plan.pushed.values) {
      out.add(
        _shapePreview(
          key: Key('homeGridPreviewPush-${pushed.key}'),
          tile: pushed,
          metrics: metrics,
          path: homeGridShapePath(
            cells: pushed.cells,
            origin: (x: pushed.bounds.left, y: pushed.bounds.top),
            metrics: metrics,
          ),
          color: AppColors.textMuted(context),
          fill: AppColors.tint(context, accent, 0.03),
          strokeWidth: 1,
          dash: 1e6, // 一整段 = 实线（同一个画笔，不再引第二个 painter）
          dashGap: 0,
        ),
      );
    }
    out.add(
      _shapePreview(
        key: const Key('homeGridPreview'),
        tile: landing,
        metrics: metrics,
        path: homeGridShapePath(
          cells: landing.cells,
          origin: (x: landing.bounds.left, y: landing.bounds.top),
          metrics: metrics,
        ),
        color: accent,
        fill: AppColors.tint(context, accent, 0.10),
      ),
    );
    return out;
  }

  Widget _shapePreview({
    required Key key,
    required HomeGridTile tile,
    required HomeGridMetrics metrics,
    required Path path,
    required Color color,
    required Color fill,
    double strokeWidth = 1.6,
    double dash = 7,
    double dashGap = 5,
  }) {
    final topLeft = metrics.topLeftOfTile(tile);
    final size = metrics.sizeOfTile(tile);
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: CustomPaint(
          key: key,
          painter: HomeGridDashedPainter(
            path: path,
            color: color,
            fill: fill,
            strokeWidth: strokeWidth,
            dash: dash,
            dashGap: dashGap,
          ),
        ),
      ),
    );
  }

  /// 被抬起的卡片（跟着指针走，带投影；自己原来的格子先空着）。
  Widget _lifted(
    HomeGridTile tile,
    HomeGridMetrics metrics,
    Map<String, HomeServiceEntry> byTitle,
    Offset pointer,
  ) {
    final size = metrics.sizeOfTile(tile);
    return Positioned(
      left: pointer.dx - _grabPixel.dx,
      top: pointer.dy - _grabPixel.dy,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.94,
          child: Transform.scale(
            scale: 1.02,
            child: HomeGridCard(
              key: const Key('homeGridLifted'),
              tile: tile,
              metrics: metrics,
              entriesByTitle: byTitle,
              lifted: true,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 拖动 ----------

  RenderBox? _gridBox() {
    final object = _gridKey.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  HomeGridMetrics? _metricsOf() {
    final box = _gridBox();
    if (box == null) return null;
    return HomeGridMetrics.of(box.size.width);
  }

  /// 起手拖动。[cell] = 抓住的那一格（拖**这一个功能**）；null = 抓在「卡片其余部分」
  /// （缝）上 → 拖**整张卡**（用户口径 3）。
  void _startDrag(HomeGridTile tile, GridCell? cell, Offset global) {
    if (widget.splitMode) return; // 拆解模式只做「点缝断开 / 接回」
    if (_dragKey != null) return; // 已经在拖了（多指按下时忽略后来者）
    final box = _gridBox();
    final metrics = _metricsOf();
    if (box == null || metrics == null) return;
    final effective = cell == null ? tile : homeGridExtractCell(tile, cell).moved;
    final local = box.globalToLocal(global);
    final grab = local - metrics.topLeftOfTile(effective);
    setState(() {
      _extractFrom = cell == null ? null : tile.key;
      _extractCell = cell;
      _dragKey = effective.key;
      _dragTile = effective;
      _grabPixel = grab;
      _pointerLocal = local;
      _syncPlan(metrics, effective, local, grab);
    });
    unawaited(HapticFeedback.mediumImpact());
  }

  void _updateDrag(Offset global) {
    final box = _gridBox();
    final metrics = _metricsOf();
    final tile = _dragTile;
    if (box == null || metrics == null || tile == null) return;
    final local = box.globalToLocal(global);
    setState(() {
      _pointerLocal = local;
      _syncPlan(metrics, tile, local, _grabPixel);
    });
  }

  /// 重算抓手格子与落点方案（纯计算；调用方负责 `setState`）。
  void _syncPlan(
    HomeGridMetrics metrics,
    HomeGridTile tile,
    Offset local,
    Offset grab,
  ) {
    final gx = metrics.pitchX <= 0
        ? 0
        : math.max(
            0,
            math.min(tile.width - 1, (grab.dx / metrics.pitchX).floor()),
          );
    final gy = metrics.pitchY <= 0
        ? 0
        : math.max(
            0,
            math.min(tile.height - 1, (grab.dy / metrics.pitchY).floor()),
          );
    _grabCell = (x: gx, y: gy);
    final cell = metrics.cellAt(local);
    final fraction = metrics.cellFractionAt(local);
    _plan = homeGridPlanDrop(
      layout: _baseLayout(metrics),
      draggedKey: tile.key,
      pointerCell: cell,
      grabCell: _grabCell,
      pointerFractionX: fraction.x,
      pointerFractionY: fraction.y,
    );
  }

  void _finishDrag() {
    final plan = _plan;
    final metrics = _metricsOf();
    // ⚠ 基准布局要在 _clearDrag 之前取：拖单格时它带着「抠出来」这一步。
    final before = metrics == null ? null : _baseLayout(metrics);
    setState(_clearDrag);
    final notify = widget.onLayoutChanged;
    if (plan == null || before == null || notify == null) return;
    final next = plan.apply(before);
    if (!next.isValid) return;
    notify(next);
    if (plan.isMerge) _announceMerge(plan, before, notify);
  }

  /// 合并给一条可撤销的提示。
  ///
  /// 合并是「长按 + 拖到边上」两个动作就能触发的，很容易误操作；而布局一旦合并就
  /// 没有单卡「拆开」的入口（只能拖到别处或整体恢复默认）—— 所以在这里给一次后悔药：
  /// SnackBar 的「撤销」把拖动前的布局原样写回去（同样会落盘）。
  ///
  /// ⚠ **`persist: false` 是必须的**（用户 2026-09-21 反馈「合并后，底部的提示信息
  /// 不消失」）：本机 Flutter 的 `SnackBar` 构造里写着 `persist = persist ?? action
  /// != null`（`snack_bar.dart:303`）—— **带 action 的 SnackBar 默认常驻**，而
  /// `ScaffoldMessengerState` 的自动消失计时器回调第一句就是 `if (snackBar.persist)
  /// return;`（`scaffold.dart:618-625`）→ `duration` 形同虚设、提示一直挂在底部。
  /// 显式写 false，`duration` 才真的生效。
  void _announceMerge(
    HomeGridDropTarget plan,
    HomeGridLayout before,
    ValueChanged<HomeGridLayout> notify,
  ) {
    final target = plan.target;
    if (target == null) return;
    final labels = plan.mergedLabels;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('homeGridMergedSnack'),
          duration: const Duration(seconds: 5),
          persist: false,
          content: Text(
            labels.length <= 2
                ? '已合并「${labels.first}」与「${labels.last}」'
                : '已合并 ${labels.length} 张卡片：'
                      '${labels.map((l) => '「$l」').join()}',
          ),
          action: SnackBarAction(label: '撤销', onPressed: () => notify(before)),
        ),
      );
  }

  void _cancelDrag() {
    if (_dragKey == null) return;
    setState(_clearDrag);
  }

  void _clearDrag() {
    _dragKey = null;
    _dragTile = null;
    _extractFrom = null;
    _extractCell = null;
    _plan = null;
    _pointerLocal = null;
    _grabPixel = Offset.zero;
    _grabCell = (x: 0, y: 0);
  }
}
