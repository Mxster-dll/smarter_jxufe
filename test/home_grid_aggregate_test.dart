/// 首页宫格聚合的**交互守卫**（长按拖动 / 边缘合并 / 虚线框 / 移动 / 嵌套 / 设置页兜底）。
///
/// 用户 2026-09-21 需求（逐字）：「宫格视图下，我希望增加聚合功能。现有的相当于每个
/// 宫格都是一个仅包含一个功能的卡片，我希望长按拖动后可以合并宫格 …… 长按拖动到其他
/// 卡片边边上时（必须要在某个边缘处，处于中间则此次拖动松手后不触发合并），松手后，
/// 合并到此边相邻的位置，然后并且未松手时，要在相应位置显示虚线框，如果没有与任何
/// 卡片相邻，则松手不触发合并。然后我们允许长按卡片调整位置（即使是异形的），并且要
/// 允许两个互补的卡片相互嵌套」。
///
/// ⚠ 拖动必须**分步移动**：`LongPressGestureRecognizer` 越过 touch slop 的那一次移动
/// 只触发 `onLongPressStart`、不作为 update 送达 —— 一步到位等于「按了一下」。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_card.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_metrics.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_grid.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards.dart';

/// 测试用最小宿主：持有布局并在拖动结果回写时重建（模拟 `home_screen` + store）。
class _Host extends StatefulWidget {
  final List<HomeServiceEntry> entries;
  final HomeGridLayout? initial;
  final List<HomeGridLayout> saved;
  final Key? boundaryKey;
  final bool splitMode;

  const _Host({
    required this.entries,
    required this.saved,
    this.initial,
    this.boundaryKey,
    this.splitMode = false,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  HomeGridLayout? _layout;

  @override
  void initState() {
    super.initState();
    _layout = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final grid = HomeServiceGrid(
      entries: widget.entries,
      layout: _layout,
      splitMode: widget.splitMode,
      onLayoutChanged: (next) {
        widget.saved.add(next);
        setState(() => _layout = next);
      },
    );
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: widget.boundaryKey == null
              ? grid
              : RepaintBoundary(key: widget.boundaryKey, child: grid),
        ),
      ),
    );
  }
}

void main() {
  const titles = ['A', 'B', 'C', 'D', 'E', 'F'];

  late Directory hiveDir;
  late Box<String> gridBox;

  /// setUp 里种进 box 的自定义布局（设置页用例要从「已自定义」状态开始）。
  final seededLayout = HomeGridLayout(
    cols: 3,
    tiles: [
      HomeGridTile(
        titles: const ['A', 'B'],
        cells: const [(x: 0, y: 0), (x: 1, y: 0)],
      ),
    ],
  );

  // 设置页那张卡会读 Hive 偏好（`homeLayoutStoreProvider` + `homeGridStoreProvider`），
  // 不初始化就会冒出未处理异步异常 —— 与 `test/settings_entry_test.dart` 同款处理。
  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('home_grid_aggregate_test');
    Hive.init(hiveDir.path);
    gridBox = await Hive.openBox<String>(homeGridPrefsBoxName);
  });

  setUp(() async {
    // ⚠ 写盘必须留在 `setUp`（真异步区）：`testWidgets` 的假异步区推不动 Hive 的
    // 真 I/O，在测试体里 `await box.put(...)` 会静默挂死到超时（实测）。
    await gridBox.clear();
    await gridBox.put(homeGridLayoutKey, homeGridLayoutJson(seededLayout));
  });
  tearDownAll(() {
    // ⚠ 收尾阶段 `await Hive.close()` 可能永远不返回（本仓踩过），不 await。
    unawaited(Hive.close());
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  HomeServiceEntry entry(String title) => HomeServiceEntry(
    icon: Icons.abc,
    title: title,
    subtitle: '副标题 $title',
    group: HomeServiceGroup.ims,
    accent: const Color(0xFFC3282E),
    builder: () => const SizedBox.shrink(),
    onTap: () {},
  );

  final entries = <HomeServiceEntry>[for (final t in titles) entry(t)];

  /// 只铺给定几个服务（自定义布局必须与目录对齐：`reconcile` 会把目录里多出来的
  /// 入口填进第一个空隙，空隙正好是测试要用的落点时就会把用例打歪）。
  List<HomeServiceEntry> someTitles(List<String> list) =>
      <HomeServiceEntry>[for (final t in list) entry(t)];

  /// 660 宽的视口 → [HomeGridMetrics] 给出 3 列 / 格宽 212 / 格高 88；
  /// 880 宽 → 4 列 / 格宽 211（「落点在空隙里、两侧都贴着卡片」那类用例要 4 列）。
  Future<List<HomeGridLayout>> pumpGrid(
    WidgetTester tester, {
    HomeGridLayout? initial,
    List<HomeServiceEntry>? customEntries,
    Key? boundaryKey,
    bool splitMode = false,
    Size viewSize = const Size(660, 1400),
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <HomeGridLayout>[];
    await tester.pumpWidget(
      _Host(
        entries: customEntries ?? entries,
        initial: initial,
        saved: saved,
        boundaryKey: boundaryKey,
        splitMode: splitMode,
      ),
    );
    await tester.pumpAndSettle();
    return saved;
  }

  /// 重新 pump 同一个宿主（State 复用 → 宫格的 `didUpdateWidget` 生效）——
  /// 用来切拆解模式：进入 / 退出都在这里发生（退出会结算剪断的缝）。
  Future<void> repumpGrid(
    WidgetTester tester,
    List<HomeGridLayout> saved, {
    bool splitMode = false,
    List<HomeServiceEntry>? customEntries,
  }) async {
    await tester.pumpWidget(
      _Host(
        entries: customEntries ?? entries,
        saved: saved,
        splitMode: splitMode,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 长按某个东西并拖到 [to]（分步移动）；返回手势供调用方决定何时松手。
  Future<TestGesture> longPressDragFrom(
    WidgetTester tester,
    Finder from,
    Offset to,
  ) async {
    final start = tester.getCenter(from);
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
    const steps = 6;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(start, to, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    return gesture;
  }

  /// 长按某张磁贴并拖到 [to]（分步移动）；返回手势供调用方决定何时松手。
  Future<TestGesture> longPressDragTo(
    WidgetTester tester,
    String fromTitle,
    Offset to,
  ) => longPressDragFrom(
    tester,
    find.byKey(Key('homeTile-$fromTitle')),
    to,
  );

  Key cardKey(List<String> titles) => Key('homeGridCard-${titles.join('\u001F')}');

  group('长按拖动 → 边缘合并', () {
    testWidgets('拖到别人右边缘：显示虚线框，松手合并成一张卡（两个服务一张卡）', (tester) async {
      final saved = await pumpGrid(tester);
      final aRect = tester.getRect(find.byKey(const Key('homeTile-A')));
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));

      final gesture = await longPressDragTo(
        tester,
        'A',
        Offset(bRect.right - 4, bRect.center.dy),
      );

      // 抬起的那张卡跟着指针走；原位置那张卡还在树里（识别器挂在它脸上，
      // 摘掉/换壳都会让拖动断在半路），只是被透明掉。
      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);
      final hiddenCard = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const Key('homeGridCard-A')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(hiddenCard.opacity, 0);
      // 未松手 → 落点画虚线框（合并时目标卡也淡染一层）。
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);
      expect(find.byKey(const Key('homeGridPreviewTarget')), findsOneWidget);
      expect(saved, isEmpty, reason: '还没松手，不该写任何布局');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final next = saved.single;
      expect(next.isValid, isTrue);
      expect(next.groupCount, 1);
      expect(next.allTitles.length, 6, reason: '一个服务都不能丢');
      // 合并后的卡片 = 乙 那格 + 落点那格（横向两张卡）。
      final group = next.tiles.firstWhere((t) => t.isGroup);
      expect(group.titles, const ['B', 'A']);
      expect(group.cells, const [(x: 1, y: 0), (x: 2, y: 0)]);

      // 界面上：一张卡两张脸。
      expect(find.byKey(cardKey(['B', 'A'])), findsOneWidget);
      expect(find.byKey(const Key('homeTile-A')), findsOneWidget);
      expect(find.byKey(const Key('homeTile-B')), findsOneWidget);
      final mergedRect = tester.getRect(find.byKey(cardKey(['B', 'A'])));
      expect(
        mergedRect.width,
        HomeGridMetrics.gap + 212 * 2,
        reason: '两张卡的宽度 + 中间一道标准缝',
      );
      expect(mergedRect.height, 88);
      // 被挤开的 C 挪到空出来的那格（A 原来的位置），没有卡片消失。
      expect(
        tester.getRect(find.byKey(const Key('homeTile-C'))).topLeft,
        aRect.topLeft,
      );
      // 合并给一条可撤销的提示（「长按 + 拖到边上」两个动作就能触发，容易误操作）。
      expect(find.byKey(const Key('homeGridMergedSnack')), findsOneWidget);
      expect(find.text('已合并「B」与「A」'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
      // 结构钉住：带 action 的 SnackBar **默认 persist = true**（本机 Flutter 的
      // `snack_bar.dart:303` 写着 `persist = persist ?? action != null`），而自动消失
      // 计时器的回调第一句就是 `if (snackBar.persist) return;` → 不显式写 false，
      // 这条提示会永远挂在底部（用户 2026-09-21 反馈的正是这个）。
      final mergedSnack = tester.widget<SnackBar>(
        find.byKey(const Key('homeGridMergedSnack')),
      );
      expect(mergedSnack.persist, isFalse);
      expect(mergedSnack.duration, const Duration(seconds: 5));
      // 提示必须自己走掉（用户 2026-09-21 反馈「合并后，底部的提示信息不消失」）。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('homeGridMergedSnack')),
        findsNothing,
        reason: '合并提示到点要自己消失，不能一直挂在底部',
      );
    });

    testWidgets('合并提示里的「撤销」把布局退回拖动前', (tester) async {
      final saved = await pumpGrid(tester);
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final gesture = await longPressDragTo(
        tester,
        'A',
        Offset(bRect.right - 4, bRect.center.dy),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(saved.single.groupCount, 1);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(saved, hasLength(2));
      expect(saved.last.groupCount, 0, reason: '撤销后回到两张独立卡片');
      expect(saved.last.tileByKey('A')?.cells, const [(x: 0, y: 0)]);
      expect(saved.last.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
      expect(find.byKey(cardKey(['B', 'A'])), findsNothing);
    });

    testWidgets('落点那格站着的卡片也一起并进来 → 三张一张卡，虚线框显示更大的形状', (tester) async {
      // 4 列：A(0,0) B(1,0) C(2,0)。A 拖到 B 的右边缘 → 落点 (2,0) 站着 C：
      // C 一起并进来并挪到 (3,0)。用户 2026-09-21 三轮口径（逐字）：
      // 「三张并成一张：C 也一起并进来（B + A + C 三格一张卡），虚线框显示这个更大的形状」。
      final saved = await pumpGrid(
        tester,
        viewSize: const Size(880, 1400),
        customEntries: someTitles(const ['A', 'B', 'C']),
        initial: HomeGridLayout(
          cols: 4,
          tiles: [
            HomeGridTile.single('A', (x: 0, y: 0)),
            HomeGridTile.single('B', (x: 1, y: 0)),
            HomeGridTile.single('C', (x: 2, y: 0)),
          ],
        ),
      );
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final gesture = await longPressDragTo(
        tester,
        'A',
        Offset(bRect.right - 4, bRect.center.dy),
      );

      // 虚线框 = 合并后的那一整张（从 B 的左边缘一直连到 C 挪过去之后的右边缘）。
      final preview = tester.getRect(find.byKey(const Key('homeGridPreview')));
      expect(preview.left, closeTo(bRect.left, 0.5));
      expect(preview.width, closeTo(211 * 3 + HomeGridMetrics.gap * 2, 0.5));
      expect(preview.height, 88);
      // 三张卡各淡染一层（第一张沿用老 key，其余按卡片 key 区分）。
      expect(find.byKey(const Key('homeGridPreviewTarget')), findsOneWidget);
      expect(find.byKey(const Key('homeGridPreviewTarget-C')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final merged = saved.single.tiles.single;
      expect(merged.titles, const ['B', 'A', 'C']);
      expect(merged.cells, const [(x: 1, y: 0), (x: 2, y: 0), (x: 3, y: 0)]);
      // 虚线框承诺的形状 = 落盘后那张卡的形状（这是两轮反馈的核心不变量）。
      final cardRect = tester.getRect(find.byKey(cardKey(['B', 'A', 'C'])));
      expect(cardRect.left, closeTo(preview.left, 0.5));
      expect(cardRect.width, closeTo(preview.width, 0.5));
      expect(cardRect.height, closeTo(preview.height, 0.5));
      // 三张一起并 → 提示里把三张都点名（两张时仍是老的「已合并「B」与「A」」）。
      expect(find.text('已合并 3 张卡片：「B」「C」「A」'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('虚线框画的就是合并后的整张卡（不是贴在旁边的一个独立方框）', (tester) async {
      await pumpGrid(tester);
      final aRect = tester.getRect(find.byKey(const Key('homeTile-A')));
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final cRect = tester.getRect(find.byKey(const Key('homeTile-C')));

      final gesture = await longPressDragTo(
        tester,
        'A',
        Offset(bRect.right - 4, bRect.center.dy),
      );
      // 落点那格原本站着 C（满格 → 让它让位，不并它）：虚线框仍是 B + 落点两格，
      // 而不是「C 那一格」一个孤立方框。
      final preview = tester.getRect(find.byKey(const Key('homeGridPreview')));
      expect(preview.left, closeTo(bRect.left, 0.5));
      expect(preview.width, closeTo(HomeGridMetrics.gap + 212 * 2, 0.5));
      expect(
        preview.left,
        lessThan(cRect.left),
        reason: '虚线框必须从目标卡开始（贴上去），不是只画落点那一格',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      final cardRect = tester.getRect(find.byKey(cardKey(['B', 'A'])));
      expect(cardRect.left, closeTo(preview.left, 0.5));
      expect(cardRect.width, closeTo(preview.width, 0.5));
      expect(cardRect.top, closeTo(preview.top, 0.5));
      expect(aRect.left, isNot(closeTo(preview.left, 0.5)));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('满格一行：后续卡片被往后顶一位（未松手时先画出它们的新位置）', (tester) async {
      // 5 列：A..E 铺满第一行。A 拖到 B 右边缘 → 落点 (2,0) 站着 C：
      // C 并进来挪到 (3,0)，D 被顶到 (4,0)，E 再顶就越界 → 交给让位。
      final saved = await pumpGrid(
        tester,
        viewSize: const Size(1100, 1400),
        customEntries: someTitles(const ['A', 'B', 'C', 'D', 'E']),
        initial: HomeGridLayout.flow(
          titles: const ['A', 'B', 'C', 'D', 'E'],
          cols: 5,
        ),
      );
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final gesture = await longPressDragTo(
        tester,
        'A',
        Offset(bRect.right - 4, bRect.center.dy),
      );
      // 未松手：合并形状（3 格）+ 被顶开的 D 的新位置（细实线框）都画出来了。
      final preview = tester.getRect(find.byKey(const Key('homeGridPreview')));
      expect(preview.left, closeTo(bRect.left, 0.5));
      final pushedKey = find.byKey(const Key('homeGridPreviewPush-D'));
      expect(pushedKey, findsOneWidget);
      expect(
        tester.getRect(pushedKey).left,
        greaterThan(preview.right),
        reason: 'D 被顶到合并卡右边那一格',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final next = saved.single;
      expect(next.tileByKey('B\u001FA\u001FC')?.cells, const [
        (x: 1, y: 0),
        (x: 2, y: 0),
        (x: 3, y: 0),
      ]);
      expect(next.tileByKey('D')?.cells, const [(x: 4, y: 0)]);
      expect(next.tileByKey('E')?.cells, const [(x: 0, y: 0)]);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('拖到卡片中间：不合并、不移动（用户口径）', (tester) async {
      final saved = await pumpGrid(tester);
      final aRect = tester.getRect(find.byKey(const Key('homeTile-A')));
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));

      final gesture = await longPressDragTo(tester, 'A', bRect.center);
      expect(find.byKey(const Key('homeGridPreview')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, isEmpty);
      expect(tester.getRect(find.byKey(const Key('homeTile-A'))).topLeft, aRect.topLeft);
      expect(find.byKey(cardKey(['B', 'A'])), findsNothing);
    });

    testWidgets('拖到空格：只挪位置，不合并', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C']),
        initial: HomeGridLayout(
          cols: 3,
          tiles: [
            HomeGridTile.single('A', (x: 0, y: 0)),
            HomeGridTile.single('B', (x: 1, y: 0)),
            HomeGridTile.single('C', (x: 0, y: 2)),
          ],
        ),
      );
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final gesture = await longPressDragTo(
        tester,
        'C',
        bRect.center + const Offset(224, 0), // 右边那格（空着）
      );
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);
      expect(find.byKey(const Key('homeGridPreviewTarget')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.groupCount, 0);
      expect(saved.single.tileByKey('C')?.cells, const [(x: 2, y: 0)]);
      // 别人一格都没动。
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('异形卡片（L 形）也能整张长按拖动', (tester) async {
      final l = HomeGridTile(
        titles: const ['A', 'B', 'C'],
        cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      final saved = await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C', 'D']),
        initial: HomeGridLayout(
          cols: 3,
          tiles: [l, HomeGridTile.single('D', (x: 2, y: 2))],
        ),
      );
      // 用户 2026-09-21 四轮口径：「长按到功能部分时，只移动此功能」+「卡片其余部分
      // 移动整个卡片」→ 拖**整张卡**要从格与格之间的缝（`homeGridBody-…` 手势带）起手。
      const bandKey = Key('homeGridBody-0,0-1,0');
      final bandCenter = tester.getCenter(find.byKey(bandKey));
      final gesture = await longPressDragFrom(
        tester,
        find.byKey(bandKey),
        bandCenter + const Offset(224, 100),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.tileByKey('A\u001FB\u001FC')?.cells, const [
        (x: 1, y: 1),
        (x: 2, y: 1),
        (x: 1, y: 2),
      ]);
      expect(saved.single.isValid, isTrue);
    });
  });

  group('互补嵌合', () {
    testWidgets('把一张卡拖进异形卡片的缺口（嵌套）', (tester) async {
      final l = HomeGridTile(
        titles: const ['A', 'B', 'C'],
        cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      final saved = await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C', 'D']),
        initial: HomeGridLayout(
          cols: 3,
          tiles: [l, HomeGridTile.single('D', (x: 2, y: 2))],
        ),
      );
      final lRect = tester.getRect(find.byKey(cardKey(['A', 'B', 'C'])));
      // 缺口 = L 的包围盒里右下那格 (1,1)。
      final notch = lRect.topLeft + const Offset(224 + 106, 100 + 44);
      final gesture = await longPressDragTo(tester, 'D', notch);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.tileByKey('D')?.cells, const [(x: 1, y: 1)]);
      // L 一格没动；D 的界面矩形落在 L 的包围盒内部 → 真的嵌进去了。
      expect(saved.single.tileByKey('A\u001FB\u001FC')?.cells, l.cells);
      final dRect = tester.getRect(find.byKey(const Key('homeTile-D')));
      expect(dRect.left, greaterThan(lRect.left));
      expect(dRect.top, greaterThan(lRect.top));
      expect(dRect.right, lessThanOrEqualTo(lRect.right));
      expect(dRect.bottom, lessThanOrEqualTo(lRect.bottom));
    });

    testWidgets('L 形 + 1 格从缺口那侧并进去 → 合并成一个矩形卡片', (tester) async {
      final l = HomeGridTile(
        titles: const ['A', 'B', 'C'],
        cells: const [(x: 0, y: 0), (x: 1, y: 0), (x: 0, y: 1)],
      );
      final saved = await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C', 'D']),
        initial: HomeGridLayout(
          cols: 3,
          tiles: [l, HomeGridTile.single('D', (x: 2, y: 2))],
        ),
      );
      // 指针落在 L 的 (0,1) 那格的右边缘（右邻是缺口 → 外露边）。
      final cCenter = tester.getCenter(find.byKey(const Key('homeTile-C')));
      final gesture = await longPressDragTo(
        tester,
        'D',
        cCenter + const Offset(106 - 6, 0),
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final group = saved.single.tiles.firstWhere((t) => t.isGroup);
      expect(group.cells.length, 4);
      expect(group.width, 2);
      expect(group.height, 2);
      expect(group.cells, const [
        (x: 0, y: 0),
        (x: 1, y: 0),
        (x: 0, y: 1),
        (x: 1, y: 1),
      ]);
      await tester.pump(const Duration(seconds: 6)); // 收尾 SnackBar 计时器
    });
  });

  group('合并后是「一张卡」的像素证据', () {
    // 用户 2026-09-21 四轮口径 1：「我希望功能与功能之间不显示分割线」——
    // 普通模式下缝上**什么都不画**（既没有卡片描边，也没有分隔短线）。
    testWidgets('两个格子之间什么都没有：没有分割线、也没有卡片描边（浅色）', (tester) async {
      final shotKey = GlobalKey();
      await pumpGrid(
        tester,
        boundaryKey: shotKey,
        initial: HomeGridLayout(
          cols: 3,
          tiles: [
            HomeGridTile(
              titles: const ['A', 'B'],
              cells: const [(x: 0, y: 0), (x: 1, y: 0)],
            ),
            HomeGridTile.single('C', (x: 2, y: 0)),
          ],
        ),
      );

      final gridOrigin = tester.getTopLeft(find.byKey(shotKey));
      final card = tester.getRect(find.byKey(cardKey(['A', 'B'])));
      final left = (card.left - gridOrigin.dx).round();
      final top = (card.top - gridOrigin.dy).round();
      final bottom = (card.bottom - gridOrigin.dy).round();
      final seamX = left + 212 + (HomeGridMetrics.gap / 2).round();
      final pixels = await _capture(tester, shotKey);

      // ① 整条缝上都不许出现异色（= 一张卡，且没有分割线）。
      for (var y = top + 2; y <= bottom - 2; y++) {
        expect(
          pixels.luminance(seamX, y),
          greaterThan(250),
          reason: '($seamX,$y) 出现异色 → 功能之间被画了分割线或卡片描边',
        );
      }
      // ② 卡片自己的外描边照旧在（证明扫描有效、不是整片纯白）。
      var borderFound = false;
      for (var y = top + 2; y <= bottom - 2; y++) {
        for (var x = left - 1; x <= left + 1; x++) {
          if (pixels.luminance(x, y) < 250) borderFound = true;
        }
      }
      expect(borderFound, isTrue, reason: '卡片外缘应该有淡描边');
    });
  });

  group('拆解模式（用户 2026-09-21 四轮）', () {
    const seamAB = Key('homeGridSeam-0,0-1,0');
    final three = someTitles(const ['A', 'B', 'C']);

    HomeGridLayout twoInARow() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 0)),
      ],
    );

    /// 缝上那条线的画笔：`dashGap == 0` = 实线（还连着），`> 0` = 虚线（断开了）。
    HomeGridDashedPainter seamPainter(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(seamAB),
          matching: find.byType(CustomPaint),
        ),
      );
      return paint.painter! as HomeGridDashedPainter;
    }

    testWidgets('普通模式不画分割线；进拆解模式才画，画面是实线', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      expect(
        find.byKey(seamAB),
        findsNothing,
        reason: '用户口径 1：功能与功能之间不显示分割线',
      );
      expect(saved, isEmpty);

      await repumpGrid(tester, saved, splitMode: true, customEntries: three);

      expect(
        find.byKey(seamAB),
        findsOneWidget,
        reason: '用户口径 2：拆解模式下才显示分割线',
      );
      expect(seamPainter(tester).dashGap, 0, reason: '没断开的缝画实线');
      expect(saved, isEmpty, reason: '只是进出模式，布局不该变');
    });

    testWidgets('点分割线：这边断开、卡片当场分成两张，边界变虚线', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        splitMode: true,
      );
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);

      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(find.byKey(cardKey(['A', 'B'])), findsNothing);
      expect(find.byKey(const Key('homeGridCard-A')), findsOneWidget);
      expect(find.byKey(const Key('homeGridCard-B')), findsOneWidget);
      expect(
        seamPainter(tester).dashGap,
        greaterThan(0),
        reason: '用户口径 2：形成的边界暂时显示为虚线',
      );
      final ra = tester.getRect(find.byKey(const Key('homeGridCard-A')));
      final rb = tester.getRect(find.byKey(const Key('homeGridCard-B')));
      expect(rb.left - ra.right, HomeGridMetrics.gap, reason: '断开后是两张独立的卡');
      expect(saved, isEmpty, reason: '拆解模式里先不落盘，退出时才结算');
    });

    testWidgets('再点一次那条虚线：接回成一张卡', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        splitMode: true,
      );
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey(['A', 'B'])), findsNothing);

      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);
      expect(seamPainter(tester).dashGap, 0);
      await repumpGrid(tester, saved, splitMode: false, customEntries: three);
      expect(saved, isEmpty, reason: '又接回去了 → 退出时没有任何要落盘的');
    });

    testWidgets('绕路还连着的缝：退出拆解模式自动接回去（布局不变）', (tester) async {
      final four = someTitles(const ['A', 'B', 'C', 'D']);
      final square = HomeGridLayout(
        cols: 2,
        tiles: [
          HomeGridTile(
            titles: const ['A', 'B', 'C', 'D'],
            cells: const [
              (x: 0, y: 0),
              (x: 1, y: 0),
              (x: 0, y: 1),
              (x: 1, y: 1),
            ],
          ),
        ],
      );
      final saved = await pumpGrid(
        tester,
        customEntries: four,
        initial: square,
        splitMode: true,
      );

      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cardKey(['A', 'B', 'C', 'D'])),
        findsOneWidget,
        reason: '2×2 从下面绕过去了 → 卡片没有分成两张',
      );
      expect(seamPainter(tester).dashGap, greaterThan(0), reason: '缝本身是断开的');

      await repumpGrid(tester, saved, splitMode: false, customEntries: four);

      expect(saved, isEmpty, reason: '用户口径 2：还连着的缝要恢复连接，不落盘');
      expect(find.byKey(cardKey(['A', 'B', 'C', 'D'])), findsOneWidget);
    });

    testWidgets('真分成两块的缝：退出拆解模式落盘成两张卡，服务不丢', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        splitMode: true,
      );
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      await repumpGrid(tester, saved, splitMode: false, customEntries: three);

      expect(saved, hasLength(1));
      expect(saved.single.isValid, isTrue);
      expect(saved.single.groupCount, 0);
      expect(saved.single.allTitles.length, 3, reason: '一个服务都不能丢');
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 0)]);
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('拆解模式里不响应长按拖动（模式内只做断开 / 接回）', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        splitMode: true,
      );
      final aCenter = tester.getCenter(find.byKey(const Key('homeTile-A')));
      final gesture = await longPressDragFrom(
        tester,
        find.byKey(const Key('homeTile-A')),
        aCenter + const Offset(0, 100),
      );
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
    });
  });

  group('长按功能部分 vs 卡片其余部分（用户 2026-09-21 四轮口径 3）', () {
    final three = someTitles(const ['A', 'B', 'C']);

    HomeGridLayout twoInARow() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 0)),
      ],
    );

    testWidgets('长按某个功能：只抬起这一格，原卡其余部分留在原地', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      final aCenter = tester.getCenter(find.byKey(const Key('homeTile-A')));
      // 往下一格（空位）拖 → 纯移动。
      final gesture = await longPressDragFrom(
        tester,
        find.byKey(const Key('homeTile-A')),
        aCenter + const Offset(0, 100),
      );

      final lifted = tester.getRect(find.byKey(const Key('homeGridLifted')));
      // 抬起的那张卡带 1.02 的缩放（拖动视觉），所以按比例核对。
      expect(
        lifted.width,
        closeTo(212 * 1.02, 0.5),
        reason: '只抬起这一个功能，不是整张卡',
      );
      expect(lifted.height, closeTo(88 * 1.02, 0.5));
      // 原卡那一格空出来（剩下 B 还在原地）。
      expect(find.byKey(const Key('homeTile-B')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      expect(saved.single.isValid, isTrue);
      expect(saved.single.allTitles.length, 3);
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 1)]);
      expect(
        saved.single.tileByKey('B')?.cells,
        const [(x: 1, y: 0)],
        reason: '原卡其余部分留在原地（不被一起搬走）',
      );
    });

    testWidgets('长按卡片其余部分（格与格之间的缝）：整张卡一起动', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      const bandKey = Key('homeGridBody-0,0-1,0');
      final bandCenter = tester.getCenter(find.byKey(bandKey));
      final gesture = await longPressDragFrom(
        tester,
        find.byKey(bandKey),
        bandCenter + const Offset(0, 100),
      );

      final lifted = tester.getRect(find.byKey(const Key('homeGridLifted')));
      expect(
        lifted.width,
        closeTo((212 * 2 + HomeGridMetrics.gap) * 1.02, 0.5),
        reason: '抬起的是整张卡',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      // 整张卡一起走：两个格子都往下挪了一格（卡片身份 = 两个服务那张卡）。
      expect(saved.single.tileByKey('A\u001FB')?.cells, const [
        (x: 0, y: 1),
        (x: 1, y: 1),
      ]);
      expect(saved.single.tileByKey('C')?.cells, const [(x: 2, y: 0)]);
    });
  });

  group('拐弯内侧是圆角（用户 2026-09-21 第三轮）', () {
    // 用户原话：「卡片在拐弯的时候，内侧会有一个突起，我希望做成圆角」。
    // 旧写法 = 逐格画圆角矩形再做布尔并 → 拐弯内侧、格缝交叉处留一个 12×12 的方角突起
    // （每格矩形都要「往外扩一个缝宽」去补格缝，补出来的就是这个突起）；
    // 新写法 = 取形状的轮廓环 + 每个 90° 转角倒圆角（凸角收圆、**凹角也倒圆**）。
    const lCells = <GridCell>[
      (x: 0, y: 0),
      (x: 1, y: 0),
      (x: 0, y: 1),
    ];

    test('L 形路径：内侧拐角是半径 12 的倒圆角，缺口不会被填上', () {
      // 手算用度量：格宽 100 / 格高 50 / 缝 12 → 第 1 条竖格线在 100、横格线在 50
      const metrics = HomeGridMetrics(
        compact: false,
        cols: 3,
        cellWidth: 100,
        cellHeight: 50,
      );
      final path = homeGridShapePath(
        cells: lCells,
        origin: (x: 0, y: 0),
        metrics: metrics,
      );
      // 外框仍然恰好落在包围盒上（2 格 + 1 缝 ✕ 2 格 + 1 缝）
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 212, 112));

      // 拐角 (100,50)：倒圆角的圆心在 (112,62)、半径 12 → 圆心附近（缺口一侧）没有卡
      expect(
        path.contains(const Offset(108, 54)),
        isFalse,
        reason: '拐弯内侧的方角突起（旧写法这里是 12×12 的实心方角）',
      );
      expect(
        path.contains(const Offset(124, 74)),
        isFalse,
        reason: '缺口区域不许被倒圆角填上',
      );
      // 倒角是弧、不是方切：弧与角点之间那一小块肉要留着
      expect(path.contains(const Offset(102, 51)), isTrue);
      // 两个切点两侧的肉照旧在
      expect(path.contains(const Offset(112, 49)), isTrue);
      expect(path.contains(const Offset(99, 62)), isTrue);
      // 外露角照旧是 12 圆角
      expect(path.contains(const Offset(2, 2)), isFalse);
      expect(path.contains(const Offset(12, 1)), isTrue);
    });

    test('P 形（缺角在左下）：拐角贴着**右边那格**的左边，差一个缝宽都要抓住', () {
      // 用户自己的聚合形状：上排 3 格 + 下排右侧 2 格，缺角在左下。
      // 这条同时守住「格线 = 两条边」的口径：拐角后的竖边必须落在第 1 列的**左边**
      // （`1 * 步距` = 112），而不是第 0 列的右边（`1 * 格宽` = 100）——差一个缝宽。
      const metrics = HomeGridMetrics(
        compact: false,
        cols: 3,
        cellWidth: 100,
        cellHeight: 50,
      );
      final path = homeGridShapePath(
        cells: const [
          (x: 0, y: 0),
          (x: 1, y: 0),
          (x: 2, y: 0),
          (x: 1, y: 1),
          (x: 2, y: 1),
        ],
        origin: (x: 0, y: 0),
        metrics: metrics,
      );
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 324, 112));
      // 下排的左边 = 第 1 列的左边 = 112
      expect(path.contains(const Offset(113, 100)), isTrue);
      expect(
        path.contains(const Offset(105, 100)),
        isFalse,
        reason: '把格线当成第 0 列的右边（100）就会多吃一个缝宽',
      );
      expect(path.contains(const Offset(111, 100)), isFalse);
      // 拐角 (112,50)：倒圆角的圆心在 (100,62)、半径 12
      // ① 缺角一侧：贴着弧的那一小块肉是倒圆角补出来的（不是方角，也不是空的）
      expect(path.contains(const Offset(110, 52)), isTrue, reason: '倒圆角补出的那点肉');
      // ② 弧线之内（圆盘里、缺角一带）不是卡
      expect(
        path.contains(const Offset(107, 55)),
        isFalse,
        reason: '缺角已经被倒成圆弧，圆盘内不该有卡',
      );
      // ③ 直角边之外的列照旧是卡（x > 112 属于下排第 1 列）
      expect(path.contains(const Offset(118, 51)), isTrue);
      expect(path.contains(const Offset(114, 52)), isTrue);
      // 上排右边照旧到包围盒右缘
      expect(path.contains(const Offset(322, 10)), isTrue);
      expect(path.contains(const Offset(20, 120)), isFalse, reason: '下排左边没有卡');
    });

    test('中心挖洞的卡片：洞是第二个环，非零填充把洞留空', () {
      const metrics = HomeGridMetrics(
        compact: false,
        cols: 3,
        cellWidth: 100,
        cellHeight: 50,
      );
      final path = homeGridShapePath(
        cells: const [
          (x: 0, y: 0),
          (x: 1, y: 0),
          (x: 2, y: 0),
          (x: 0, y: 1),
          (x: 2, y: 1),
          (x: 0, y: 2),
          (x: 1, y: 2),
          (x: 2, y: 2),
        ],
        origin: (x: 0, y: 0),
        metrics: metrics,
      );
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 324, 174));
      expect(path.contains(const Offset(5, 5)), isTrue, reason: '外环仍是卡');
      expect(
        path.contains(const Offset(162, 87)),
        isFalse,
        reason: '洞的中间必须是空的（两个反向环，非零填充挖空）',
      );
    });

    test('1×1 卡片仍是圆角矩形（轮廓环退化不改老行为）', () {      const metrics = HomeGridMetrics(
        compact: false,
        cols: 1,
        cellWidth: 100,
        cellHeight: 50,
      );
      final path = homeGridShapePath(
        cells: const [(x: 0, y: 0)],
        origin: (x: 0, y: 0),
        metrics: metrics,
      );
      expect(path.getBounds(), const Rect.fromLTRB(0, 0, 100, 50));
      expect(path.contains(const Offset(1, 1)), isFalse, reason: '角被圆掉');
      expect(path.contains(const Offset(50, 25)), isTrue);
      expect(path.contains(const Offset(99, 1)), isFalse);
    });

    testWidgets('L 形卡片：描边随弧线走，12px 处的方角竖边已经没了', (tester) async {
      final shotKey = GlobalKey();
      await pumpGrid(
        tester,
        boundaryKey: shotKey,
        customEntries: someTitles(const ['A', 'B', 'C']),
        initial: HomeGridLayout(
          cols: 3,
          tiles: [
            HomeGridTile(titles: const ['A', 'B', 'C'], cells: lCells),
          ],
        ),
      );

      final gridOrigin = tester.getTopLeft(find.byKey(shotKey));
      final card = tester.getRect(find.byKey(cardKey(['A', 'B', 'C'])));
      // 660 宽 → 3 列、格宽 212、格高 88；内拐角 = 包围盒上的（1 格宽, 1 格高）。
      // 倒圆角的圆心 = 拐角 + (12, 12)，半径 12（`kAppCardRadius`）。
      final cornerX = card.left + 212;
      final cornerY = card.top + 88;
      final pixels = await _capture(tester, shotKey);
      int alphaAt(double dx, double dy) => pixels.alpha(
        (cornerX + dx - gridOrigin.dx).round(),
        (cornerY + dy - gridOrigin.dy).round(),
      );

      // ① 旧写法在拐角右下方铺着一个 12×12 的方角突起（含它右边那条竖描边）；
      //    新写法那里是倒圆角的切口 —— 这几处在弧线内侧 3px 以上，必须什么都没画。
      for (final p in const <({double dx, double dy})>[
        (dx: 12, dy: 4),
        (dx: 12, dy: 6),
        (dx: 10, dy: 6),
        (dx: 8, dy: 6),
      ]) {
        expect(
          alphaAt(p.dx, p.dy),
          0,
          reason: '内侧拐角右下方 (${p.dx}, ${p.dy}) 处被画了东西 → 方角突起又回来了',
        );
      }
      // ② 弧线确实画出来了，而且是**弧**：行数越往下，卡片的右边界越靠左
      //    （旧写法的方角突起在那三行都是同一条 x = 拐角 + 12 的直边）
      int lastInk(double dy) {
        for (var dx = 20; dx >= -2; dx--) {
          if (alphaAt(dx.toDouble(), dy) > 0) return dx;
        }
        return -99;
      }

      final near = lastInk(1);
      final mid = lastInk(5);
      final far = lastInk(9);
      expect(near, greaterThanOrEqualTo(0), reason: '拐角处没有画东西（倒圆角没画出来）');
      expect(mid, greaterThanOrEqualTo(0), reason: '拐角处没有画东西（倒圆角没画出来）');
      expect(far, greaterThanOrEqualTo(0), reason: '拐角处没有画东西（倒圆角没画出来）');
      expect(near, greaterThan(mid), reason: '弧线应随行数变高而左移（直边不会）');
      expect(mid, greaterThan(far), reason: '弧线应随行数变高而左移（直边不会）');
      // ③ 卡片外缘描边照旧（证明描边整体没丢、扫描有效）
      var edge = false;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = 18; dx <= 22; dx++) {
          if (pixels.alpha(
                (card.left + dx - gridOrigin.dx).round(),
                (card.top + dy - gridOrigin.dy).round(),
              ) >
              0) {
            edge = true;
          }
        }
      }
      expect(edge, isTrue, reason: '卡片外缘应该有淡描边');
    });
  });

  group('设置页兜底', () {
    test('布局存取：save 落盘、reset 删键回默认', () async {
      // 纯 Dart 用例（真异步区）：Hive 的 await 在这里能正常 resume。
      final store = HomeGridStore();
      await store.ensureLoaded();
      expect(store.hasCustomLayout, isTrue, reason: 'setUp 已种了一份自定义布局');
      expect(store.layout, seededLayout);

      await store.reset();
      expect(store.layout, isNull);
      expect(store.hasCustomLayout, isFalse);
      expect(gridBox.get(homeGridLayoutKey), isNull, reason: 'reset 必须把存档删掉');

      await store.save(seededLayout);
      expect(store.layout, seededLayout);
      expect(
        homeGridLayoutFromJson(gridBox.get(homeGridLayoutKey)),
        seededLayout,
        reason: '拖动结果要真的写进 box',
      );
    });

    testWidgets('「恢复默认布局」清掉自定义布局，并显示当前状态', (tester) async {
      // 设置卡比默认 800×600 视口高，按钮会落在屏幕外 → 先开高视口再点。
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // ⚠ store 必须在**测试体之外**先把盘读完（`setUp` 真异步区）：
      // 假异步区里 `await` 一个真异步区创建的 Future 永远不 resume（实测），
      // 那样页面会停在「正在读取」而 reset 也永远走不完。
      final store = HomeGridStore();
      await tester.runAsync(store.ensureLoaded);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeGridStoreProvider.overrideWith((ref) => store)],
          child: const MaterialApp(
            home: Scaffold(body: SettingsHomeLayoutCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已自定义：1 张卡片，其中 1 张是聚合卡片。'), findsOneWidget);
      expect(find.text('宫格聚合'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('homeGridReset')));
      await tester.tap(find.byKey(const Key('homeGridReset')));
      await tester.pump();
      // 让真异步区把 `reset()` 剩下的部分跑完（它 await 的是真异步区的 Future）。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();

      expect(store.layout, isNull);
      expect(find.text('当前为默认布局（未自定义）。'), findsOneWidget);
    });
  });
}

/// 抓 RepaintBoundary 的像素（`toImage` 走真异步，必须包 `runAsync`）。
Future<_Pixels> _capture(WidgetTester tester, Key key) async {
  late _Pixels shot;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    shot = _Pixels(data!, image.width, image.height);
    image.dispose();
  });
  return shot;
}

class _Pixels {
  final ByteData data;
  final int width;
  final int height;

  _Pixels(this.data, this.width, this.height);

  /// 亮度（0..255）—— 白卡 ≈ 255，淡描边 ≈ 226。
  int luminance(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return -1;
    final i = (y * width + x) * 4;
    return (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) ~/ 3;
  }

  /// 不透明度（0..255）—— 卡片轮廓只画在形状内部，形状外的像素是**透明**的
  /// （`RepaintBoundary` 只包住宫格，Scaffold 底色在它外面）。
  int alpha(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return -1;
    return data.getUint8((y * width + x) * 4 + 3);
  }
}
