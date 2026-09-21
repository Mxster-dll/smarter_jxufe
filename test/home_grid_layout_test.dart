/// 宫格聚合的领域层守卫（形状几何 / 布局 / 拖拽落点判定）。
///
/// 用户 2026-09-21 需求（逐字）：「宫格视图下，我希望增加聚合功能 …… 宫格可以异形，
/// 长按拖动到其他卡片边边上时（必须要在某个边缘处，处于中间则此次拖动松手后不触发
/// 合并），松手后，合并到此边相邻的位置 …… 如果没有与任何卡片相邻，则松手不触发合并。
/// 然后我们允许长按卡片调整位置（即使是异形的），并且要允许两个互补的卡片相互嵌套，
/// 例如一正一反两个大写 F 形的卡片可以相互插入空隙」。
///
/// 本文件把这条口径逐条钉成断言：**边缘才合并、中间不合并、落点必须相邻、
/// 异形可嵌合、拖动可调位置**。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';

void main() {
  HomeGridTile one(String title, int x, int y) =>
      HomeGridTile.single(title, (x: x, y: y));

  HomeGridTile many(List<String> titles, List<GridCell> cells) =>
      HomeGridTile(titles: titles, cells: cells);

  /// 常用布局：3 列 6 张单格卡（甲..己 铺两行）。
  HomeGridLayout sixGrid() => HomeGridLayout.flow(
    titles: const ['甲', '乙', '丙', '丁', '戊', '己'],
    cols: 3,
  );

  group('形状几何', () {
    test('行优先排序与比较', () {
      expect(gridCompare((x: 0, y: 1), (x: 9, y: 0)), greaterThan(0));
      expect(gridCompare((x: 1, y: 0), (x: 2, y: 0)), lessThan(0));
      expect(gridShapeKey(const [(x: 1, y: 0), (x: 0, y: 0)]), '0,0;1,0');
      expect(gridSorted(const [(x: 2, y: 1), (x: 0, y: 0)]), const [
        (x: 0, y: 0),
        (x: 2, y: 1),
      ]);
    });

    test('四邻连通：L 形连通、两坨不连通、空集合不连通', () {
      expect(
        gridConnected(const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)]),
        isTrue,
      );
      expect(
        gridConnected(const [(x: 0, y: 0), (x: 2, y: 0)]),
        isFalse,
      );
      // 对角相接**不算**连通（卡片只有四邻相接才是一张卡）。
      expect(
        gridConnected(const [(x: 0, y: 0), (x: 1, y: 1)]),
        isFalse,
      );
      expect(gridConnected(const <GridCell>[]), isFalse);
    });

    test('相接 / 重叠 / 范围', () {
      const a = <GridCell>[(x: 0, y: 0)];
      const b = <GridCell>[(x: 1, y: 0)];
      const c = <GridCell>[(x: 1, y: 1)];
      expect(gridTouching(a, b), isTrue);
      expect(gridTouching(a, c), isFalse);
      expect(gridOverlaps(a, b), isFalse);
      expect(gridOverlaps(a, a), isTrue);
      final bounds = gridBoundsOf(const [
        (x: 2, y: 3),
        (x: 0, y: 1),
        (x: 1, y: 5),
      ]);
      expect(bounds, (left: 0, top: 1, right: 2, bottom: 5));
      expect(gridWidthOf(bounds), 3);
      expect(gridHeightOf(bounds), 5);
      final empty = gridBoundsOf(const <GridCell>[]);
      expect(gridWidthOf(empty), 0);
      expect(gridHeightOf(empty), 0);
    });
  });

  group('轮廓环（异形卡片倒圆角用）', () {
    // 用户 2026-09-21 第三轮原话：「卡片在拐弯的时候，内侧会有一个突起，我希望做成圆角」。
    // 轮廓环是这条需求的地基：环沿格线走（不碰格缝），画轮廓时每个 90° 转角
    // （凸角收圆 + 凹角倒圆）才有的可倒 —— 逐格圆角矩形做布尔并会留下 12×12 方角突起。
    test('单格 = 一个 4 点环，环的绕向让内部落在前进方向右手边（屏幕坐标下顺时针）', () {
      final loops = gridOutlineLoops(const [(x: 0, y: 0)]);
      expect(loops, hasLength(1));
      expect(loops.single, const [
        (x: 0, y: 0),
        (x: 1, y: 0),
        (x: 1, y: 1),
        (x: 0, y: 1),
      ]);
      expect(_loopArea(loops.single), greaterThan(0), reason: '外环 = 顺时针');
    });

    test('L 形 = 一个 6 点环：只有真正的转角留着（共线点已简化）', () {
      final loops = gridOutlineLoops(const [
        (x: 0, y: 0),
        (x: 1, y: 0),
        (x: 0, y: 1),
      ]);
      expect(loops, hasLength(1));
      expect(loops.single, const [
        (x: 0, y: 0),
        (x: 2, y: 0),
        (x: 2, y: 1),
        (x: 1, y: 1), // ← 内侧拐角：倒圆角就倒在这里
        (x: 1, y: 2),
        (x: 0, y: 2),
      ]);
      expect(_loopArea(loops.single), greaterThan(0));
    });

    test('2×2 方块 = 4 点环（卡内那两条格缝不在环上）', () {
      final loops = gridOutlineLoops(const [
        (x: 0, y: 0),
        (x: 1, y: 0),
        (x: 0, y: 1),
        (x: 1, y: 1),
      ]);
      expect(loops, hasLength(1));
      expect(loops.single, const [
        (x: 0, y: 0),
        (x: 2, y: 0),
        (x: 2, y: 2),
        (x: 0, y: 2),
      ]);
    });

    test('互补嵌合（S 形）同样是 1 个环，两条内拐角都在环里', () {
      final loops = gridOutlineLoops(const [
        (x: 0, y: 0),
        (x: 1, y: 0),
        (x: 1, y: 1),
        (x: 2, y: 1),
      ]);
      expect(loops, hasLength(1));
      // S 形有 8 个转角（6 个凸角 + 2 个凹角）—— 简化后一个都不许少。
      expect(loops.single, hasLength(8));
      expect(
        loops.single,
        containsAll(<GridCell>[(x: 1, y: 1), (x: 2, y: 1)]),
        reason: '两个内拐角必须留在环上',
      );
    });

    test('中间挖洞 = 两个环，洞的方向相反（非零填充据此把洞挖空）', () {
      final ring = <GridCell>[
        for (var y = 0; y < 3; y++)
          for (var x = 0; x < 3; x++)
            if (x != 1 || y != 1) (x: x, y: y),
      ];
      final loops = gridOutlineLoops(ring);
      expect(loops, hasLength(2));
      expect(loops.map((l) => l.length), everyElement(4));
      final areas = [for (final l in loops) _loopArea(l)];
      expect(areas.where((a) => a > 0), hasLength(1), reason: '外环顺时针');
      expect(areas.where((a) => a < 0), hasLength(1), reason: '洞逆时针');
    });

    test('空集合 → 没有环；共线简化不吞掉转角', () {
      expect(gridOutlineLoops(const <GridCell>[]), isEmpty);
      // 一整条共线的「环」是退化输入：简化会把点全去掉，函数于是原样返回（不返回空环）
      expect(
        gridSimplifyLoop(const [(x: 0, y: 0), (x: 1, y: 0), (x: 2, y: 0)]),
        const [(x: 0, y: 0), (x: 1, y: 0), (x: 2, y: 0)],
      );
      // 真正要简化的形态：一条 3 格长的直边 + 一个转角 → 只留两端
      expect(
        gridSimplifyLoop(const [
          (x: 0, y: 0),
          (x: 1, y: 0),
          (x: 2, y: 0),
          (x: 2, y: 1),
        ]),
        const [(x: 0, y: 0), (x: 2, y: 0), (x: 2, y: 1)],
      );
      expect(
        gridSimplifyLoop(const [
          (x: 0, y: 0),
          (x: 1, y: 0),
          (x: 1, y: 1),
          (x: 0, y: 1),
        ]),
        const [(x: 0, y: 0), (x: 1, y: 0), (x: 1, y: 1), (x: 0, y: 1)],
      );
    });
  });

  group('卡片 HomeGridTile', () {
    test('一个格子一个服务：格子乱序时服务跟着自己的格子走', () {
      final tile = many(
        const ['甲', '乙', '丙'],
        const [(x: 1, y: 0), (x: 0, y: 0), (x: 0, y: 1)],
      );
      expect(tile.cells, const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)]);
      expect(tile.titles, const ['乙', '甲', '丙']);
      expect(tile.cellOf('甲'), (x: 1, y: 0));
      expect(tile.width, 2);
      expect(tile.height, 2);
      expect(tile.isGroup, isTrue);
      expect(tile.label, '乙 · 甲 · 丙');
    });

    test('格子数与服务数必须相等（否则是脏状态，直接报错）', () {
      expect(
        () => many(const ['甲', '乙'], const [(x: 0, y: 0)]),
        throwsArgumentError,
      );
      expect(
        () => many(const <String>[], const <GridCell>[]),
        throwsArgumentError,
      );
    });

    test('平移不改变形状与配对', () {
      final tile = many(
        const ['甲', '乙'],
        const [(x: 0, y: 0), (x: 0, y: 1)],
      );
      final moved = tile.translate(3, 2);
      expect(moved.cells, const [(x: 3, y: 2), (x: 3, y: 3)]);
      expect(moved.titles, const ['甲', '乙']);
      expect(moved.key, tile.key);
    });

    test('JSON 往返 + 脏数据一律 null', () {
      final tile = many(
        const ['甲', '乙', '丙'],
        const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      expect(HomeGridTile.fromJson(tile.toJson()), tile);

      expect(HomeGridTile.fromJson('nope'), isNull);
      expect(HomeGridTile.fromJson(<String, Object?>{}), isNull);
      expect(
        HomeGridTile.fromJson(<String, Object?>{
          'titles': '甲',
          'cells': <Object?>[],
        }),
        isNull,
      );
      // 数量不等
      expect(
        HomeGridTile.fromJson(<String, Object?>{
          'titles': <String>['甲', '乙'],
          'cells': <Object?>[
            <int>[0, 0],
          ],
        }),
        isNull,
      );
      // 重复格
      expect(
        HomeGridTile.fromJson(<String, Object?>{
          'titles': <String>['甲', '乙'],
          'cells': <Object?>[
            <int>[0, 0],
            <int>[0, 0],
          ],
        }),
        isNull,
      );
      // 不连通
      expect(
        HomeGridTile.fromJson(<String, Object?>{
          'titles': <String>['甲', '乙'],
          'cells': <Object?>[
            <int>[0, 0],
            <int>[2, 0],
          ],
        }),
        isNull,
      );
      // 空白标题
      expect(
        HomeGridTile.fromJson(<String, Object?>{
          'titles': <String>['  '],
          'cells': <Object?>[
            <int>[0, 0],
          ],
        }),
        isNull,
      );
    });
  });

  group('布局 HomeGridLayout', () {
    test('默认流式布局 = 一行一行铺（与重构前 Wrap 完全一致）', () {
      final layout = sixGrid();
      expect(layout.rows, 2);
      expect(layout.tiles.length, 6);
      expect(layout.groupCount, 0);
      expect(layout.tileAt((x: 2, y: 1))?.titles.single, '己');
      expect(layout.tileByKey('甲'), isNotNull);
      expect(layout.tileByKey('不存在'), isNull);
      expect(layout.allTitles, const ['甲', '乙', '丙', '丁', '戊', '己']);
      expect(layout.isValid, isTrue);
    });

    test('目录对账：删掉中间一个入口，其余卡片原位不动', () {
      final layout = sixGrid().reconcile(const ['甲', '丙', '丁', '戊', '己']);
      expect(layout.allTitles, const ['甲', '丙', '丁', '戊', '己']);
      expect(layout.tileByKey('丙')?.cells, const [(x: 2, y: 0)]);
      expect(layout.isValid, isTrue);
      for (final tile in layout.tiles) {
        expect(tile.cellCount, tile.titles.length);
      }
    });

    test('目录对账：新入口落到**第一个空隙**（填洞）', () {
      // 甲(0,0) 丙(2,0) 中间空着 (1,0)。
      final sparse = HomeGridLayout(
        cols: 3,
        tiles: [one('甲', 0, 0), one('丙', 2, 0)],
      );
      final layout = sparse.reconcile(const ['甲', '乙', '丙']);
      expect(layout.tileByKey('乙')?.cells, const [(x: 1, y: 0)]);
      expect(layout.isValid, isTrue);
    });

    test('目录对账：脏存档（两张卡抢同一格）也能收敛成合法布局', () {
      final dirty = HomeGridLayout(
        cols: 3,
        tiles: [one('甲', 0, 0), one('乙', 0, 0), one('丙', 1, 0)],
      );
      final layout = dirty.reconcile(const ['甲', '乙', '丙']);
      expect(layout.allTitles.length, 3);
      expect(layout.isValid, isTrue);
    });

    test('列数变化：同列数原样保留，换列数重新装箱且服务不丢', () {
      final layout = sixGrid();
      expect(layout.fitTo(3), same(layout));
      final narrow = layout.fitTo(2);
      expect(narrow.cols, 2);
      expect(narrow.allTitles.toSet(), layout.allTitles.toSet());
      expect(narrow.isValid, isTrue);
      expect(narrow.tiles.every((t) => t.width <= 2), isTrue);
    });

    test('装箱会填进异形留下的空隙（互补嵌合）', () {
      // L 形占 (0,0)(1,0)(0,1)，(1,1) 是它的缺口。
      final l = many(
        const ['甲', '乙', '丙'],
        const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      final layout = HomeGridLayout(
        cols: 2,
        tiles: [l, one('丁', 9, 9)],
      ).packed(cols: 2);
      expect(layout.tileByKey('甲\u001F乙\u001F丙')?.cells, l.cells);
      expect(layout.tileByKey('丁')?.cells, const [(x: 1, y: 1)]);
      expect(layout.isValid, isTrue);
    });

    test('比列数还宽的形状：装箱时拆成单格（不会越界）', () {
      final wide = many(
        const ['甲', '乙', '丙'],
        const [(x: 0, y: 0), (x: 1, y: 0), (x: 2, y: 0)],
      );
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [wide],
      ).packed(cols: 2);
      expect(layout.isValid, isTrue);
      expect(layout.tiles.length, 3);
      expect(layout.allTitles.toSet(), const {'甲', '乙', '丙'});
    });

    test('JSON 往返 + 脏 JSON 一律 null', () {
      final layout = sixGrid();
      expect(homeGridLayoutFromJson(homeGridLayoutJson(layout)), layout);
      expect(homeGridLayoutFromJson(null), isNull);
      expect(homeGridLayoutFromJson(''), isNull);
      expect(homeGridLayoutFromJson('{'), isNull);
      expect(homeGridLayoutFromJson('{"tiles": "x"}'), isNull);
      expect(homeGridLayoutFromJson('{"cols": 3, "tiles": []}'), isNull);
      // 越界（cols=1 却摆在第 2 列）→ 整份丢弃
      expect(
        homeGridLayoutFromJson(
          '{"cols":1,"tiles":[{"titles":["甲"],"cells":[[1,0]]}]}',
        ),
        isNull,
      );
    });
  });

  group('拖拽落点判定', () {
    test('拖到别人右边缘 → 合并（落点那格原本有别人也让位）', () {
      final layout = sixGrid();
      // 甲 拖到 乙 的右边缘（指针在 乙 的格子里、贴右）。
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97,
        pointerFractionY: 0.5,
      );
      expect(plan, isNotNull);
      expect(plan!.kind, HomeGridDropKind.merge);
      expect(plan.side, 'right');
      expect(plan.target?.titles, const ['乙']);
      // 落点 = 乙 右边那格（原本站着 丙）。
      expect(plan.landing.cells, const [(x: 2, y: 0)]);

      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.groupCount, 1);
      expect(next.allTitles.length, 6);
      // 合并后的卡片 = 目标那格 + 落点那格（按行优先配服务：乙 左、甲 右）。
      final merged = next.tileByKey('乙\u001F甲');
      expect(merged?.cells, const [(x: 1, y: 0), (x: 2, y: 0)]);
      // 被挤开的 丙 仍然在（挪到空出来的第一格），没有任何卡片消失。
      expect(next.tileByKey('丙')?.cells, const [(x: 0, y: 0)]);
      expect(next.tiles.length, 5);
    });

    test('从左边贴上去 → 合并在自己原来那格（不打扰别人）', () {
      final layout = sixGrid();
      // 甲 拖到 乙 的**左**边缘：落点 = 乙 左边那格 = 甲 原来的位置 (0,0)。
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.03,
      );
      expect(plan?.side, 'left');
      expect(plan?.landing.cells, const [(x: 0, y: 0)]);
      final next = plan!.apply(layout);
      expect(next.tileByKey('甲\u001F乙')?.cells, const [
        (x: 0, y: 0),
        (x: 1, y: 0),
      ]);
      // 丙 纹丝不动（没被挤开）。
      expect(next.tileByKey('丙')?.cells, const [(x: 2, y: 0)]);
    });

    test('落点那格站着的卡片也一起并进来（三张一张卡），尾巴往后推开一位', () {
      // 用户 2026-09-21 三轮口径（逐字）：「三张并成一张：C 也一起并进来
      // （B + A + C 三格一张卡），虚线框显示这个更大的形状」。
      // 甲(0,0) 乙(1,0) 丙(2,0) [空(3,0)] 丁(4,0)：甲 拖到 乙 的右边缘，
      // 落点 (2,0) 站着 丙 → 丙 一起并进来，并整体挪到 (3,0)（空位，不打扰 丁）。
      final layout = HomeGridLayout(
        cols: 5,
        tiles: [one('甲', 0, 0), one('乙', 1, 0), one('丙', 2, 0), one('丁', 4, 0)],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97,
      );
      expect(plan, isNotNull);
      expect(plan!.landing.cells, const [(x: 2, y: 0)]);
      // joined = 目标（乙）+ 落点原来的主人（丙，带挪之后的新位置）。
      expect(plan.joined.map((t) => t.key), const ['乙', '丙']);
      expect(plan.joined.last.cells, const [(x: 3, y: 0)]);
      expect(plan.pushed, isEmpty, reason: '丙 挪到的 (3,0) 是空的，没人被连锁推开');
      expect(plan.mergedLabels, const ['乙', '丙', '甲']);

      // 虚线框画的就是合并后的形状：三格一整块。
      final shape = plan.mergedResult!;
      expect(shape.cells, const [(x: 1, y: 0), (x: 2, y: 0), (x: 3, y: 0)]);
      expect(shape.titles, const ['乙', '甲', '丙']);
      expect(shape.width, 3);
      expect(gridConnected(shape.cells), isTrue);

      // 落盘后的那张卡与虚线框逐格一致，且 丁 一格没动。
      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, 4, reason: '一个服务都不能丢');
      expect(next.tileByKey('乙\u001F甲\u001F丙')?.cells, shape.cells);
      expect(next.tileByKey('丁')?.cells, const [(x: 4, y: 0)]);
    });

    test('连锁：被推开的位置上还站着卡片，它跟着往后挪（整条尾巴同一位移）', () {
      // 满格一行 甲 乙 丙 丁 戊（5 列）：甲 拖到 乙 右边缘 → 丙 并进来挪到 (3,0)，
      // 那里站着 丁 → 丁 被推到 (4,0)，那里站着 戊 → 戊 再挪就越界了 → 交给让位。
      final layout = HomeGridLayout(
        cols: 5,
        tiles: [
          one('甲', 0, 0),
          one('乙', 1, 0),
          one('丙', 2, 0),
          one('丁', 3, 0),
          one('戊', 4, 0),
        ],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97,
      );
      expect(plan!.joined.map((t) => t.key), const ['乙', '丙']);
      expect(plan.pushed['丁']?.cells, const [(x: 4, y: 0)]);
      expect(plan.pushed.containsKey('戊'), isFalse, reason: '戊 挪出界 → 不硬挪');

      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, 5);
      expect(next.tileByKey('乙\u001F甲\u001F丙')?.cells, const [
        (x: 1, y: 0),
        (x: 2, y: 0),
        (x: 3, y: 0),
      ]);
      expect(next.tileByKey('丁')?.cells, const [(x: 4, y: 0)]);
      // 戊 被让位到空出来的第一格（甲 原来那格）。
      expect(next.tileByKey('戊')?.cells, const [(x: 0, y: 0)]);
    });

    test('纵向同样：落点在下方，下面那张也一起并进来', () {
      final layout = HomeGridLayout(
        cols: 2,
        tiles: [one('甲', 0, 0), one('乙', 0, 1), one('丙', 0, 2), one('丁', 1, 0)],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 0, y: 1),
        grabCell: (x: 0, y: 0),
        pointerFractionY: 0.97,
      );
      expect(plan?.side, 'bottom');
      expect(plan?.landing.cells, const [(x: 0, y: 2)]);
      expect(plan?.joined.map((t) => t.key), const ['乙', '丙']);
      expect(plan?.joined.last.cells, const [(x: 0, y: 3)]);
      expect(plan?.mergedResult?.cells, const [
        (x: 0, y: 1),
        (x: 0, y: 2),
        (x: 0, y: 3),
      ]);
      final next = plan!.apply(layout);
      expect(next.tileByKey('乙\u001F甲\u001F丙')?.cells, const [
        (x: 0, y: 1),
        (x: 0, y: 2),
        (x: 0, y: 3),
      ]);
      expect(next.tileByKey('丁')?.cells, const [(x: 1, y: 0)]);
    });

    test('落点压回目标卡自己身上 → 不认（同一格写两个标题必丢一个服务）', () {
      // 甲 是竖着两格；乙 是 L 形（(2,0) + (1,1)）。甲 贴 乙 的左边缘时，
      // 落点会落在 (1,0)+(1,1)，而 (1,1) 是 乙 自己的格子 → 叠上去了。
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [
          many(const ['甲', '己'], const [(x: 0, y: 0), (x: 0, y: 1)]),
          many(const ['乙', '戊'], const [(x: 2, y: 0), (x: 1, y: 1)]),
        ],
      );
      expect(
        homeGridPlanDrop(
          layout: layout,
          draggedKey: '甲',
          pointerCell: (x: 2, y: 0),
          grabCell: (x: 0, y: 0),
          pointerFractionX: 0.03,
        ),
        isNull,
      );
    });

    test('拖到卡片中间 → 不合并，但把压到的卡片挤开（用户 2026-09-21 十二轮）', () {
      // 用户原话：「我希望添加碰撞移动的功能，就是像手机桌面一样，既要支持合并
      // 也要支持把卡片挤开」→ 老口径「处于中间则松手什么都不做」已作废。
      final layout = sixGrid();
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      );
      expect(plan, isNotNull, reason: '压在中间 → 挤开，不再是「什么都不做」');
      expect(plan!.isMerge, isFalse, reason: '中间仍然**不合并**（用户二轮口径保留）');
      expect(plan.kind, HomeGridDropKind.move);
      expect(plan.landing.cells, const [(x: 1, y: 0)]);
      expect(plan.side, 'right', reason: '往右拖 → 往右让');
      expect(plan.pushed.keys, contains('乙'));
      expect(plan.pushed['乙']!.cells, const [(x: 2, y: 0)]);
      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, 6, reason: '一个服务都不许丢');
      expect(next.tileByKey('甲')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('乙')?.cells, const [(x: 2, y: 0)]);
      expect(
        next.tileByKey('丙')?.cells,
        const [(x: 0, y: 0)],
        reason: '丙 被连锁挤到列外 → 交给 reflowed 让位（挪到空出来的第一格）',
      );

      // 3 格宽的卡片，指针落在中间那格：整体被挤到下一行（往下拖 → 往下让）。
      final wide = HomeGridLayout(
        cols: 4,
        tiles: [
          many(
            const ['甲', '乙', '丙'],
            const [(x: 0, y: 0), (x: 1, y: 0), (x: 2, y: 0)],
          ),
          one('丁', 0, 2),
        ],
      );
      final up = homeGridPlanDrop(
        layout: wide,
        draggedKey: '丁',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      );
      expect(up?.isMerge, isFalse);
      expect(up?.side, 'top', reason: '丁 是从下面拖上来的 → 让位方向是「上」');
      final wideNext = up!.apply(wide);
      expect(wideNext.isValid, isTrue);
      expect(wideNext.tileByKey('丁')?.cells, const [(x: 1, y: 0)]);
      expect(
        wideNext.tileByKey('甲\u001F乙\u001F丙')?.cells,
        const [(x: 0, y: 1), (x: 1, y: 1), (x: 2, y: 1)],
        reason: '往上没地方 → 整张宽卡让位到下一行（不被拆散）',
      );
    });

    test('四条边各自对应的落点', () {
      final layout = HomeGridLayout(
        cols: 5,
        tiles: [one('甲', 2, 2), one('乙', 0, 0)],
      );
      HomeGridDropTarget? at(double fx, double fy) => homeGridPlanDrop(
        layout: layout,
        draggedKey: '乙',
        pointerCell: (x: 2, y: 2),
        grabCell: (x: 0, y: 0),
        pointerFractionX: fx,
        pointerFractionY: fy,
      );
      expect(at(0.02, 0.5)?.side, 'left');
      expect(at(0.02, 0.5)?.landing.cells, const [(x: 1, y: 2)]);
      expect(at(0.98, 0.5)?.side, 'right');
      expect(at(0.98, 0.5)?.landing.cells, const [(x: 3, y: 2)]);
      expect(at(0.5, 0.02)?.side, 'top');
      expect(at(0.5, 0.02)?.landing.cells, const [(x: 2, y: 1)]);
      expect(at(0.5, 0.98)?.side, 'bottom');
      expect(at(0.5, 0.98)?.landing.cells, const [(x: 2, y: 3)]);
    });

    test('多格卡片贴边合并：另一轴与指针所在的行对齐（形状必须连通）', () {
      // 甲/乙 竖直两张卡在 (1,0)(1,1)；丙 是竖直两张卡（丙1 上、丙2 下）。
      final layout = HomeGridLayout(
        cols: 4,
        tiles: [
          many(
            const ['甲', '乙'],
            const [(x: 1, y: 0), (x: 1, y: 1)],
          ),
          many(
            const ['丙1', '丙2'],
            const [(x: 3, y: 2), (x: 3, y: 3)],
          ),
        ],
      );
      // 抓住 丙1（包围盒第 0 格），指针落在 乙 那格右边缘。
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丙1\u001F丙2',
        pointerCell: (x: 1, y: 1),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97,
      );
      expect(plan, isNotNull);
      expect(plan!.side, 'right');
      // 落点一列两格，与指针所在行 (1) 对齐 → (2,1)(2,2)。
      expect(plan.landing.cells, const [(x: 2, y: 1), (x: 2, y: 2)]);
      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.groupCount, 1);
      expect(
        next.tiles.firstWhere((t) => t.isGroup).cells.length,
        4,
        reason: '两张卡合并成 4 格',
      );
    });

    test('落点越界 / 不相邻 → 不做任何事', () {
      final layout = sixGrid();
      // 最右列的卡片拖到它右边 → 越界。
      expect(
        homeGridPlanDrop(
          layout: layout,
          draggedKey: '甲',
          pointerCell: (x: 2, y: 0),
          grabCell: (x: 0, y: 0),
          pointerFractionX: 0.98,
        ),
        isNull,
      );
      // 拖到别人的中间 → 不合并，但**挤开**（不再是 null；见「碰撞移动」组）。
      final pushed = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.5,
        pointerFractionY: 0.5,
      );
      expect(pushed?.isMerge, isFalse);
      expect(pushed?.pushed, isNotEmpty);
    });

    test('拖到空格 = 纯移动（不合并）', () {
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [one('甲', 0, 0), one('乙', 1, 0), one('丙', 0, 2)],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丙',
        pointerCell: (x: 2, y: 0),
        grabCell: (x: 0, y: 0),
      );
      expect(plan?.kind, HomeGridDropKind.move);
      expect(plan?.target, isNull);
      final next = plan!.apply(layout);
      expect(next.tileByKey('丙')?.cells, const [(x: 2, y: 0)]);
      expect(next.groupCount, 0);
      expect(next.isValid, isTrue);
      // 别人一格都没动。
      expect(next.tileByKey('甲')?.cells, const [(x: 0, y: 0)]);
    });
  });

  group('互补嵌合与异形', () {
    test('把卡片拖进异形卡片的缺口（嵌套）', () {
      // 甲..丙 组成 L：(0,0)(1,0)(0,1)，缺口 = (1,1)。
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [
          many(
            const ['甲', '乙', '丙'],
            const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
          ),
          one('丁', 2, 1),
        ],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丁',
        pointerCell: (x: 1, y: 1), // L 的缺口
        grabCell: (x: 0, y: 0),
      );
      expect(plan?.kind, HomeGridDropKind.move);
      expect(plan?.landing.cells, const [(x: 1, y: 1)]);
      final next = plan!.apply(layout);
      expect(next.isValid, isTrue);
      final l = next.tileByKey('甲\u001F乙\u001F丙')!;
      final d = next.tileByKey('丁')!;
      // 丁 的格子落在 L 的包围盒**内部**，且零重叠 → 嵌合。
      expect(gridOverlaps(l.cells, d.cells), isFalse);
      expect(d.bounds.left, greaterThanOrEqualTo(l.bounds.left));
      expect(d.bounds.top, greaterThanOrEqualTo(l.bounds.top));
      expect(d.bounds.right, lessThanOrEqualTo(l.bounds.right));
      expect(d.bounds.bottom, lessThanOrEqualTo(l.bounds.bottom));
    });

    test('互补的两张卡合并后正好拼成一个矩形（从缺口那侧并进去）', () {
      // 甲..丙 是 L 形（缺右下角 (1,1)），丁 单独摆在远处。
      final layout = HomeGridLayout(
        cols: 4,
        tiles: [
          many(
            const ['甲', '乙', '丙'],
            const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
          ),
          one('丁', 3, 1),
        ],
      );
      // 指针落在 L 的 (0,1) 那格的**右**边缘：右邻 (1,1) 不属于 L（是缺口）→ 外露边。
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丁',
        pointerCell: (x: 0, y: 1),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97,
      );
      expect(plan, isNotNull);
      expect(plan!.landing.cells, const [(x: 1, y: 1)]);
      final next = plan.apply(layout);
      final merged = next.tiles.firstWhere((t) => t.isGroup);
      expect(merged.cells.length, 4);
      expect(merged.width, 2);
      expect(merged.height, 2, reason: '缺口被填满 → 合并后是一个规整矩形');
      expect(next.isValid, isTrue);
    });

    test('同一张卡内部的缝不是「边」→ 拖到内缝不合并', () {
      // L 形的 (0,0) 与 (1,0) 之间是内缝（右邻属于同一张卡）。
      final layout = HomeGridLayout(
        cols: 4,
        tiles: [
          many(
            const ['甲', '乙', '丙'],
            const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
          ),
          one('丁', 3, 3),
        ],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丁',
        pointerCell: (x: 0, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.97, // 贴内缝
      );
      expect(plan?.isMerge, isFalse, reason: '内缝不是「边」→ 不合并');
      expect(
        plan?.kind,
        HomeGridDropKind.move,
        reason: '十二轮起：压在内缝上 = 把 L 形挤开，而不是什么都不做',
      );
    });

    test('异形卡片的范围与键', () {
      // 大写 F 形（5 格）：.XX / XX. / .X.
      final f = many(
        const ['1', '2', '3', '4', '5'],
        const [
          (x: 1, y: 0),
          (x: 2, y: 0),
          (x: 0, y: 1),
          (x: 1, y: 1),
          (x: 1, y: 2),
        ],
      );
      expect(f.bounds, (left: 0, top: 0, right: 2, bottom: 2));
      expect(f.width, 3);
      expect(f.height, 3);
      expect(gridConnected(f.cells), isTrue);
      expect(gridShapeKey(f.cells), '1,0;2,0;0,1;1,1;1,2');
    });
  });

  group('点击放下的落点（编辑模式 · 用户 2026-09-21 九轮）', () {
    // 用户原话：「或者点击拿起，再次点击方下」→ 点一下必须有个结果。
    // ⚠ 十二轮起拖动版与点击版**共用同一套挤开逻辑**（用户：「既要支持合并也要支持
    //   把卡片挤开」），所以两边给出的方案逐字相同 —— 这条断言就是钉住这一点。
    test('压在别的卡片正中：拖动版与点击版一样，都是「挤开」', () {
      final layout = sixGrid(); // 3 列 6 张单格卡
      // 甲 的指针落在 乙 那一格的正中（四条边都在 0.5，远超 `kHomeGridEdgeBand` 0.34）。
      final dragged = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      );
      final tapped = homeGridPlanTapDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      );
      expect(dragged, isNotNull);
      expect(tapped, isNotNull);
      expect(dragged!.isMerge, isFalse);
      expect(dragged.kind, HomeGridDropKind.move);
      expect(dragged.landing.cells, const [(x: 1, y: 0)]);
      expect(tapped!.landing.cells, dragged.landing.cells);
      expect(tapped.pushed.keys, dragged.pushed.keys);

      // 甲 落到 (1,0)，乙 被挤到 (2,0)，丙 被连锁挤到列外 → 让位到空出来的 (0,0)。
      final next = tapped.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, 6);
      expect(next.tileByKey('甲')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('乙')?.cells, const [(x: 2, y: 0)]);
      expect(next.tileByKey('丙')?.cells, const [(x: 0, y: 0)]);
    });

    test('抓手格不是包围盒左上角：保持相对关系（拖 2 格卡的第 2 格放到 (0,1)）', () {
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [
          many(const ['甲', '乙'], const [(x: 0, y: 0), (x: 1, y: 0)]),
          one('丙', 2, 0),
        ],
      );
      final plan = homeGridPlanTapDrop(
        layout: layout,
        draggedKey: '甲\u001F乙',
        pointerCell: (x: 1, y: 1),
        grabCell: (x: 1, y: 0), // 抓的是乙那一格
      );
      expect(plan?.landing.cells, const [(x: 0, y: 1), (x: 1, y: 1)]);
      expect(plan!.apply(layout).tileByKey('甲\u001F乙')?.cells, const [
        (x: 0, y: 1),
        (x: 1, y: 1),
      ]);
    });

    test('落点越界 → null（这次点击等于取消）', () {
      final layout = sixGrid();
      // 甲 在 (2,0)（最右列），抓手格 = 包围盒第 2 格 → 往右上放会越过右边界。
      expect(
        homeGridPlanTapDrop(
          layout: layout,
          draggedKey: '丙',
          pointerCell: (x: 2, y: 0),
          grabCell: (x: 0, y: 0),
        )?.landing.cells,
        const [(x: 2, y: 0)],
      );
      // 2 格卡抓**左边那格**、指针放在最右列 → 右边那格会落到列外 → 越界。
      final wide = HomeGridLayout(
        cols: 3,
        tiles: [
          many(const ['甲', '乙'], const [(x: 0, y: 0), (x: 1, y: 0)]),
        ],
      );
      expect(
        homeGridPlanTapDrop(
          layout: wide,
          draggedKey: '甲\u001F乙',
          pointerCell: (x: 2, y: 0),
          grabCell: (x: 0, y: 0),
        ),
        isNull,
        reason: '第二格会被顶到 (3,0)（列外）→ 这次点击取消',
      );
      // 卡片不在布局里 → 也没有方案（脏 key 防御）。
      expect(
        homeGridPlanTapDrop(
          layout: layout,
          draggedKey: '不存在',
          pointerCell: (x: 0, y: 0),
          grabCell: (x: 0, y: 0),
        ),
        isNull,
      );
    });
  });

  // 用户 2026-09-21 十二轮原话（逐字）：「我希望添加碰撞移动的功能，就是像手机桌面一样，
  // 既要支持合并也要支持把卡片挤开」。
  group('碰撞移动：压到别人就挤开（十二轮）', () {
    test('挤开方向 = 从原来位置指向落点的主导轴', () {
      final layout = sixGrid(); // 3 列 6 格全占满 → 落点必然压着人
      // 往右拖一格：乙 让到 (2,0)，丙 连锁出界 → 让位到空出来的 (0,0)。
      final right = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      )!;
      expect(right.isMerge, isFalse);
      expect(right.side, 'right');
      expect(right.landing.cells, const [(x: 1, y: 0)]);
      expect(right.pushed['乙']!.cells, const [(x: 2, y: 0)]);
      final down = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 0, y: 1),
        grabCell: (x: 0, y: 0),
      )!;
      expect(down.side, 'bottom');
      expect(down.landing.cells, const [(x: 0, y: 1)]);
      expect(down.pushed['丁']!.cells, const [(x: 0, y: 2)]);
      final next = down.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, 6, reason: '一个服务都不许丢');
      expect(next.tileByKey('甲')?.cells, const [(x: 0, y: 1)]);
      expect(next.tileByKey('丁')?.cells, const [(x: 0, y: 2)]);
      expect(
        next.tileByKey('戊')?.cells,
        const [(x: 1, y: 1)],
        reason: '丙 那一列没人被撞到 → 一格都不动',
      );
    });

    test('多格卡片被压到：整张一起让位（不拆散）', () {
      final layout = HomeGridLayout(
        cols: 6,
        tiles: [
          many(const ['甲', '乙'], const [(x: 2, y: 0), (x: 3, y: 0)]),
          one('丙', 0, 2),
        ],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '丙',
        pointerCell: (x: 3, y: 0),
        grabCell: (x: 0, y: 0),
      )!;
      expect(plan.side, 'right');
      expect(plan.pushed['甲\u001F乙']!.cells, const [(x: 4, y: 0), (x: 5, y: 0)]);
      final next = plan.apply(layout);
      expect(next.isValid, isTrue);
      expect(next.tileByKey('丙')?.cells, const [(x: 3, y: 0)]);
      expect(
        next.tileByKey('甲\u001F乙')?.cells,
        const [(x: 4, y: 0), (x: 5, y: 0)],
      );
      expect(next.groupCount, 1, reason: '聚合卡整体挪，没有被拆成两张');
    });

    test('落点是空的 → 谁都不挤（pushed 为空）', () {
      final layout = HomeGridLayout.flow(
        titles: const ['甲', '乙', '丙', '丁', '戊', '己'],
        cols: 4,
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 2, y: 1), // 空格子
        grabCell: (x: 0, y: 0),
      )!;
      expect(plan.kind, HomeGridDropKind.move);
      expect(plan.pushed, isEmpty);
      final next = plan.apply(layout);
      expect(next.tileByKey('甲')?.cells, const [(x: 2, y: 1)]);
      expect(next.tileByKey('乙')?.cells, const [(x: 1, y: 0)]);
    });

    test('贴在别人的边上仍然是合并（挤开不许把合并顶掉）', () {
      final layout = sixGrid();
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
        pointerFractionX: 0.02, // 贴左边缘 → 落点在 (0,0)，与 乙 那一格相邻
      );
      expect(plan?.isMerge, isTrue);
      expect(plan?.side, 'left');
      expect(plan?.landing.cells, const [(x: 0, y: 0)]);
    });
  });
}

/// 折线的有向面积（2 倍；> 0 = 顺时针，屏幕坐标 y 向下）—— 轮廓环绕向守卫用。
int _loopArea(List<GridCell> loop) {
  var sum = 0;
  for (var i = 0; i < loop.length; i++) {
    final a = loop[i];
    final b = loop[(i + 1) % loop.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum;
}
