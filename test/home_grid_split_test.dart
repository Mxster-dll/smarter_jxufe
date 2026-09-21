/// 宫格「连接 / 断开」口径的守卫（拆解模式 + 长按功能部分单拖）。
///
/// 用户 2026-09-21 四轮原话（逐字）：
/// 「我希望可以进入拆解模式，此模式下，才显示分割线，点击分割线后，此边处不连接，
/// 分成两部分，因此形成的边界，暂时显示为虚线。退出拆解模式时，如果有些分割线分开的
/// 两边没有分开（还在其他地方相连），则恢复此处连接。」+
/// 「长按到功能部分时，只移动此功能」。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_split.dart';

void main() {
  /// I 形（横着三格）：A B C。
  HomeGridTile row3() => HomeGridTile(
    titles: const ['A', 'B', 'C'],
    cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 2, y: 0)],
  );

  /// 2×2 方块：A B / C D。
  HomeGridTile square() => HomeGridTile(
    titles: const ['A', 'B', 'C', 'D'],
    cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1), (x: 1, y: 1)],
  );

  group('缝（相邻两格之间的连接）', () {
    test('规范化成有序对：参数顺序换了也还是同一条缝', () {
      expect(
        gridSeam((x: 1, y: 0), (x: 0, y: 0)),
        gridSeam((x: 0, y: 0), (x: 1, y: 0)),
      );
      expect(gridSeam((x: 1, y: 0), (x: 0, y: 0)).a, (x: 0, y: 0));
      expect(gridSeamKey(gridSeam((x: 0, y: 0), (x: 1, y: 0))), '0,0-1,0');
      expect(gridSeamKey(gridSeam((x: 0, y: 1), (x: 0, y: 0))), '0,0-0,1');
    });

    test('一张卡的缝 = 所有相邻对（阅读序）；不相邻的格子不构成缝', () {
      expect(gridSeamsOf(row3().cells), [
        (a: (x: 0, y: 0), b: (x: 1, y: 0)),
        (a: (x: 1, y: 0), b: (x: 2, y: 0)),
      ]);
      expect(gridSeamsOf(square().cells), hasLength(4));
      // L 形只有两条缝（对角不算相邻）。
      expect(
        gridSeamsOf(const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)]),
        hasLength(2),
      );
    });
  });

  group('按「还连着的缝」分连通块', () {
    test('没剪断 = 一块；剪掉中间的缝 = 两块（阅读序）', () {
      final cells = row3().cells;
      expect(gridComponents(cells), hasLength(1));
      final cut = {gridSeam((x: 0, y: 0), (x: 1, y: 0))};
      final comps = gridComponents(cells, cuts: cut);
      expect(comps, hasLength(2));
      expect(comps.first, {(x: 0, y: 0)});
      expect(comps.last, {(x: 1, y: 0), (x: 2, y: 0)});
    });

    test('绕路还连着 → 剪一条缝也还只是一块', () {
      final comps = gridComponents(
        square().cells,
        cuts: {gridSeam((x: 0, y: 0), (x: 1, y: 0))},
      );
      expect(comps, hasLength(1), reason: '2×2 从下面绕过去了');
      expect(comps.single, hasLength(4));
    });

    test('空输入 → 空表', () {
      expect(gridComponents(const <GridCell>[]), isEmpty);
    });
  });

  group('把卡片按剪断的缝拆成几张卡', () {
    test('没真拆开时原样返回（连对象都是同一个）', () {
      final tile = square();
      final out = homeGridSplitTile(
        tile,
        cuts: {gridSeam((x: 0, y: 0), (x: 1, y: 0))},
      );
      expect(out, hasLength(1));
      expect(identical(out.single, tile), isTrue);
    });

    test('拆开后每张卡带自己的标题，服务一个都不丢、顺序是阅读序', () {
      final out = homeGridSplitTile(
        row3(),
        cuts: {gridSeam((x: 1, y: 0), (x: 2, y: 0))},
      );
      expect(out, hasLength(2));
      expect(out.first.titles, const ['A', 'B']);
      expect(out.first.cells, const [(x: 0, y: 0), (x: 1, y: 0)]);
      expect(out.last.titles, const ['C']);
      expect(out.last.cells, const [(x: 2, y: 0)]);
      expect(<String>[...out.first.titles, ...out.last.titles], const [
        'A',
        'B',
        'C',
      ]);
    });

    test('整份布局一起拆（拆分与不拆的卡片混在一起）', () {
      final out = homeGridSplitAll([
        row3(),
        HomeGridTile.single('Z', (x: 0, y: 3)),
      ], {gridSeam((x: 0, y: 0), (x: 1, y: 0))});
      expect(out, hasLength(3));
      expect(out.map((t) => t.key), contains('Z'));
      expect(out.where((t) => t.isGroup).length, 1);
    });
  });

  group('退出拆解模式：只有真分开的缝才留下', () {
    test('I 形剪中间两条缝（串联）→ 两条都算数', () {
      final cuts = {
        gridSeam((x: 0, y: 0), (x: 1, y: 0)),
        gridSeam((x: 1, y: 0), (x: 2, y: 0)),
      };
      expect(homeGridEffectiveCuts([row3()], cuts), cuts);
    });

    test('绕路还连着的缝 → 一条都不算数（要接回去）', () {
      // 2×2 剪掉上边那条缝：A 与 B 还能从下面绕过去（A-C、C-D、D-B 都连着）。
      final only = {gridSeam((x: 0, y: 0), (x: 1, y: 0))};
      expect(
        homeGridEffectiveCuts([square()], only),
        isEmpty,
        reason: '用户口径 2：两边还在其他地方相连 → 恢复此处连接',
      );
      // 两条水平缝一起剪：左右两列之间再没有别的通路 → 两条都算数（真的分开了）。
      final both = {
        gridSeam((x: 0, y: 0), (x: 1, y: 0)),
        gridSeam((x: 0, y: 1), (x: 1, y: 1)),
      };
      expect(homeGridEffectiveCuts([square()], both), both);
    });

    test('只剪一条、卡片仍然连着 → 不算数；剪成两块 → 算数', () {
      final middle = gridSeam((x: 1, y: 0), (x: 2, y: 0));
      final edge = gridSeam((x: 0, y: 0), (x: 1, y: 0));
      // I 形：剪右边那条 → 断成 (A,B) + (C)；剪左边那条 → 断成 (A) + (B,C)。
      expect(homeGridEffectiveCuts([row3()], {middle}), {middle});
      expect(homeGridEffectiveCuts([row3()], {edge}), {edge});
    });

    test('不属于任何卡片的缝被忽略（脏数据不炸）', () {
      final stranger = gridSeam((x: 9, y: 9), (x: 9, y: 10));
      expect(homeGridEffectiveCuts([row3()], {stranger}), isEmpty);
      expect(homeGridEffectiveCuts([row3()], <GridSeam>{}), isEmpty);
    });

    test('单格卡片没有缝可剪', () {
      final single = HomeGridTile.single('A', (x: 0, y: 0));
      expect(gridSeamsOf(single.cells), isEmpty);
      expect(homeGridEffectiveCuts([single], <GridSeam>{}), isEmpty);
    });
  });

  group('长按功能部分：把一格从卡里抠出来', () {
    test('单格卡片：抠出来的就是它自己，剩下什么都没有', () {
      final single = HomeGridTile.single('A', (x: 0, y: 0));
      final out = homeGridExtractCell(single, (x: 0, y: 0));
      expect(out.moved.titles, const ['A']);
      expect(out.moved.cells, const [(x: 0, y: 0)]);
      expect(out.rest, isEmpty);
    });

    test('L 形抠掉一个角：剩下两格仍连在一起（一张卡）', () {
      final l = HomeGridTile(
        titles: const ['A', 'B', 'C'],
        cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      final out = homeGridExtractCell(l, (x: 1, y: 0));
      expect(out.moved.titles, const ['B']);
      expect(out.rest, hasLength(1));
      expect(out.rest.single.titles, const ['A', 'C']);
      expect(out.rest.single.cells, const [(x: 0, y: 0), (x: 0, y: 1)]);
    });

    test('I 形抠掉中间那格：两边断成两张卡（各自带自己的标题）', () {
      final out = homeGridExtractCell(row3(), (x: 1, y: 0));
      expect(out.moved.titles, const ['B']);
      expect(out.rest, hasLength(2));
      expect(out.rest.first.titles, const ['A']);
      expect(out.rest.last.titles, const ['C']);
      expect(out.rest.last.cells, const [(x: 2, y: 0)]);
    });

    test('格子不在卡里时退化成第一格（容错，不抛异常）', () {
      final out = homeGridExtractCell(row3(), (x: 8, y: 8));
      expect(out.moved.cells, hasLength(1));
      expect(out.rest, hasLength(1));
      expect(out.rest.single.cells, hasLength(2));
    });
  });
}
