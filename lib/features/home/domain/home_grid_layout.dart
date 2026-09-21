/// 首页宫格的**聚合布局**（形状 + 位置 + 服务）与拖拽落点判定。
///
/// 用户 2026-09-21 需求（逐字）：
/// 「宫格视图下，我希望增加聚合功能。现有的相当于每个宫格都是一个仅包含一个功能的
/// 卡片，我希望长按拖动后可以合并宫格，并且，宫格这样显示：宫格可以异形，长按拖动到
/// 其他卡片边边上时（必须要在某个边缘处，处于中间则此次拖动松手后不触发合并），松手后，
/// 合并到此边相邻的位置，然后并且未松手时，要在相应位置显示虚线框，如果没有与任何
/// 卡片相邻，则松手不触发合并。然后我们允许长按卡片调整位置（即使是异形的），并且要
/// 允许两个互补的卡片相互嵌套，例如一正一反两个大写 F 形的卡片可以相互插入空隙」
///
/// 本文件的三条核心口径：
/// 1. **一个格子放一个服务**：`titles.length == cells.length` 恒成立（`cells[i]` 属于
///    `titles[i]`，按行优先排序）。合并 = 两张卡的格子与服务一起并起来，因此「合并后的
///    卡片有几个格子就有几个服务」，不存在「格子比服务多」的中间态。
/// 2. **位置是绝对格坐标**（不是「顺序 + 自动流式排版」）：用户要求「松手后合并到此边
///    相邻的位置」「允许调整位置」「允许互补嵌套」，这些都必须精确落位 → 布局存
///    `{cols, tiles[{titles, cells}]}`。窗口列数变了才重新 `packed()`（见 [HomeGridLayout.fitTo]）。
/// 3. **只在本文件做判定**：`homeGridPlanDrop` 是纯函数（给定布局 + 指针格子 + 抓手偏移
///    → 落点方案），界面层只负责把像素换成格子坐标，因此「边缘才合并、中间不合并」
///    这条规则可以在单测里逐字钉住。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'home_grid_shape.dart';

/// 边缘带宽度（占卡片宽 / 高的比例）。
///
/// 指针落在卡片**最外侧这个比例**内才算「拖到边边上」（用户口径：必须要在某个边缘处）；
/// 落在中间（四个方向的最短距离都大于它）→ 本次松手不触发合并。
const double kHomeGridEdgeBand = 0.34;

/// 一张宫格卡片。
///
/// - 单格卡片（未合并）：1 个服务 + 1 个格子；
/// - 聚合卡片（合并后）：N 个服务 + N 个格子（形状可以异形，例如 F 形、L 形）。
class HomeGridTile {
  /// 服务标题（本项目以**标题**当服务身份：`home_screen.dart` 的 `_selectedService`、
  /// 磁贴 key `homeTile-<title>` 都是这个口径），顺序 = [cells] 的行优先顺序。
  final List<String> titles;

  /// 形状：绝对格坐标，行优先排序。
  final List<GridCell> cells;

  /// 主构造：`cells` 会被**按对**重排（服务跟着自己的格子走），
  /// 因此脏存档里顺序错乱的 `cells` 不会让服务串位。
  factory HomeGridTile({
    required List<String> titles,
    required List<GridCell> cells,
  }) {
    if (titles.isEmpty || titles.length != cells.length) {
      throw ArgumentError(
        '宫格卡片：格子数必须等于服务数且不为空'
        '（${titles.length} 个服务 / ${cells.length} 个格子）',
      );
    }
    final order = List<int>.generate(titles.length, (i) => i)
      ..sort((a, b) => gridCompare(cells[a], cells[b]));
    return HomeGridTile._(
      titles: List<String>.unmodifiable([for (final i in order) titles[i]]),
      cells: List<GridCell>.unmodifiable([for (final i in order) cells[i]]),
    );
  }

  const HomeGridTile._({required this.titles, required this.cells});

  /// 单格卡片（未合并的普通宫格）。
  factory HomeGridTile.single(String title, GridCell cell) =>
      HomeGridTile(titles: <String>[title], cells: <GridCell>[cell]);

  /// 服务个数 = 格子个数。
  int get cellCount => cells.length;

  /// 是否是聚合卡片（多服务）。
  bool get isGroup => titles.length > 1;

  /// 身份（**不是**给人看的文案）：服务标题拼串。
  /// 用 `\u001F`（单元分隔符）而不是 `+`，避免标题里本身带分隔符时撞 key。
  String get key => titles.join('\u001F');

  /// 给人看的文案。
  String get label => titles.join(' · ');

  /// 形状范围。
  GridBounds get bounds => gridBoundsOf(cells);

  /// 宽度（格数）。
  int get width => gridWidthOf(bounds);

  /// 高度（格数）。
  int get height => gridHeightOf(bounds);

  /// 平移（形状不变）。
  HomeGridTile translate(int dx, int dy) =>
      HomeGridTile(titles: titles, cells: gridTranslated(cells, dx, dy));

  /// 是否含某个服务。
  bool hasTitle(String title) => titles.contains(title);

  /// 是否含某个格子。
  bool hasCell(GridCell cell) => cells.contains(cell);

  /// 卡片里第 [title] 个服务所在的格子（找不到 → null）。
  GridCell? cellOf(String title) {
    final i = titles.indexOf(title);
    return i < 0 ? null : cells[i];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'titles': titles,
    'cells': <List<int>>[
      for (final c in cells) <int>[c.x, c.y],
    ],
  };

  /// 容错解析：字段缺失 / 类型不对 / 数量不等 / 有重复格 / 形状不连通 → null
  /// （调用方丢掉这一张卡，而不是让整份布局崩掉）。
  static HomeGridTile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawTitles = raw['titles'];
    final rawCells = raw['cells'];
    if (rawTitles is! List || rawCells is! List) return null;
    final titles = <String>[];
    for (final t in rawTitles) {
      if (t is! String) return null;
      final s = t.trim();
      if (s.isEmpty) return null;
      titles.add(s);
    }
    final cells = <GridCell>[];
    for (final c in rawCells) {
      final parsed = _cellOf(c);
      if (parsed == null) return null;
      cells.add(parsed);
    }
    if (titles.isEmpty || titles.length != cells.length) return null;
    if (gridCellSet(cells).length != cells.length) return null;
    if (!gridConnected(cells)) return null;
    return HomeGridTile(titles: titles, cells: cells);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeGridTile &&
      listEquals(titles, other.titles) &&
      gridShapeKey(cells) == gridShapeKey(other.cells);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(titles), gridShapeKey(cells));

  @override
  String toString() => 'HomeGridTile($label @ ${gridShapeKey(cells)})';
}

/// 整个宫格的布局：列数 + 全部卡片（互不重叠）。
class HomeGridLayout {
  /// 排版时的列数。渲染列数是响应式的（窄窗少几列），
  /// 与它不一致时走 [fitTo] 重新排（`packed`）。
  final int cols;

  /// 全部卡片（按「先上后下、先左后右」排序，即渲染顺序）。
  final List<HomeGridTile> tiles;

  factory HomeGridLayout({
    required int cols,
    required List<HomeGridTile> tiles,
  }) {
    final ordered = List<HomeGridTile>.of(tiles)..sort(_compareTiles);
    return HomeGridLayout._(
      cols: cols < 1 ? 1 : cols,
      tiles: List<HomeGridTile>.unmodifiable(ordered),
    );
  }

  const HomeGridLayout._({required this.cols, required this.tiles});

  /// 默认布局：按目录顺序**一行一行铺**（= 重构前 `Wrap` 的排法，逐格 1×1）。
  factory HomeGridLayout.flow({
    required List<String> titles,
    required int cols,
  }) {
    final n = cols < 1 ? 1 : cols;
    return HomeGridLayout(
      cols: n,
      tiles: <HomeGridTile>[
        for (var i = 0; i < titles.length; i++)
          HomeGridTile.single(titles[i], (x: i % n, y: i ~/ n)),
      ],
    );
  }

  static int _compareTiles(HomeGridTile a, HomeGridTile b) {
    final byRow = a.bounds.top.compareTo(b.bounds.top);
    if (byRow != 0) return byRow;
    final byCol = a.bounds.left.compareTo(b.bounds.left);
    if (byCol != 0) return byCol;
    return a.key.compareTo(b.key);
  }

  /// 行数（最大行号 + 1）。
  int get rows {
    var bottom = 0;
    for (final t in tiles) {
      final b = t.bounds.bottom + 1;
      if (b > bottom) bottom = b;
    }
    return bottom;
  }

  /// 每个格子归哪张卡（重叠时以先出现的为准）。
  Map<GridCell, HomeGridTile> get occupancy {
    final map = <GridCell, HomeGridTile>{};
    for (final t in tiles) {
      for (final c in t.cells) {
        map.putIfAbsent(c, () => t);
      }
    }
    return map;
  }

  /// 全部服务标题（按卡片顺序）。
  List<String> get allTitles => <String>[for (final t in tiles) ...t.titles];

  /// 聚合卡片张数（>1 个服务的卡片）。
  int get groupCount => tiles.where((t) => t.isGroup).length;

  /// 是否含某个服务。
  bool containsTitle(String title) => tiles.any((t) => t.hasTitle(title));

  /// 格子上的卡片。
  HomeGridTile? tileAt(GridCell cell) => occupancy[cell];

  /// 按身份取卡片。
  HomeGridTile? tileByKey(String key) {
    for (final t in tiles) {
      if (t.key == key) return t;
    }
    return null;
  }

  /// 布局自洽：格子不越界、互不重叠、每张卡连通、服务不重复。
  bool get isValid {
    final used = <GridCell>{};
    final titles = <String>{};
    for (final t in tiles) {
      if (t.cells.isEmpty || !gridConnected(t.cells)) return false;
      for (final c in t.cells) {
        if (c.x < 0 || c.x >= cols || c.y < 0) return false;
        if (!used.add(c)) return false;
      }
      for (final title in t.titles) {
        if (!titles.add(title)) return false;
      }
    }
    return true;
  }

  /// 去掉一张卡。
  HomeGridLayout withoutTile(String key) => HomeGridLayout(
    cols: cols,
    tiles: <HomeGridTile>[
      for (final t in tiles)
        if (t.key != key) t,
    ],
  );

  /// 用同一身份的新卡替换（改位置 / 改形状都走这里）。
  HomeGridLayout replacingTile(String key, HomeGridTile next) => HomeGridLayout(
    cols: cols,
    tiles: <HomeGridTile>[
      for (final t in tiles) t.key == key ? next : t,
    ],
  );

  /// 追加一张卡。
  HomeGridLayout addingTile(HomeGridTile tile) =>
      HomeGridLayout(cols: cols, tiles: <HomeGridTile>[...tiles, tile]);

  /// 把某个服务单独放到**第一个空位**（含别人形状留下的空隙 —— 用户要的「互补嵌套」）。
  HomeGridLayout addingSingle(String title) {
    final used = <GridCell>{for (final t in tiles) ...t.cells};
    final at = _firstFreeOrigin(
      HomeGridTile.single(title, (x: 0, y: 0)),
      cols,
      used,
    );
    return addingTile(HomeGridTile.single(title, at));
  }

  /// 按当前目录重排布局：
  /// - 目录里还有的服务：**原位保留**（形状、位置都不动）；
  /// - 目录里没有的服务（改版删掉的入口）：连格子一起去掉；
  /// - 目录里新加的服务（以及因为脏存档被拆散的服务）：放到第一个空位；
  /// - 最后校验一次，任何不自洽（重叠 / 越界 / 不连通）都退回默认流式布局。
  HomeGridLayout reconcile(List<String> titles) {
    final want = <String>[];
    final wantSet = <String>{};
    for (final raw in titles) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      if (wantSet.add(s)) want.add(s);
    }
    if (want.isEmpty) {
      return HomeGridLayout(cols: cols, tiles: const <HomeGridTile>[]);
    }

    final used = <GridCell>{};
    final handled = <String>{};
    final kept = <HomeGridTile>[];
    final pending = <String>[];
    for (final tile in tiles) {
      final keepTitles = <String>[];
      final keepCells = <GridCell>[];
      for (var i = 0; i < tile.cells.length; i++) {
        final title = tile.titles[i];
        if (!wantSet.contains(title) || handled.contains(title)) continue;
        keepTitles.add(title);
        keepCells.add(tile.cells[i]);
      }
      if (keepTitles.isEmpty) continue;
      var ok = gridConnected(keepCells);
      if (ok) {
        for (final c in keepCells) {
          if (c.x < 0 || c.x >= cols || c.y < 0 || used.contains(c)) {
            ok = false;
            break;
          }
        }
      }
      if (ok) {
        kept.add(HomeGridTile(titles: keepTitles, cells: keepCells));
        used.addAll(keepCells);
        handled.addAll(keepTitles);
      } else {
        // 脏存档 / 目录删了中间一个入口导致形状断成两截：拆成单格重新找位置。
        pending.addAll(keepTitles);
        handled.addAll(keepTitles);
      }
    }
    for (final title in want) {
      if (!handled.contains(title)) {
        pending.add(title);
        handled.add(title);
      }
    }

    var result = HomeGridLayout(cols: cols, tiles: kept);
    for (final title in pending) {
      result = result.addingSingle(title);
    }
    return result.isValid
        ? result
        : HomeGridLayout.flow(titles: want, cols: cols);
  }

  /// 换列数（响应式）：列数一致原样返回（保住用户的异形与嵌套），
  /// 不一致则按阅读序重新装箱（`packed`）。
  HomeGridLayout fitTo(int other) {
    final n = other < 1 ? 1 : other;
    if (n == cols && isValid) return this;
    return packed(cols: n);
  }

  /// 阅读序装箱（首次适配）：逐张卡在行优先扫描中找**第一个放得下的位置**。
  ///
  /// 扫描允许「填进前面卡片留下的空隙」，所以互补异形（一正一反两个 F）
  /// 在这里会自动嵌合；比目标列还宽的卡（窗口被拖得很窄）拆成单格。
  HomeGridLayout packed({required int cols}) {
    final n = cols < 1 ? 1 : cols;
    final used = <GridCell>{};
    final placed = <HomeGridTile>[];
    for (final tile in tiles) {
      for (final piece in _piecesFor(tile, n)) {
        final at = _firstFreeOrigin(piece, n, used);
        final moved = piece.translate(
          at.x - piece.bounds.left,
          at.y - piece.bounds.top,
        );
        placed.add(moved);
        used.addAll(moved.cells);
      }
    }
    return HomeGridLayout(cols: n, tiles: placed);
  }

  /// 让位：把 [anchored]（刚被拖动 / 刚合并出来的卡）**钉死在它落下的位置**，
  /// 只把与它撞车的卡片挪到第一个空位；其余卡片的格子**一格都不动**。
  ///
  /// 为什么需要它：满格的宫格里，把 A 拖到 B 的右边缘，落点那一格必然是 C 的位置
  /// （用户口径要的是「合并到此边相邻的位置」，而不是「把 C 盖掉」）→ C 必须让开。
  /// 只要不撞车就原位保留，所以用户辛苦摆出来的异形嵌合不会被一次拖动打乱。
  HomeGridLayout reflowed({
    required HomeGridTile anchored,
    Map<String, HomeGridTile> settled = const <String, HomeGridTile>{},
  }) {
    // 已经定好位置的卡片（被挤开 / 被顶开的那些）**先占住格子** —— 否则「谁被让位」
    // 取决于卡片在列表里的顺序：列表按「行优先 + 标题」排（`_compareTiles`），乙 与 丙
    // 都想站 (2,0) 时 丙 排在前面、会先把格子占了，乙 反而被扔到第一个空位去。
    final used = <GridCell>{
      ...anchored.cells,
      for (final tile in settled.values) ...tile.cells,
    };
    final keep = <HomeGridTile>[];
    final displaced = <HomeGridTile>[];
    for (final tile in tiles) {
      if (tile.key == anchored.key) continue;
      final fixed = settled[tile.key];
      if (fixed != null) {
        keep.add(fixed); // 它已经在最终位置上了：占住格子、不接受让位
        continue;
      }
      var clash = false;
      for (final c in tile.cells) {
        if (used.contains(c)) {
          clash = true;
          break;
        }
      }
      if (clash) {
        displaced.add(tile);
      } else {
        keep.add(tile);
        used.addAll(tile.cells);
      }
    }
    final placed = <HomeGridTile>[...keep, anchored];
    for (final tile in displaced) {
      for (final piece in _piecesFor(tile, cols)) {
        final at = _firstFreeOrigin(piece, cols, used);
        final moved = piece.translate(
          at.x - piece.bounds.left,
          at.y - piece.bounds.top,
        );
        placed.add(moved);
        used.addAll(moved.cells);
      }
    }
    return HomeGridLayout(cols: cols, tiles: placed);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'cols': cols,
    'tiles': <Map<String, Object?>>[for (final t in tiles) t.toJson()],
  };

  /// 容错解析（脏 / 旧 / 半截数据一律返回 null，由调用方回落默认布局）。
  static HomeGridLayout? parse(Object? raw) {
    Object? value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    final rawTiles = value['tiles'];
    if (rawTiles is! List) return null;
    final tiles = <HomeGridTile>[];
    for (final t in rawTiles) {
      final tile = HomeGridTile.fromJson(t);
      if (tile != null) tiles.add(tile);
    }
    if (tiles.isEmpty) return null;
    final layout = HomeGridLayout(
      cols: _intOf(value['cols']) ?? 1,
      tiles: tiles,
    );
    return layout.isValid ? layout : null;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeGridLayout && cols == other.cols && listEquals(tiles, other.tiles);

  @override
  int get hashCode => Object.hash(cols, Object.hashAll(tiles));

  @override
  String toString() =>
      'HomeGridLayout(cols=$cols, tiles=${tiles.length}, groups=$groupCount)';
}

/// 落点方案类型。
enum HomeGridDropKind {
  /// 拖到空格（或**压到别人身上**）→ 只挪位置，不合并；
  /// 压到的卡片沿拖动方向被**挤开**（见 `_movePlan`）。
  move('移动'),

  /// 拖到别的卡片**边缘** → 落在那条边旁边，并合并成一张卡。
  merge('合并');

  const HomeGridDropKind(this.label);

  /// 给人看的文案。
  final String label;
}

/// 一次拖动的落点方案（纯数据；界面只负责画虚线框与调用 [apply]）。
class HomeGridDropTarget {
  /// 落点类型。
  final HomeGridDropKind kind;

  /// 被拖卡片的新形状 / 新位置。
  final HomeGridTile landing;

  /// 被拖卡片的身份。
  final String sourceKey;

  /// 合并目标（指针压着的那张；[HomeGridDropKind.move] 时为 null）。
  final HomeGridTile? target;

  /// 合并后**一起进同一张卡**的所有卡片（含 [target]；纯移动时为空）。
  ///
  /// 落点那格**原本站着的卡片**也在里面（它已经带上挪之后的新位置）—— 用户
  /// 2026-09-21 三轮口径：「三张并成一张：C 也一起并进来（B + A + C 三格一张卡）」。
  final List<HomeGridTile> joined;

  /// 被**整体推开**、但不进合并的卡片（`key` → 挪之后的新位置；通常是被连锁推着走的尾巴）。
  final Map<String, HomeGridTile> pushed;

  /// 合并发生在目标的哪条边（`left` / `right` / `top` / `bottom`；移动时为空串）。
  final String side;

  const HomeGridDropTarget({
    required this.kind,
    required this.landing,
    required this.sourceKey,
    this.target,
    this.joined = const <HomeGridTile>[],
    this.pushed = const <String, HomeGridTile>{},
    this.side = '',
  });

  /// 是否合并。
  bool get isMerge => kind == HomeGridDropKind.merge;

  /// 这条边的中文名。
  String get sideLabel => switch (side) {
    'left' => '左边',
    'right' => '右边',
    'top' => '上方',
    'bottom' => '下方',
    _ => '',
  };

  /// **合并后的那张卡**（形状 = 落点 + 所有要并进来的卡片；纯移动时为 null）。
  ///
  /// 虚线框画的就是它 —— 用户 2026-09-21 二轮：「我希望显示的虚线框是与将要连接的
  /// 卡片相连的，而不是单纯相邻 …… 虚线框展示合并后的卡片形状」。
  HomeGridTile? get mergedResult {
    if (!isMerge) return null;
    final union = <GridCell, String>{};
    for (final tile in <HomeGridTile>[...joined, landing]) {
      for (var i = 0; i < tile.cells.length; i++) {
        union.putIfAbsent(tile.cells[i], () => tile.titles[i]);
      }
    }
    final cells = gridSorted(union.keys);
    return HomeGridTile(
      titles: <String>[for (final c in cells) union[c]!],
      cells: cells,
    );
  }

  /// 这次落点会并进来的全部服务名（给提示文案用，按卡片顺序）。
  List<String> get mergedLabels => <String>[
    for (final t in joined) t.label,
    landing.label,
  ];

  /// 把方案落到布局上（新的布局；调用方负责保存）。
  ///
  /// [pushed] 里的卡片先落到它们的新位置（**合并与被挤开都走这条**），再由
  /// [HomeGridLayout.reflowed] 处理「挪出界 / 仍然撞车」的那些（`anchored` = 落点那张卡，
  /// 它钉死不动）。
  HomeGridLayout apply(HomeGridLayout layout) {
    final merged = mergedResult;
    if (merged == null) {
      final moved = pushed.isEmpty
          ? layout.replacingTile(sourceKey, landing)
          : HomeGridLayout(
              cols: layout.cols,
              tiles: <HomeGridTile>[
                for (final tile in layout.tiles)
                  if (tile.key == sourceKey)
                    landing
                  else
                    pushed[tile.key] ?? tile,
              ],
            );
      return moved.reflowed(anchored: landing, settled: pushed);
    }
    final absorbed = <String>{
      sourceKey,
      for (final tile in joined) tile.key,
    };
    return HomeGridLayout(
      cols: layout.cols,
      tiles: <HomeGridTile>[
        for (final tile in layout.tiles)
          if (!absorbed.contains(tile.key)) pushed[tile.key] ?? tile,
        merged,
      ],
    ).reflowed(anchored: merged, settled: pushed);
  }

  @override
  String toString() =>
      'HomeGridDropTarget(${kind.label}${isMerge ? '·$sideLabel' : ''} '
      '@${gridShapeKey(landing.cells)} joined=${joined.length} '
      'pushed=${pushed.length})';
}

/// 判定一次拖动的落点（纯函数）。
///
/// - [pointerCell]：指针所在的格子；
/// - [grabCell]：起手时抓住的**卡片内格子偏移**（相对卡片包围盒左上角），
///   落位时保持这个相对关系，用户的手指与卡片不会「错位」；
/// - [pointerFractionX] / [pointerFractionY]：指针在**该格子内**的像素比例（0..1），
///   用来判断「是不是贴在这张卡的某条边上」——格子粒度不够（1×1 的卡片只有一个格子，
///   按格子算永远在正中间，就永远合并不了），必须看格内比例；
/// - **边只认外露的边**：同一张卡内部两个格子之间的缝不是边（异形卡片的内凹处
///   反而是合法的落点 —— 用户要的「互补嵌合」正是从那里进去的）；
/// - 指针压在卡片**中间 / 内缝**（不在任何一条边带里）→ **不合并，但会挤开**：
///   落点照常算（抓手格对齐指针），压到的卡片沿拖动方向让位（用户 2026-09-21 十二轮
///   「像手机桌面一样 …… 也要支持把卡片挤开」）；
/// - 结果 null = 本次松手什么都不做（落点越界 / 原地没挪）。
HomeGridDropTarget? homeGridPlanDrop({
  required HomeGridLayout layout,
  required String draggedKey,
  required GridCell pointerCell,
  required GridCell grabCell,
  double pointerFractionX = 0.5,
  double pointerFractionY = 0.5,
  double edgeBand = kHomeGridEdgeBand,
}) {
  final dragged = layout.tileByKey(draggedKey);
  if (dragged == null) return null;

  final occupied = <GridCell, HomeGridTile>{};
  for (final t in layout.tiles) {
    if (t.key == draggedKey) continue; // 自己的格子先腾空
    for (final c in t.cells) {
      occupied.putIfAbsent(c, () => t);
    }
  }

  final target = occupied[pointerCell];
  if (target != null) {
    final fx = pointerFractionX < 0
        ? 0.0
        : (pointerFractionX > 1 ? 1.0 : pointerFractionX);
    final fy = pointerFractionY < 0
        ? 0.0
        : (pointerFractionY > 1 ? 1.0 : pointerFractionY);
    // 四条边里挑**最近且外露**的一条；都不在边缘带内 → 指针在卡片中间 → 不合并。
    String? side;
    var best = double.infinity;
    void consider(String name, double distance, bool exposed) {
      if (!exposed || distance > edgeBand) return;
      if (distance < best) {
        best = distance;
        side = name;
      }
    }

    consider(
      'left',
      fx,
      !target.hasCell((x: pointerCell.x - 1, y: pointerCell.y)),
    );
    consider(
      'right',
      1 - fx,
      !target.hasCell((x: pointerCell.x + 1, y: pointerCell.y)),
    );
    consider(
      'top',
      fy,
      !target.hasCell((x: pointerCell.x, y: pointerCell.y - 1)),
    );
    consider(
      'bottom',
      1 - fy,
      !target.hasCell((x: pointerCell.x, y: pointerCell.y + 1)),
    );
    final picked = side;
    if (picked == null) {
      // 指针压在卡片**中间 / 内缝**（不在任何一条边带里）：不合并，但**挤开**
      // —— 用户 2026-09-21 十二轮：「我希望添加碰撞移动的功能，就是像手机桌面一样，
      // 既要支持合并也要支持把卡片挤开」。老口径这里是 `return null`（松手什么都不做）。
      final db = dragged.bounds;
      return _movePlan(
        layout: layout,
        dragged: dragged,
        landing: dragged.translate(
          pointerCell.x - grabCell.x - db.left,
          pointerCell.y - grabCell.y - db.top,
        ),
      );
    }

    final bounds = dragged.bounds;
    // 另一轴与指针所在的行 / 列对齐（抓手格必在包围盒内，clamp 只是防御性写法）。
    final top = _clampAlign(
      pointerCell.y - grabCell.y,
      pointerCell.y - (dragged.height - 1),
      pointerCell.y,
    );
    final left = _clampAlign(
      pointerCell.x - grabCell.x,
      pointerCell.x - (dragged.width - 1),
      pointerCell.x,
    );
    late final HomeGridTile landing;
    if (picked == 'right') {
      // 落在指针那格**右边那一格**上（= 目标卡的外侧）。
      landing = dragged.translate(
        pointerCell.x + 1 - bounds.left,
        top - bounds.top,
      );
    } else if (picked == 'left') {
      landing = dragged.translate(
        pointerCell.x - 1 - bounds.right,
        top - bounds.top,
      );
    } else if (picked == 'top') {
      landing = dragged.translate(
        left - bounds.left,
        pointerCell.y - 1 - bounds.bottom,
      );
    } else {
      landing = dragged.translate(
        left - bounds.left,
        pointerCell.y + 1 - bounds.top,
      );
    }
    // 「如果没有与任何卡片相邻，则松手不触发合并」+ 落点必须在界内
    // （落点上原本站着的**别人**不算冲突 —— `apply` 会让它们让位，
    //   否则满格宫格里根本合并不了：落点那格永远是别人）。
    if (!gridTouching(target.cells, landing.cells)) return null;
    if (!_inBounds(landing, layout.cols)) return null;
    // 落点压到目标卡自己身上 = 两张卡叠着并，union 里同一格要写两个标题（必丢一个服务）→ 不认。
    if (gridOverlaps(landing.cells, target.cells)) return null;
    if (!gridConnected(<GridCell>{...target.cells, ...landing.cells})) return null;

    // 落点那格**站着的卡片一起并进来**，并且整条尾巴沿合并方向往后推开一位 ——
    // 用户 2026-09-21 三轮口径（逐字）：「三张并成一张：C 也一起并进来
    // （B + A + C 三格一张卡），虚线框显示这个更大的形状」。
    final landingSet = gridCellSet(landing.cells);
    final occupants = <HomeGridTile>[
      for (final t in layout.tiles)
        if (t.key != draggedKey &&
            t.key != target.key &&
            t.cells.any(landingSet.contains))
          t,
    ];
    var joined = <HomeGridTile>[target];
    final pushed = <String, HomeGridTile>{};
    if (occupants.isNotEmpty) {
      final step = _pushVector(landing, occupants, picked);
      final moves = _cascadeMoves(
        layout: layout,
        skipKeys: <String>{draggedKey, target.key},
        landingSet: landingSet,
        step: step,
      );
      for (final t in layout.tiles) {
        final mv = moves[t.key];
        if (mv == null) continue;
        final moved = t.translate(mv.x, mv.y);
        // 挪出界的卡片不硬挪：留给 `apply` 的 `reflowed` 让位（挪到第一个空位）。
        if (!_inBounds(moved, layout.cols)) continue;
        if (occupants.any((o) => o.key == t.key)) {
          joined.add(moved); // 落点那格原来的卡片：并进来
        } else {
          pushed[t.key] = moved; // 只是被推开，不进合并
        }
      }
    }
    // 合并后的形状必须连通；不连通就退回「只并目标那一张」（老口径）。
    final mergedCells = <GridCell>{
      ...target.cells,
      ...landing.cells,
      for (final t in joined.skip(1)) ...t.cells,
    };
    if (!gridConnected(mergedCells)) {
      joined = <HomeGridTile>[target];
      pushed.clear();
    }
    return HomeGridDropTarget(
      kind: HomeGridDropKind.merge,
      landing: landing,
      sourceKey: draggedKey,
      target: target,
      joined: joined,
      pushed: pushed,
      side: picked,
    );
  }

  final db = dragged.bounds;
  final landing = dragged.translate(
    pointerCell.x - grabCell.x - db.left,
    pointerCell.y - grabCell.y - db.top,
  );
  // 压到别人身上（不在任何一条边带里）= **挤开**，不是「什么都不做」——
  // 用户 2026-09-21 十二轮原话：「我希望添加碰撞移动的功能，就是像手机桌面一样，
  // 既要支持合并也要支持把卡片挤开」。
  return _movePlan(layout: layout, dragged: dragged, landing: landing);
}

/// 「纯移动」的落点方案 —— 落点压到别人时**把别人挤开**（不合并）。
///
/// 老口径是 `_canPlace` 不过就返回 null（「拖到卡片中间 / 落点压着别人 → 松手什么都不做」），
/// 但满格宫格里落点几乎永远压着别人，用户会觉得「我明明拖到了那里却什么都没发生」
/// （用户 2026-09-21 十二轮：「既要支持合并也要支持把卡片挤开」）。
///
/// 挤开方向 = **从原来位置指向落点的主导轴**（往右拖 → 右边的卡片往右让；往下拖 → 往下让），
/// 与合并那一支共用 [_pushVector] + [_cascadeMoves]：被推的整条尾巴同一位移，
/// 挪出界的那些不硬挪，留给 [HomeGridLayout.reflowed] 让位（挪到第一个空位）。
///
/// 返回 null = 落点越界（放不下），或**本来就没挪**（点一下拿起 → 原地再点一下放下）。
HomeGridDropTarget? _movePlan({
  required HomeGridLayout layout,
  required HomeGridTile dragged,
  required HomeGridTile landing,
}) {
  if (!_inBounds(landing, layout.cols)) return null;
  final landingSet = gridCellSet(landing.cells);
  final occupants = <HomeGridTile>[
    for (final t in layout.tiles)
      if (t.key != dragged.key && t.cells.any(landingSet.contains)) t,
  ];
  if (occupants.isEmpty) {
    return HomeGridDropTarget(
      kind: HomeGridDropKind.move,
      landing: landing,
      sourceKey: dragged.key,
    );
  }
  final from = dragged.bounds;
  final to = landing.bounds;
  final dx = to.left - from.left;
  final dy = to.top - from.top;
  if (dx == 0 && dy == 0) return null; // 一格都没挪 = 取消
  final horizontal = dx != 0 && dx.abs() >= dy.abs();
  final side = horizontal
      ? (dx > 0 ? 'right' : 'left')
      : (dy > 0 ? 'bottom' : 'top');
  final step = _pushVector(landing, occupants, side);
  final moves = _cascadeMoves(
    layout: layout,
    skipKeys: <String>{dragged.key},
    landingSet: landingSet,
    step: step,
  );
  final pushed = <String, HomeGridTile>{};
  for (final t in layout.tiles) {
    final mv = moves[t.key];
    if (mv == null) continue;
    final moved = t.translate(mv.x, mv.y);
    // 挪出界的卡片不硬挪：留给 `apply` 的 `reflowed` 让位（挪到第一个空位）。
    if (!_inBounds(moved, layout.cols)) continue;
    pushed[t.key] = moved;
  }
  return HomeGridDropTarget(
    kind: HomeGridDropKind.move,
    landing: landing,
    sourceKey: dragged.key,
    pushed: pushed,
    side: side,
  );
}

/// 「点击拿起 → 再点一下放下」的落点方案（编辑模式）。
///
/// 与 [homeGridPlanDrop] 共用同一套 [_movePlan]：落点压在别的卡片中间 / 内缝上时
/// **把那几张挤开**（用户 2026-09-21 十二轮：「像手机桌面一样 …… 也要支持把卡片挤开」），
/// 而不是像老口径那样「点哪儿都没反应」。落点越界（算出负数格 / 越过右边）→ null = 取消。
HomeGridDropTarget? homeGridPlanTapDrop({
  required HomeGridLayout layout,
  required String draggedKey,
  required GridCell pointerCell,
  required GridCell grabCell,
}) {
  final dragged = layout.tileByKey(draggedKey);
  if (dragged == null) return null;
  final bounds = dragged.bounds;
  return _movePlan(
    layout: layout,
    dragged: dragged,
    landing: dragged.translate(
      pointerCell.x - grabCell.x - bounds.left,
      pointerCell.y - grabCell.y - bounds.top,
    ),
  );
}

/// 布局 → JSON 字符串（Hive 单 key 存整份布局的口径，与 `zcMaterialsJson` 同款）。
String homeGridLayoutJson(HomeGridLayout layout) => jsonEncode(layout.toJson());

/// JSON 字符串 → 布局（脏数据返回 null）。
HomeGridLayout? homeGridLayoutFromJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return HomeGridLayout.parse(raw);
}

/// **连锁推动**：撞上落点、或撞上「已经要挪的卡片（挪之后的位置）」的卡片一起挪
/// （整条尾巴共用同一个位移 [step]）。
///
/// [skipKeys] = 不参与推动的卡片（被拖的那张；合并时还有被并进来的目标）。
/// 合并那一支与 [_movePlan] 的「挤开」共用这一份实现，两边的手感才一致。
Map<String, GridCell> _cascadeMoves({
  required HomeGridLayout layout,
  required Set<String> skipKeys,
  required Set<GridCell> landingSet,
  required GridCell step,
}) {
  final moves = <String, GridCell>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final t in layout.tiles) {
      if (skipKeys.contains(t.key) || moves.containsKey(t.key)) continue;
      var hit = t.cells.any(landingSet.contains);
      if (!hit) {
        for (final entry in moves.entries) {
          final other = layout.tileByKey(entry.key);
          if (other == null) continue;
          if (gridOverlaps(
            t.cells,
            gridTranslated(other.cells, entry.value.x, entry.value.y),
          )) {
            hit = true;
            break;
          }
        }
      }
      if (hit) {
        moves[t.key] = step;
        changed = true;
      }
    }
  }
  return moves;
}

/// 让落点上站着的卡片整体让开落点所需的位移（沿合并方向，整条尾巴同一位移）。
///
/// 「往右并出去」时 = 把落点那格原来的卡片挪到落点右边界再往右一格；
/// 纵向同理（用行号）。多个占用卡（多格落点）取最靠外的那个。
GridCell _pushVector(
  HomeGridTile landing,
  List<HomeGridTile> occupants,
  String side,
) {
  final lb = landing.bounds;
  switch (side) {
    case 'right':
      var minLeft = occupants.first.bounds.left;
      for (final t in occupants) {
        if (t.bounds.left < minLeft) minLeft = t.bounds.left;
      }
      return (x: lb.right + 1 - minLeft, y: 0);
    case 'left':
      var maxRight = occupants.first.bounds.right;
      for (final t in occupants) {
        if (t.bounds.right > maxRight) maxRight = t.bounds.right;
      }
      return (x: lb.left - 1 - maxRight, y: 0);
    case 'bottom':
      var minTop = occupants.first.bounds.top;
      for (final t in occupants) {
        if (t.bounds.top < minTop) minTop = t.bounds.top;
      }
      return (x: 0, y: lb.bottom + 1 - minTop);
    case 'top':
      var maxBottom = occupants.first.bounds.bottom;
      for (final t in occupants) {
        if (t.bounds.bottom > maxBottom) maxBottom = t.bounds.bottom;
      }
      return (x: 0, y: lb.top - 1 - maxBottom);
  }
  return (x: 0, y: 0);
}

/// 落位是否在网格内（横向不越界、行号不为负）—— 合并时用：别人可以让位，越界不行。
bool _inBounds(HomeGridTile tile, int cols) {
  for (final c in tile.cells) {
    if (c.x < 0 || c.x >= cols || c.y < 0) return false;
  }
  return true;
}

/// 一张卡在当前列数下的摆放单元：放得下就是它自己，比列数还宽就拆成单格。
List<HomeGridTile> _piecesFor(HomeGridTile tile, int cols) {
  if (tile.width <= cols) return <HomeGridTile>[tile];
  return <HomeGridTile>[
    for (final title in tile.titles) HomeGridTile.single(title, (x: 0, y: 0)),
  ];
}

/// 把值夹到 `[lo, hi]`（`lo` 可能等于 `hi`，不会出现 lo > hi）。
int _clampAlign(int value, int lo, int hi) {
  if (value < lo) return lo;
  if (value > hi) return hi;
  return value;
}

/// 逐个扫「阅读序的第一个放得下（且不越界）的位置」。
GridCell _firstFreeOrigin(
  HomeGridTile tile,
  int cols,
  Set<GridCell> used,
) {
  final w = tile.width;
  final b = tile.bounds;
  var maxY = 0;
  for (final c in used) {
    if (c.y > maxY) maxY = c.y;
  }
  final limit = maxY + tile.height + 1;
  for (var y = 0; y <= limit; y++) {
    for (var x = 0; x + w <= cols; x++) {
      final cells = gridTranslated(tile.cells, x - b.left, y - b.top);
      var fits = true;
      for (final c in cells) {
        if (used.contains(c)) {
          fits = false;
          break;
        }
      }
      if (fits) return (x: x, y: y);
    }
  }
  return (x: 0, y: limit + 1);
}

GridCell? _cellOf(Object? raw) {
  if (raw is! List || raw.length < 2) return null;
  final x = _intOf(raw[0]);
  final y = _intOf(raw[1]);
  if (x == null || y == null) return null;
  return (x: x, y: y);
}

int? _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim());
  return null;
}
