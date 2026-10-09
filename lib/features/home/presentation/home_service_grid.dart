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
///   拖到空格 = 纯移动；**拖到别人身上（中间 / 内缝）= 把压到的卡片挤开**（十二轮口径，
///   [kHomeGridSlideDuration]；预览直接取 `plan.apply` 的结果，见 `build` 里的 `pushedAt`）；
///   落点越界的松手 = 什么都不做；
/// - **虚线框** = 未松手时在落点画虚线轮廓（合并时目标卡也淡染一层）；
/// - 布局由外部传入并回写（[layout] / [onLayoutChanged]）—— 本组件刻意**不碰 Riverpod**，
///   这样既能被 `home_screen.dart` 接上持久化 store，也能在测试里裸 pump。
///
/// 用户 2026-09-21 四轮（逐字）：
/// 1. 「我希望功能与功能之间不显示分割线」→ 卡片内部**不再画分隔线**（[HomeGridCard.showDividers]
///    默认 false）；
/// 2. 「我希望可以进入拆解模式，此模式下，才显示分割线，点击分割线后，此边处不连接，
///    分成两部分，因此形成的边界，暂时显示为虚线。退出拆解模式时，如果有些分割线分开的
///    两边没有分开（还在其他地方相连），则恢复此处连接。」→ [editMode] 打开时每个格缝上
///    画一条可点的分割线（[Key] `homeGridSeam-<a>-<b>`），点一下剪断 / 再接回；剪断后
///    卡片按连通块**当场分成几张卡**，被剪的那道边界画成虚线；退出时只有真的分成两块的缝
///    落盘（[homeGridEffectiveCuts]），绕路还连着的自动接回去；
/// 3. 「然后长按卡片也分为长按到功能部分，和卡片其余部分，前者不再移动整个卡片，而是改成
///    后者移动整个卡片，长按到功能部分时，只移动此功能，同样要用虚线展示预期效果」→
///    长按**某一格的脸** = 只拖这一个功能（[homeGridExtractCell] 把它从原卡里抠出来，
///    剩下部分留在原地；抠走长条中间那格会让两边断成两张卡）；长按**卡片其余部分**
///    = 拖整张卡（老行为）。
///
/// 用户 2026-09-21 六轮（逐字）：「我们希望每个卡片内，功能的点击区不要太大，不然就很难
/// 移动整个卡片」→ 「功能部分」从**整格**收窄到**功能的内容块**：每格只有
/// `homeGridFaceContentPadding` 圈出来的那一块（图标 / 标题 / 副标题）长按才拖单个功能，
/// 格子四周那一圈 + 格与格之间的缝都算「卡片其余部分」（长按拖整张卡）。脸的视觉与
/// **轻点区照旧占满整格**（抓取区是 translucent，轻点继续穿透到脸的 `InkWell`）。
///
/// 用户 2026-09-21 九轮（逐字）：「我希望拆分模式更名为编辑模式，此模式下，拖动功能不需要
/// 长按，按下即可拖动，或者点击拿起，再次点击方下」→ 三件事：
/// 1. [editMode]（原「拆解模式」）**改名**，UI 文案与 key 一并改（`homeGridEditHint`；
///    开关本身十三轮起在设置页，见 `home_edit_mode.dart` —— 主页顶栏不再有这枚按钮）；
/// 2. 编辑模式里**按下即可拖**：抓取层的手势从长按换成 pan（[kHomeGridEditTouchSlop] 把
///    自己的滑动阈值压到很小，免得被主页滚动视图的 18px 抢走）；
/// 3. **点击拿起 / 再点放下**：点一下先「拿起」（同一套抬起渲染 + 虚线框），再点一下在
///    点的位置放下（压在别的卡片中间时退化成纯移动，[homeGridPlanTapDrop]）；点回原位 =
///    什么都没发生（语义指纹相同 → 不落盘）。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_split.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_card.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_metrics.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'widgets/home_grid_widgets.dart';

/// 「卡片其余部分」在**缝**上的补充命中带：缝两侧各外扩这么多像素（12px 的缝 → 20px 带）。
///
/// 用户 2026-09-21 六轮之后，整张卡除功能内容块之外的地方都能起手整卡拖动
/// （[HomeGridCard.bodyWrapper]），这条带因此在几何上与卡片自己的手势层**重合**
/// （同样是那张卡的缝、同样是拖整张卡）—— 保留它是给「缝」留一道与卡片轮廓裁剪无关的
/// 兜底：轮廓裁剪在极端异形 / 相邻格归属边界上万一判掉某条缝，缝上仍有得抓。
const double kHomeGridSeamHitPad = 4;

/// 编辑模式「按下即拖」给**宫格自己的手势层**换的触摸滑动阈值（逻辑像素）。
///
/// `GestureDetector` 的 pan 默认要 `kPanSlop = kTouchSlop × 2 = 36` 像素才起手
/// （`events.dart:2566` 的 `computePanSlop`：触摸走 `settings?.panSlop ?? kPanSlop`），
/// 而**祖先的滚动视图只要 18 像素就先把手势抢走**（宫格长在主页的滚动视图里）→ 手机上
/// 「按下即拖」根本拖不动、只会滚页面。这里把阈值压到 2（panSlop 随之 = 4），靠先拿到
/// arena 赢下与滚动视图的竞争；**只包宫格自己的子树**，祖先读的是它自己的 MediaQuery，
/// 滚动视图不受影响。鼠标不受此限（`computePanSlop(mouse)` 恒为 `kPrecisePointerPanSlop`）。
const double kHomeGridEditTouchSlop = 2;

/// 被挤开 / 被顶开的卡片滑到新位置的时长。
///
/// 用户 2026-09-21 十二轮：「我希望添加碰撞移动的功能，就是像手机桌面一样，既要支持合并
/// 也要支持把卡片挤开」—— 手机桌面上被压到的图标是**立刻滑开**的，不是等到松手才跳过去。
/// 拖动过程中落点方案每跨一格才变一次，所以这里只负责把那一跳补成一小段滑动。
const Duration kHomeGridSlideDuration = Duration(milliseconds: 180);

/// 服务宫格。
class HomeServiceGrid extends StatefulWidget {
  /// 目录条目（顺序 = 默认铺排顺序；聚合布局按标题与它们对齐）。
  final List<HomeServiceEntry> entries;

  /// 已保存的聚合布局；null = 还没自定义过 → 按目录顺序流式铺。
  final HomeGridLayout? layout;

  /// 拖动 / 合并产生新布局时回调（调用方负责落盘）。
  final ValueChanged<HomeGridLayout>? onLayoutChanged;

  /// 编辑模式（原名「拆解模式」，用户 2026-09-21 九轮改口径）：画分割线、点缝断开 / 接回
  /// （退出时把真分开的缝落盘），并且**拖动不必长按**（按下即拖 / 点击拿起再点放下）。
  final bool editMode;

  const HomeServiceGrid({
    super.key,
    required this.entries,
    this.layout,
    this.onLayoutChanged,
    this.editMode = false,
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

  /// 编辑模式里被剪断的缝（**只在编辑模式期间存在**，退出时结算：真分开的落盘）。
  Set<GridSeam> _cuts = <GridSeam>{};

  /// 起手抓住的格子（相对卡片包围盒左上角）。
  GridCell _grabCell = (x: 0, y: 0);

  /// 起手时指针相对卡片左上角的像素偏移（抬起的那张卡跟着手指走）。
  Offset _grabPixel = Offset.zero;

  /// 编辑模式：这一次按下时指针的位置。
  ///
  /// 编辑模式用 pan 起手，而 pan 要等指针**移过一个阈值**才 `onPanStart`（那时已经离
  /// 按下的地方有段距离了）—— 抓手偏移要按**按下那一刻**算，否则整张卡会相对手指错位
  /// 一整个阈值的距离（[kHomeGridEditTouchSlop] 就是为此存在的）。
  Offset? _pressGlobal;

  /// 手上这件东西是**点一下拿起来的**（而不是 pan 拖起来的）。
  ///
  /// ⚠ 必须区分，否则「点击拿起 → 再点一下放下」的第二下会失灵：同一次按下里 tap 与 pan
  ///   一起进 arena，指针抬起时 pan 先被拒（`_giveUpPointer` → `resolvePointer(rejected)`
  ///   → `onPanCancel`），而 tap 要等 arena sweep 才拿到 `onTapUp` —— 也就是说
  ///   `onPanCancel` **先于** `onTapUp` 到达。若不区分，`_cancelDrag` 会先把「刚拿起的」
  ///   东西清掉、紧接着 `_tapGrab` 又把它拿起来（实测：点第二下反而重新拿起，卡片放不下）。
  bool _tapPicked = false;

  /// 指针在网格内的位置。
  Offset? _pointerLocal;

  /// 网格里**正有指针按着**（任何键、任何设备）。
  ///
  /// 只为一件事服务：悬停提示（用户 2026-09-21 十轮「如果是鼠标按下的状态，则不显示」）。
  /// 单靠 [_dragKey] 不够 —— 按下但还没起手拖动的那段时间里，鼠标滑到别的功能上仍然会
  /// 进悬停、`waitDuration` 一到就弹。按下时把脸的 [HomeGridTileFace.showTooltip] 关掉，
  /// 悬停那一刻读到的是 [kHomeGridTooltipSuppressed] → 等于不显示。
  bool _pointerDown = false;

  /// 当前落点方案（null = 松手什么都不会发生 → 不画虚线框）。
  HomeGridDropTarget? _plan;

  @override
  void didUpdateWidget(covariant HomeServiceGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.editMode && widget.editMode) {
      // 进入编辑模式：从「全都连着」开始，每次进来都是新的一轮。
      _cuts = <GridSeam>{};
    } else if (oldWidget.editMode && !widget.editMode) {
      // 退出编辑模式：手上还拿着的那张**就地放下**（= 取消，不落盘），
      // 只有真把卡片分成两块的缝留下，其余接回去。
      // ⚠ 不能在 `didUpdateWidget` 里**同步**回调 `onLayoutChanged` —— 此刻父级正在
      //   build（当前构建目标是宫格下面的手势识别器），父级 setState 会被框架拒：
      //   `setState() or markNeedsBuild() called during build`。挪到帧末再回调。
      // ⚠ 也不能 `setState` —— 这里本来就在 build 里，直接改字段即可（本次 build 就会用上）。
      _clearDrag();
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
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final metrics = HomeGridMetrics.of(constraints.maxWidth);
        final saved = _savedLayout(metrics);
        final layout = _displayLayout(metrics, saved);
        final seams = hgTileSeams(saved);
        // 编辑模式里被剪开的碎块（不在已保存布局里 = 它是拆出来的一块）→ 画红色虚线轮廓。
        // 用户 2026-09-21 十一轮：「点击分割线后立刻分开，而不是只高亮分割线」—— 模型层面
        // 本来就立刻分开了，但卡片纯白、页面底也是纯白，12px 格缝肉眼看不出来，所以给每一块
        // 换成虚线轮廓（同一条缝断开后画的那条红虚线同款）。
        final pieceKeys = <String>{
          for (final t in layout.tiles)
            if (saved.tileByKey(t.key) == null) t.key,
        };
        final plan = _plan;
        final dragTile = _dragTile;
        final pointer = _pointerLocal;
        // **挤开预览**：落点方案松手后会落到哪，卡片就先滑到哪 —— 直接拿 `plan.apply`
        // 的结果做差（它就是 `_finishDrag` 真正落盘的那份布局），预览与结果因此**不可能对不上**，
        // 连锁挤开 / 挤不动退回让位这些分支也不用各写一遍。用户 2026-09-21 十二轮：
        // 「我希望添加碰撞移动的功能，就是像手机桌面一样，既要支持合并也要支持把卡片挤开」。
        final pushedAt = <String, HomeGridTile>{};
        if (plan != null) {
          for (final moved in plan.apply(_baseLayout(metrics)).tiles) {
            if (moved.key == plan.sourceKey) continue; // 被拖的那张走「抬起 + 幽灵卡」
            final now = layout.tileByKey(moved.key);
            if (now == null) continue;
            if (gridShapeKey(now.cells) == gridShapeKey(moved.cells)) continue;
            pushedAt[moved.key] = moved;
          }
        }
        return SizedBox(
          key: _gridKey,
          height: metrics.heightOfRows(layout.rows),
          // 只做一件事：记住「网格里有没有指针按着」（见 [_pointerDown]）。
          // [Listener] 不参与手势竞技场、也不吃事件（translucent），纯粹旁观。
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _setPointerDown(true),
            onPointerUp: (_) => _setPointerDown(false),
            onPointerCancel: (_) => _setPointerDown(false),
            child: Stack(
              // 抬起的卡片 / 虚线框可以画到网格外面（长按拖到上方时不该被切掉）。
              clipBehavior: Clip.none,
              children: [
                // 编辑模式：点空白处 = 把手上拿着的放下（垫在最底下 → 只有没点到任何卡片 /
                // 分割线时才轮得到它；没拿着东西时是空操作）。
                if (widget.editMode)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('homeGridEditBackground'),
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (d) => _tapDrop(d.globalPosition),
                      child: const SizedBox.expand(),
                    ),
                  ),
                for (final tile in layout.tiles)
                  _card(
                    // **挤开预览**：落点方案里被挤开 / 被顶开的卡片当场滑到新位置（用户
                    // 2026-09-21 十二轮：「就是像手机桌面一样」—— 手机桌面上被压到的图标是
                    // **立刻**让开的，不是等到松手才跳）。位置变、卡片 key 不变 → Element
                    // 不重建，手势识别器不受影响（本模块的老坑，见 `_card` 结尾的注释）。
                    pushedAt[tile.key] ?? tile,
                    metrics,
                    byTitle,
                    hidden: tile.key == _dragKey,
                    dashedPiece: pieceKeys.contains(tile.key),
                  ),
                if (widget.editMode)
                  for (final seam in seams)
                    _seamHandle(seam.seam, metrics, context)
                else
                  // 卡片其余部分（格与格之间的缝）= 拖整张卡的手势带；透明命中，
                  // 轻点仍然穿透到下面那张脸（只有长按才起手）。
                  // ⚠ 拖动中**不能**把这些手势带从树里摘掉 —— 摘掉会让长按识别器随
                  //   Element 一起 dispose，move / end 再也送不到（卡片卡在半空、松手没反应）。
                  for (final seam in seams)
                    _bodyHandle(seam.tile, seam.seam, metrics),
                if (plan != null) ...hgPreview(plan, metrics, context),
                if (dragTile != null && pointer != null)
                  _lifted(dragTile, metrics, byTitle, pointer),
                // 编辑模式：鼠标在网格上移动 → 「拿起」的那张卡与落点虚线框跟着走
                // （触摸端没有 hover，靠最后一次点击位置；见 [_tapDrop]）。
                // ⚠ [MouseRegion] 用 translucent + opaque:false：它**不许**吃掉指针事件
                //   （卡片 / 分割线还在它下面），也不许挡住下面的 hover 标注（分割线的
                //   手型光标）。仅作旁观者：命中路径里有它 → 收得到 onHover。
                if (widget.editMode)
                  Positioned.fill(
                    child: MouseRegion(
                      key: const Key('homeGridEditHover'),
                      hitTestBehavior: HitTestBehavior.translucent,
                      opaque: false,
                      onHover: (e) => _updateDrag(e.position),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!widget.editMode) return grid;
    // 编辑模式：把宫格自己的手势滑动阈值压小（见 [kHomeGridEditTouchSlop]），
    // 免得「按下即拖」被祖先滚动视图的 18px 阈值抢走。**只包自己的子树**。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        gestureSettings: const DeviceGestureSettings(
          touchSlop: kHomeGridEditTouchSlop,
        ),
      ),
      child: grid,
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

  /// 渲染布局 = 已保存布局 +（编辑模式）把剪断的缝两侧拆成各自的卡。
  ///
  /// ⚠ 拖单格时**不在这里**把那一格抠出来：抠格会让源卡片的 key 变掉（原卡换成
  ///   「抠出来那格 + 剩下的部分」）→ 那张卡的手势识别器随 Element 一起 dispose →
  ///   move / end 再也送不到（宫格拖动踩过两次的同款坑）。抠格只体现在抬起的卡
  ///   （[_dragTile]）与落点方案（[_baseLayout]）上，松手才真的改写布局。
  ///   源卡片「少一格」的**视觉**靠 [HomeGridCard.skinCells] 实现（形状变、key 不变）。
  HomeGridLayout _displayLayout(HomeGridMetrics metrics, HomeGridLayout saved) {
    final cuts = _cuts;
    if (!widget.editMode || cuts.isEmpty) return saved;
    return HomeGridLayout(
      cols: saved.cols,
      tiles: homeGridSplitAll(saved.tiles, cuts),
    );
  }

  Widget _card(
    HomeGridTile tile,
    HomeGridMetrics metrics,
    Map<String, HomeServiceEntry> byTitle, {
    bool hidden = false,
    bool dashedPiece = false,
  }) {
    final topLeft = metrics.topLeftOfTile(tile);
    final size = metrics.sizeOfTile(tile);
    final content = homeGridFaceContentPadding(compact: metrics.compact);
    // 拖单格时，源卡片的那一格：脸不画（用户 2026-09-21 十轮），并且**形状也跟着让位**
    // （用户 2026-09-21 十一轮：「不只是功能不显示，而是卡片形状也要改变」）。只认
    // 「被抠出来的那张卡」—— 抬起的幽灵卡有自己的 key，不受影响。
    final extracted = _extractCell;
    final fromThis = _extractFrom == tile.key && extracted != null;
    final blankCells = fromThis ? <GridCell>{extracted} : const <GridCell>{};
    // 十一轮口径：抬起的那个功能**还压在自己的原格子上** → 源卡片画「原来完整轮廓」的
    // 虚线（放回来就是这个形状）；已经挪到别处 → 直接画「去掉这一格」的实心形状。
    final atHome = fromThis && _extractedAtHome;
    final skinCells = fromThis && !atHome
        ? <GridCell>{
            for (final c in tile.cells)
              if (c != extracted) c,
          }
        : null;
    final card = HomeGridCard(
      key: Key('homeGridCard-${tile.key}'),
      tile: tile,
      metrics: metrics,
      entriesByTitle: byTitle,
      blankCells: blankCells,
      skinCells: skinCells,
      // 虚线轮廓两种来源（见 [HomeGridCard.dashedOutline]）：功能还在原位的「放回来还是这个
      // 形状」预览，以及编辑模式里被剪开、拆出来的碎块。
      dashedOutline: atHome || dashedPiece,
      // 悬停提示：按着 / 拖着东西时不弹（见 [_pointerDown]）。
      showTooltip: !_pointerDown && _dragKey == null,
      // 抓取手势挂在**每一格的脸**上（而不是整张卡的包围盒上）：
      // ① 异形卡片的包围盒里可能有别人嵌进来的格子，挂在外框上会把那格的手势吞掉；
      // ② 用户 2026-09-21 四轮：「长按到功能部分时，只移动此功能」→ 抓某一格 = 拖这一格。
      //
      // ⚠ **抓取区只覆盖功能的内容块**（用户 2026-09-21 六轮：「我们希望每个卡片内，
      //   功能的点击区不要太大，不然就很难移动整个卡片」）：脸的视觉照旧占满整格（轻点
      //   整格都能打开功能），但「拖这一个功能」只在内容块（图标 / 标题 / 副标题
      //   那一块，`homeGridFaceContentPadding`）里生效；格子四周那一圈留给「卡片其余部分」
      //   （[bodyWrapper]）= 拖整张卡。桌面 212×88 的一格：内容块 180×56，四周 16px
      //   的圈；相邻两个功能的内容块之间因此有 16 + 12 + 16 = 44px 的整卡抓取走廊。
      //
      //   抓取区用 [HitTestBehavior.translucent] 而不是 opaque：普通模式下轻点要**继续
      //   穿透**到下面那张脸的 `InkWell`（水波纹 / hover 高亮 / 打开功能都还得是整格可用）。
      //   起手（长按 / pan）则是抓取区（在 hit-test 结果里更靠前）与卡片手势层抢同一个
      //   识别器，前者先入 arena 胜出 —— 这与缝上那条带压着脸的既有机制同款。
      //
      // ⚠ 三个手势层的**层序**（同格内自上而下：抓取区 → 卡片其余部分 → 脸）：
      //   ① 脸的 `InkWell` 是 `HitTestBehavior.opaque`，会把手势吞在它自己身上 ——
      //      「空白处」那一层必须**压在脸之上**才能收到手势（先写在脸下面，实测长按
      //      不起手、`homeGridLifted` 根本不出现）；
      //   ② 抓取区又必须**压在卡片那一层之上**：两层都是 translucent，会一起进入
      //      arena，靠 hit-test 顺序（topmost 先入 arena）让「拖功能」赢过「拖整卡」。
      faceWrapper: (entry, cell, face) => Stack(
        children: [
          // 编辑模式里功能**点不动**（用户 2026-09-21 七轮：「处于分割状态下，功能不能被
          // 点击」）：模式内点一下只该是「拿起这一格 / 断开接回这条缝」，误点到功能会直接
          // 跳走、把正在编辑的布局丢在半路。用 [IgnorePointer] 而不是把 `onTap` 置空 ——
          // 连带水波纹 / hover 高亮一起静默，视觉上也看得出「现在在编辑布局」。
          Positioned.fill(
            child: IgnorePointer(ignoring: widget.editMode, child: face),
          ),
          // 「卡片其余部分」= 这一格（普通模式长按 / 编辑模式按下即拖 → 拖整张卡）。它整格
          // 覆盖，但抓取区压在它上面，所以实际只有「内容块之外的那一圈」会走到这里；
          // 普通模式下轻点照旧穿透到脸。
          _grabLayer(
            key: Key('homeGridCardBody-${entry.title}'),
            tile: tile,
            cell: null,
          ),
          // 功能自己的抓取区 = 内容块（图标 / 标题 / 副标题那块 → 只拖 / 只拿起这一个功能）。
          Positioned.fill(
            child: Padding(
              padding: content,
              child: _grabLayer(
                key: Key('homeGridGrip-${entry.title}'),
                tile: tile,
                cell: cell,
              ),
            ),
          ),
        ],
      ),
    );
    return AnimatedPositioned(
      // 位置变化（挤开 / 顶开）走一小段滑动，像手机桌面那样「滑过去」而不是跳过去。
      duration: kHomeGridSlideDuration,
      curve: Curves.easeOut,
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

  /// 一个「抓取层」（用户 2026-09-21 九轮：「拖动功能不需要长按，按下即可拖动，或者点击
  /// 拿起，再次点击方下」）。
  ///
  /// - **普通模式**：长按起手（老口径 —— 长按不动的其它地方就是轻点打开功能）；
  /// - **编辑模式**：`pan` 起手 = **按下即拖**（不再等长按），并且挂 `onTapUp` =
  ///   点一下**拿起**、已经拿着时点一下**放下**。
  ///
  /// [cell] = 这一层负责的那一格（功能内容块 → 拖 / 拿起**这一个功能**）；null = 「卡片其余
  /// 部分」（拖 / 拿起**整张卡**）。两层都是 [HitTestBehavior.translucent]，轻点在普通模式下
  /// 继续穿透到脸的 `InkWell`；编辑模式下脸被 [IgnorePointer] 挡住，所以点击都落到这两层。
  Widget _grabLayer({
    required Key key,
    required HomeGridTile tile,
    required GridCell? cell,
  }) {
    if (!widget.editMode) {
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (d) => _startDrag(tile, cell, d.globalPosition),
        onLongPressMoveUpdate: (d) => _updateDrag(d.globalPosition),
        onLongPressEnd: (_) => _finishDrag(),
        onLongPressCancel: _cancelDrag,
        child: const SizedBox.expand(),
      );
    }
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.translucent,
      // 按下就记住位置：pan 真正起手时指针已经移过一个阈值了，抓手偏移得按**按下那一刻**
      // 算，否则卡片与手指错位一整个阈值的距离。
      onPanDown: (d) => _pressGlobal = d.globalPosition,
      onPanStart: (d) {
        _startDrag(tile, cell, _pressGlobal ?? d.globalPosition);
        _updateDrag(d.globalPosition);
      },
      onPanUpdate: (d) => _updateDrag(d.globalPosition),
      onPanEnd: (_) => _finishDrag(),
      onPanCancel: _cancelDrag,
      onTapUp: (d) => _tapGrab(tile, cell, d.globalPosition),
      child: const SizedBox.expand(),
    );
  }

  /// 编辑模式的分割线：**没断开** = 卡片描边同色的细实线；**断开了** = 主题红虚线
  /// （用户口径 2：「因此形成的边界，暂时显示为虚线」）。点一下切换断开 / 接回。
  ///
  /// ⚠ 手上**拿着东西**时点分割线 = 在线的位置把东西放下（用户 2026-09-21 九轮的口径：
  ///   拿着东西时点一下一律先放下），不切换断开 —— 否则「拿起 → 点到缝上」会顺手改坏
  ///   卡片的分卡方式。
  Widget _seamHandle(
    GridSeam seam,
    HomeGridMetrics metrics,
    BuildContext context,
  ) {
    final cut = _cuts.contains(seam);
    final band = hgSeamBand(seam, metrics);
    final (a, b) = hgSeamLine(
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
        onTapUp: (d) {
          if (_dragKey != null) {
            _tapDrop(d.globalPosition);
            return;
          }
          _toggleCut(seam);
        },
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

  /// 普通模式：**卡片其余部分**在缝上的补充手势带 = 拖整张卡（与卡片自己的
  /// [HomeGridCard.bodyWrapper] 同动作，见 [kHomeGridSeamHitPad] 的说明）。
  /// 透明命中（[HitTestBehavior.translucent]）→ 轻点仍穿透到下面那张脸，只有长按才起手。
  Widget _bodyHandle(HomeGridTile tile, GridSeam seam, HomeGridMetrics metrics) {
    final band = hgSeamBand(seam, metrics);
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

  /// 剪断 / 接回一条缝（编辑模式）。
  void _toggleCut(GridSeam seam) {
    setState(() {
      if (!_cuts.add(seam)) _cuts.remove(seam);
    });
    unawaited(HapticFeedback.selectionClick());
  }

  /// 退出编辑模式：**只有真把卡片分成两块的缝才落盘**，绕路还连着的接回去
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
              // 幽灵卡永远在指针底下 → 悬停提示必须关掉，否则拖到一半会在手指上弹出来。
              showTooltip: false,
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

  /// 网格里按下 / 松开一个指针 → 更新 [_pointerDown]（只为此重建，见字段文档）。
  void _setPointerDown(bool down) {
    if (_pointerDown == down) return;
    setState(() => _pointerDown = down);
  }

  /// 手上那个功能**是不是还压在自己的原格子上**（用户 2026-09-21 十一轮）。
  ///
  /// 判据 = 抬起那张卡此刻占的格子（指针所在格 − 抓手格）是否等于它被抠出来的那一格。
  /// 决定源卡片画哪种形状（见 [_card]）：还在原位 → 原来完整轮廓的**虚线**；挪到别处 →
  /// 去掉这一格的**实心**形状。拿不到几何 / 没有指针时按「还在原位」处理 —— 那正是刚拿起
  /// 来的状态，宁可多画一次虚线，也别让卡片先闪一下「少了一格」的实心形状。
  bool get _extractedAtHome {
    final cell = _extractCell;
    if (cell == null) return true;
    final local = _pointerLocal;
    final metrics = _metricsOf();
    if (local == null || metrics == null) return true;
    final under = metrics.cellAt(local);
    return under.x - _grabCell.x == cell.x && under.y - _grabCell.y == cell.y;
  }

  /// 起手拖动。[cell] = 抓住的那一格（拖**这一个功能**）；null = 抓在「卡片其余部分」
  /// （缝）上 → 拖**整张卡**（用户口径 3）。[byTap] = 这是「点一下拿起」（不是拖起来的）。
  void _startDrag(
    HomeGridTile tile,
    GridCell? cell,
    Offset global, {
    bool byTap = false,
  }) {
    if (_dragKey != null) return; // 已经在拖了（多指按下时忽略后来者）
    final box = _gridBox();
    final metrics = _metricsOf();
    if (box == null || metrics == null) return;
    final effective = cell == null ? tile : homeGridExtractCell(tile, cell).moved;
    final local = box.globalToLocal(global);
    final grab = local - metrics.topLeftOfTile(effective);
    // 起手那一刻就收掉已经挂着的悬停提示（框架在 PointerDown 时也会收一次，这里是双保险：
    // 「点一下拿起」是**抬起**之后才起手的，那一刻没有 PointerDown）。
    Tooltip.dismissAllToolTips();
    setState(() {
      _extractFrom = cell == null ? null : tile.key;
      _extractCell = cell;
      _dragKey = effective.key;
      _dragTile = effective;
      _grabPixel = grab;
      _pointerLocal = local;
      _tapPicked = byTap;
      _syncPlan(metrics, effective, local, grab);
    });
    unawaited(HapticFeedback.mediumImpact());
  }

  /// 编辑模式：点击 = **拿起** / 已经拿着时 = **放下**（用户 2026-09-21 九轮原话：
  /// 「或者点击拿起，再次点击方下」）。
  void _tapGrab(HomeGridTile tile, GridCell? cell, Offset global) {
    if (_dragKey == null) {
      _startDrag(tile, cell, global, byTap: true);
      return;
    }
    _tapDrop(global);
  }

  /// 把手上拿着的那张卡 / 那个功能放到 [global] 处（编辑模式的「再点一下放下」）。
  ///
  /// 落点优先用拖动那套（[homeGridPlanDrop]：贴边 → 合并、空格 → 移动，虚线框一直显示
  /// 的就是它）；指针压在**别的卡片中间 / 内缝**时拖动版没有方案，这里退化成一次纯移动
  /// （[homeGridPlanTapDrop]）。点回自己原来的位置 = 指纹不变 → 什么都不写（等于取消）。
  void _tapDrop(Offset global) {
    if (_dragKey == null) return;
    final box = _gridBox();
    final metrics = _metricsOf();
    final tile = _dragTile;
    if (box == null || metrics == null || tile == null) {
      _cancelDrag();
      return;
    }
    final local = box.globalToLocal(global);
    final cell = metrics.cellAt(local);
    setState(() {
      _pointerLocal = local;
      _syncPlan(metrics, tile, local, _grabPixel);
      _plan ??= homeGridPlanTapDrop(
        layout: _baseLayout(metrics),
        draggedKey: tile.key,
        pointerCell: cell,
        grabCell: _grabCell,
      );
    });
    _finishDrag();
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
    // ⚠ **结果与基准一样 = 这一次拖动什么都没改**（长按不动就松手；或者拖出去又拖回来），
    //   此时**不许回调** —— 否则「长按某一格不动就松手」也会把那张卡拆成「这一格 + 其余」
    //   两张（`_baseLayout` 已经把这一格抠出来了，落点又把它放回原处 → 分卡方式变了、
    //   服务位置没变）。真机上实测：原地长按一下，存档就多一次改写。
    //
    // ⚠ 但**合并永远不能走这条早退**（用户 2026-09-21 八轮：「现在合并会有问题，始终合并
    //   不起来」）：把两张**相邻**的卡并起来时，每个服务占的格子一格都没动（A@0,0 与 B@1,0
    //   并成一张卡后还是 A@0,0、B@1,0）—— 语义指纹看不出差别，可它恰恰是一次货真价实的
    //   合并（分卡方式变了）。合并一定改变分卡方式，所以 `isMerge` 直接放行。
    if (!plan.isMerge && _layoutSignature(next) == _layoutSignature(before)) return;
    notify(next);
    if (plan.isMerge) _announceMerge(plan, before, notify);
  }

  /// 布局的**语义指纹**：每个服务 → 它占的那一格。
  ///
  /// 用于判断「这次拖动到底改没改动布局」。不能直接比 `HomeGridLayout`：它的值相等连
  /// **分卡方式**与**卡片顺序**一起比，而拖单格的基准布局里那一格已经被抠成单独一张卡
  /// （`_baseLayout`），落点再把它放回原处就会出现「服务位置全一样、值却不相等」。
  static String _layoutSignature(HomeGridLayout layout) {
    final parts = <String>[];
    for (final tile in layout.tiles) {
      final n = math.min(tile.titles.length, tile.cells.length);
      for (var i = 0; i < n; i++) {
        final c = tile.cells[i];
        parts.add('${tile.titles[i]}@${c.x},${c.y}');
      }
    }
    parts.sort();
    return parts.join('|');
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

  /// pan 被拒（= 这一下其实是个点击）时回调。
  ///
  /// ⚠ **只清「拖起来的」那一次拖动**：点一下拿起的东西要留在手上等第二下（见 [_tapPicked]
  ///   的说明 —— 同一次抬起里 `onPanCancel` 先于 `onTapUp` 到达）。
  void _cancelDrag() {
    if (_dragKey == null || _tapPicked) return;
    setState(_clearDrag);
  }

  void _clearDrag() {
    _dragKey = null;
    _dragTile = null;
    _extractFrom = null;
    _extractCell = null;
    _plan = null;
    _pointerLocal = null;
    _pressGlobal = null;
    _tapPicked = false;
    _grabPixel = Offset.zero;
    _grabCell = (x: 0, y: 0);
  }
}
