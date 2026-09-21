/// 宫格形状（多联骨牌）的纯几何工具。
///
/// 用户 2026-09-21 需求（首页宫格聚合）原话：
/// 「宫格可以异形，长按拖动到其他卡片边边上时（必须要在某个边缘处，处于中间则此次
/// 拖动松手后不触发合并），松手后，合并到此边相邻的位置 …… 并且要允许两个互补的
/// 卡片相互嵌套，例如一正一反两个大写 F 形的卡片可以相互插入空隙」。
///
/// 因此宫格排版不再是 `Wrap` 的「一行一行等宽等高」，而是**格子坐标上的自由形状**：
/// - 坐标单位 = 格子（列 `x` 向右、行 `y` 向下），与像素无关（像素换算在
///   `presentation/home_grid_metrics.dart`）；
/// - 形状 = 一组**四邻连通**的格子（`Set<GridCell>` 语义），允许 L 形 / F 形这类
///   异形，也允许「A 的空缺正好由 B 填满」的互补嵌套；
/// - 本文件只做集合运算与轮廓提取（[gridOutlineLoops]），不关心「哪个格子放的是哪个
///   服务」（那是 `home_grid_layout.dart` 的 `HomeGridTile`）。
library;

/// 宫格格子（record：结构相等 + `hashCode` 由语言免费提供，
/// 可直接当 `Set`/`Map` 的键 —— 手写类要自己实现 `==`/`hashCode`，易错且冗长）。
typedef GridCell = ({int x, int y});

/// 格子范围（左闭右闭：`left..right` × `top..bottom`）。
typedef GridBounds = ({int left, int top, int right, int bottom});

/// 造一个格子。
GridCell gridCell(int x, int y) => (x: x, y: y);

/// 行优先比较（先比行 `y`、再比列 `x`）—— 全仓「阅读序」的唯一口径。
int gridCompare(GridCell a, GridCell b) {
  final byRow = a.y.compareTo(b.y);
  return byRow != 0 ? byRow : a.x.compareTo(b.x);
}

/// 行优先排序后的新列表（**不改入参**）。
List<GridCell> gridSorted(Iterable<GridCell> cells) =>
    List<GridCell>.of(cells)..sort(gridCompare);

/// 去重后的格子集合。
Set<GridCell> gridCellSet(Iterable<GridCell> cells) => Set<GridCell>.of(cells);

/// 形状的范围；空集合返回 `(0,0,-1,-1)`（宽高为 0，调用方自己判空）。
GridBounds gridBoundsOf(Iterable<GridCell> cells) {
  var left = 0;
  var top = 0;
  var right = -1;
  var bottom = -1;
  var first = true;
  for (final c in cells) {
    if (first) {
      first = false;
      left = c.x;
      right = c.x;
      top = c.y;
      bottom = c.y;
      continue;
    }
    if (c.x < left) left = c.x;
    if (c.x > right) right = c.x;
    if (c.y < top) top = c.y;
    if (c.y > bottom) bottom = c.y;
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

/// 范围宽度（格数；空集合为 0）。
int gridWidthOf(GridBounds b) => b.right - b.left + 1;

/// 范围高度（格数；空集合为 0）。
int gridHeightOf(GridBounds b) => b.bottom - b.top + 1;

/// 平移（**不改入参**；保持传入顺序）。
List<GridCell> gridTranslated(Iterable<GridCell> cells, int dx, int dy) => [
  for (final c in cells) (x: c.x + dx, y: c.y + dy),
];

/// 两个格子是否共边相邻。
bool gridNeighbours(GridCell a, GridCell b) {
  final dx = (a.x - b.x).abs();
  final dy = (a.y - b.y).abs();
  return dx + dy == 1;
}

/// 形状是否四邻连通（空集合 = false）。
///
/// 合并后的形状**必须连通**，否则会出现「一张卡片两坨、中间隔着别人」的怪状态。
bool gridConnected(Iterable<GridCell> cells) {
  final set = gridCellSet(cells);
  if (set.isEmpty) return false;
  final start = set.first;
  final seen = <GridCell>{start};
  final queue = <GridCell>[start];
  while (queue.isNotEmpty) {
    final c = queue.removeLast();
    for (final n in <GridCell>[
      (x: c.x + 1, y: c.y),
      (x: c.x - 1, y: c.y),
      (x: c.x, y: c.y + 1),
      (x: c.x, y: c.y - 1),
    ]) {
      if (set.contains(n) && seen.add(n)) queue.add(n);
    }
  }
  return seen.length == set.length;
}

/// 两个形状是否**共边相接**（至少存在一对相邻格子）。
bool gridTouching(Iterable<GridCell> a, Iterable<GridCell> b) {
  final setB = gridCellSet(b);
  for (final c in a) {
    if (setB.contains((x: c.x + 1, y: c.y)) ||
        setB.contains((x: c.x - 1, y: c.y)) ||
        setB.contains((x: c.x, y: c.y + 1)) ||
        setB.contains((x: c.x, y: c.y - 1))) {
      return true;
    }
  }
  return false;
}

/// 两个形状是否有重叠格子。
bool gridOverlaps(Iterable<GridCell> a, Iterable<GridCell> b) {
  final setA = gridCellSet(a);
  for (final c in b) {
    if (setA.contains(c)) return true;
  }
  return false;
}

/// 形状的规范指纹（行优先 + `x,y;x,y`）—— 用于判等 / 当 `Map` 键 / 测试断言。
String gridShapeKey(Iterable<GridCell> cells) =>
    gridSorted(cells).map((c) => '${c.x},${c.y}').join(';');

/// 两个形状的格子集合是否完全一致（顺序无关）。
bool gridSameShape(Iterable<GridCell> a, Iterable<GridCell> b) =>
    gridShapeKey(a) == gridShapeKey(b);

/// 形状的**轮廓环**（多联骨牌的边界折线；坐标 = 格子的**角点**，单位 = 格子）。
///
/// 为什么需要它：异形卡片的轮廓此前是「逐格画圆角矩形再做布尔并」，而格子之间隔着
/// 12px 格缝 —— 并集在拐弯的**内侧**会在格缝交叉处留下一个 12×12 的方角突起
/// （用户 2026-09-21 原话：「卡片在拐弯的时候，内侧会有一个突起，我希望做成圆角」）。
/// 正确姿势 = 先取轮廓环，再把每个 90° 转角（凸角收圆 + **凹角倒圆**）用圆弧连接。
///
/// 方向约定：每条有向边都让**形状内部落在前进方向的右手边**，于是外环在屏幕坐标
/// （y 向下）下是顺时针、洞是逆时针 —— `Path` 的非零填充据此自动把洞挖空。
///
/// 入参必须是**四邻连通**的格子集合（[gridConnected]；卡片不变式保证），此时每个角点
/// 至多一进一出，走链是确定的；返回的每个环都过了共线简化（[gridSimplifyLoop]），
/// 因此只有**真正的转角**留在里面。
List<List<GridCell>> gridOutlineLoops(Iterable<GridCell> cells) {
  final set = gridCellSet(cells);
  if (set.isEmpty) return const <List<GridCell>>[];
  // 起点 → 终点（同一角点可能既是一条边的终点、又是另一条边的起点）。
  final outs = <GridCell, List<GridCell>>{};
  void addEdge(GridCell from, GridCell to) =>
      (outs[from] ??= <GridCell>[]).add(to);
  for (final c in gridSorted(set)) {
    if (!set.contains((x: c.x, y: c.y - 1))) {
      addEdge((x: c.x, y: c.y), (x: c.x + 1, y: c.y)); // 上边：向右
    }
    if (!set.contains((x: c.x + 1, y: c.y))) {
      addEdge((x: c.x + 1, y: c.y), (x: c.x + 1, y: c.y + 1)); // 右边：向下
    }
    if (!set.contains((x: c.x, y: c.y + 1))) {
      addEdge((x: c.x + 1, y: c.y + 1), (x: c.x, y: c.y + 1)); // 下边：向左
    }
    if (!set.contains((x: c.x - 1, y: c.y))) {
      addEdge((x: c.x, y: c.y + 1), (x: c.x, y: c.y)); // 左边：向上
    }
  }
  final loops = <List<GridCell>>[];
  // 链一定闭合（连通性保证），上限只是防御 —— 万一脏数据让链断开，不至于死循环。
  var guard = 4 * set.length + 8;
  while (outs.isNotEmpty && guard-- > 0) {
    final start = outs.keys.first;
    final loop = <GridCell>[];
    var at = start;
    while (true) {
      final ends = outs[at];
      if (ends == null || ends.isEmpty) break;
      final to = ends.removeAt(0);
      if (ends.isEmpty) outs.remove(at);
      loop.add(at);
      at = to;
      if (at == start) break;
    }
    if (loop.length >= 4) loops.add(gridSimplifyLoop(loop));
  }
  return loops;
}

/// 去掉轮廓折线上**共线的中间点**（同一方向连着走几格 → 只留两端）。
///
/// 输入是「每格一条边」的原始链（每个格子转角处都有点），输出只保留真正的转角；
/// 顺带把「直角折线」变成最短表达，出弧时的半径上限也才好算。
List<GridCell> gridSimplifyLoop(List<GridCell> loop) {
  final n = loop.length;
  if (n < 3) return List<GridCell>.of(loop);
  final out = <GridCell>[];
  for (var i = 0; i < n; i++) {
    final prev = loop[(i - 1 + n) % n];
    final cur = loop[i];
    final next = loop[(i + 1) % n];
    final cross =
        (cur.x - prev.x) * (next.y - cur.y) -
        (cur.y - prev.y) * (next.x - cur.x);
    if (cross != 0) out.add(cur);
  }
  return out.isEmpty ? List<GridCell>.of(loop) : out;
}
