/// 宫格聚合的「连接 / 断开」口径（拆解模式 + 长按功能部分单拖）。
///
/// 用户 2026-09-21 四轮原话：
/// 1. 「我希望功能与功能之间不显示分割线」；
/// 2. 「我希望可以进入拆解模式，此模式下，才显示分割线，点击分割线后，此边处不连接，
///    分成两部分，因此形成的边界，暂时显示为虚线。退出拆解模式时，如果有些分割线分开
///    的两边没有分开（还在其他地方相连），则恢复此处连接。」；
/// 3. 「然后长按卡片也分为长按到功能部分，和卡片其余部分，前者不再移动整个卡片，而是
///    改成后者移动整个卡片，长按到功能部分时，只移动此功能，同样要用虚线展示预期效果」。
///
/// 模型：一张卡 = 一组格子 + 一组**缝**（相邻两格之间的连接）。
/// - 剪断一条缝 → 卡片按「还连着的缝」分成若干连通块，每块独立成卡（本文件 [gridComponents]
///   / [homeGridSplitTile]）；
/// - 剪断的缝**不一定真的分开**：两边还可能绕过别处连着 —— 退出拆解模式时只有真的把卡片
///   分成两块的缝才留下（[homeGridEffectiveCuts]），其余原样接回去（用户口径 2）；
/// - 缝的身份 = 两格坐标（[gridSeam] 规范化成有序对），所以**不需要卡片的 key 参与**，
///   界面层的暂存集合就是 `Set<GridSeam>`。
library;

import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';

/// 一条缝 = 同一张卡里两个**相邻**格子之间的连接。
typedef GridSeam = ({GridCell a, GridCell b});

/// 规范化一条缝（字典序小的当 `a`），让它与遍历顺序无关。
GridSeam gridSeam(GridCell a, GridCell b) =>
    gridCompare(a, b) <= 0 ? (a: a, b: b) : (a: b, b: a);

/// 缝的稳定字符串（widget key / 测试断言用）。
String gridSeamKey(GridSeam seam) =>
    '${seam.a.x},${seam.a.y}-${seam.b.x},${seam.b.y}';

/// 一组格子里**所有**相邻对（= 这张卡可以被剪开的全部缝），阅读序。
List<GridSeam> gridSeamsOf(Iterable<GridCell> cells) {
  final set = gridCellSet(cells);
  final out = <GridSeam>[];
  for (final c in gridSorted(set)) {
    final right = (x: c.x + 1, y: c.y);
    final down = (x: c.x, y: c.y + 1);
    if (set.contains(right)) out.add((a: c, b: right));
    if (set.contains(down)) out.add((a: c, b: down));
  }
  return out;
}

/// 四邻（正交）。
Iterable<GridCell> _neighboursOf(GridCell c) => <GridCell>[
  (x: c.x + 1, y: c.y),
  (x: c.x - 1, y: c.y),
  (x: c.x, y: c.y + 1),
  (x: c.x, y: c.y - 1),
];

/// 按「还连着的缝」把一组格子分成连通块（顺序 = 阅读序，确定性；空输入 → 空表）。
List<Set<GridCell>> gridComponents(
  Iterable<GridCell> cells, {
  Set<GridSeam> cuts = const <GridSeam>{},
}) {
  final all = gridCellSet(cells);
  if (all.isEmpty) return const <Set<GridCell>>[];
  final seen = <GridCell>{};
  final out = <Set<GridCell>>[];
  for (final start in gridSorted(all)) {
    if (seen.contains(start)) continue;
    final comp = <GridCell>{};
    final queue = <GridCell>[start];
    seen.add(start);
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      comp.add(cur);
      for (final n in _neighboursOf(cur)) {
        if (!all.contains(n)) continue;
        if (cuts.contains(gridSeam(cur, n))) continue; // 这条缝被剪断了
        if (seen.add(n)) queue.add(n);
      }
    }
    out.add(comp);
  }
  return out;
}

/// 一张卡按 [cuts] 拆成若干张卡（连通块 = 一张卡；没有真拆开时原样返回单元素表）。
List<HomeGridTile> homeGridSplitTile(
  HomeGridTile tile, {
  Set<GridSeam> cuts = const <GridSeam>{},
}) {
  final comps = gridComponents(tile.cells, cuts: cuts);
  if (comps.length <= 1) return <HomeGridTile>[tile];
  final titleOf = <GridCell, String>{
    for (var i = 0; i < tile.cells.length; i++) tile.cells[i]: tile.titles[i],
  };
  return <HomeGridTile>[
    for (final comp in comps) _tileOf(comp, titleOf),
  ];
}

/// 整份布局一起拆（拆解模式的预览与退出提交共用）。
List<HomeGridTile> homeGridSplitAll(
  Iterable<HomeGridTile> tiles,
  Set<GridSeam> cuts,
) => <HomeGridTile>[
  for (final t in tiles) ...homeGridSplitTile(t, cuts: cuts),
];

/// 只有**真的把卡片分成两块**的缝才算数。
///
/// 判据 = 把所有缝一起剪断后，这条缝的两格是否落在不同连通块里 —— 串联的两条缝
/// （单独剪任何一条都还连着，一起剪才断开）因此都算数，而绕路还连着的缝会被丢掉
/// （用户口径 2「如果有些分割线分开的两边没有分开（还在其他地方相连），则恢复此处连接」）。
Set<GridSeam> homeGridEffectiveCuts(
  Iterable<HomeGridTile> tiles,
  Set<GridSeam> cuts,
) {
  final out = <GridSeam>{};
  if (cuts.isEmpty) return out;
  for (final tile in tiles) {
    if (tile.cells.length < 2) continue;
    final owner = <GridCell, int>{};
    final comps = gridComponents(tile.cells, cuts: cuts);
    for (var i = 0; i < comps.length; i++) {
      for (final c in comps[i]) {
        owner[c] = i;
      }
    }
    for (final seam in cuts) {
      if (!tile.cells.contains(seam.a) || !tile.cells.contains(seam.b)) continue;
      if (owner[seam.a] != owner[seam.b]) out.add(seam);
    }
  }
  return out;
}

/// 从一张卡里「抠出」一格（长按功能部分拖走 = 只移动这个功能）。
///
/// 返回被抠出来的单格卡 + 剩下的部分 —— 剩下部分**可能不止一张**：抠走一条长条的
/// 中间那格，两边就断了（用户口径 3「长按到功能部分时，只移动此功能」）。
({HomeGridTile moved, List<HomeGridTile> rest}) homeGridExtractCell(
  HomeGridTile tile,
  GridCell cell,
) {
  final titleOf = <GridCell, String>{
    for (var i = 0; i < tile.cells.length; i++) tile.cells[i]: tile.titles[i],
  };
  if (tile.cells.isEmpty) return (moved: tile, rest: const <HomeGridTile>[]);
  // 容错：格子不在卡里时按第一格处理（界面层不会走到，脏数据也不该抛异常）。
  final picked = tile.cells.contains(cell) ? cell : tile.cells.first;
  final moved = HomeGridTile.single(titleOf[picked] ?? tile.titles.first, picked);
  final restCells = <GridCell>[
    for (final c in tile.cells)
      if (c != picked) c,
  ];
  if (restCells.isEmpty) {
    return (moved: moved, rest: const <HomeGridTile>[]);
  }
  final rest = HomeGridTile(
    titles: <String>[for (final c in restCells) titleOf[c] ?? ''],
    cells: restCells,
  );
  return (moved: moved, rest: homeGridSplitTile(rest));
}

/// 用一组格子 + 「格子 → 标题」表拼一张卡（阅读序，与 [HomeGridTile] 的不变式一致）。
HomeGridTile _tileOf(Iterable<GridCell> cells, Map<GridCell, String> titleOf) {
  final sorted = gridSorted(cells);
  return HomeGridTile(
    titles: <String>[for (final c in sorted) titleOf[c] ?? ''],
    cells: sorted,
  );
}
