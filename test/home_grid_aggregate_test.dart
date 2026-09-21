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
///
/// ⚠ **新增用例组请插在「设置页兜底」之前**（它是文件里最后一个组，历史上一直如此）：
/// 实测把新组追加在它后面，新组的第一个用例会**静默挂死** —— 600s 内零输出、
/// `--timeout 45s` 也不生效（用例体没有 await，是同步自旋），
/// `--name '恢复默认布局|功能的抓取区'` 可复现；把同一组挪到它前面（或单独跑）全绿。
/// 根因未定位（`设置页兜底` 的 widget 用例用 `runAsync` + 真 Hive + ProviderScope），
/// 与业务代码无关，先按位置规避。
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

import 'package:smarter_jxufe/features/home/data/home_edit_mode.dart';
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
  final bool editMode;

  const _Host({
    required this.entries,
    required this.saved,
    this.initial,
    this.boundaryKey,
    this.editMode = false,
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
      editMode: widget.editMode,
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

  HomeServiceEntry entry(String title, {void Function(String title)? onTap}) =>
      HomeServiceEntry(
        icon: Icons.abc,
        title: title,
        subtitle: '副标题 $title',
        group: HomeServiceGroup.ims,
        accent: const Color(0xFFC3282E),
        builder: () => const SizedBox.shrink(),
        onTap: onTap == null ? () {} : () => onTap(title),
      );

  final entries = <HomeServiceEntry>[for (final t in titles) entry(t)];

  /// 只铺给定几个服务（自定义布局必须与目录对齐：`reconcile` 会把目录里多出来的
  /// 入口填进第一个空隙，空隙正好是测试要用的落点时就会把用例打歪）。
  List<HomeServiceEntry> someTitles(
    List<String> list, {
    void Function(String title)? onTap,
  }) => <HomeServiceEntry>[for (final t in list) entry(t, onTap: onTap)];

  /// 660 宽的视口 → [HomeGridMetrics] 给出 3 列 / 格宽 212 / 格高 88；
  /// 880 宽 → 4 列 / 格宽 211（「落点在空隙里、两侧都贴着卡片」那类用例要 4 列）。
  Future<List<HomeGridLayout>> pumpGrid(
    WidgetTester tester, {
    HomeGridLayout? initial,
    List<HomeServiceEntry>? customEntries,
    Key? boundaryKey,
    bool editMode = false,
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
        editMode: editMode,
      ),
    );
    await tester.pumpAndSettle();
    return saved;
  }

  /// 重新 pump 同一个宿主（State 复用 → 宫格的 `didUpdateWidget` 生效）——
  /// 用来切编辑模式：进入 / 退出都在这里发生（退出会结算剪断的缝）。
  Future<void> repumpGrid(
    WidgetTester tester,
    List<HomeGridLayout> saved, {
    bool editMode = false,
    List<HomeServiceEntry>? customEntries,
  }) async {
    await tester.pumpWidget(
      _Host(
        entries: customEntries ?? entries,
        saved: saved,
        editMode: editMode,
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

    testWidgets('两张「相邻」的卡也并得起来 —— 服务一格没动同样算合并', (tester) async {
      // 用户 2026-09-21 八轮：「现在合并会有问题，始终合并不起来」。
      // 根因：两张卡本来就相邻时（拆解过、或拖回来放好了），把它们并起来**每个服务占的格子
      // 一格都没动**（并前 A@0,0 + B@1,0，并后还是 A@0,0 + B@1,0）→ 被「原地松手不写库」
      // 那条语义指纹早退（`_layoutSignature`）吞掉。合并一定改变分卡方式 → `isMerge` 放行。
      final saved = await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C']),
        initial: HomeGridLayout(
          cols: 3,
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
        Offset(bRect.left + 4, bRect.center.dy),
      );
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1), reason: '相邻两张卡也得并得起来（否则就是这一轮的回归）');
      expect(saved.single.groupCount, 1);
      expect(saved.single.tileByKey('A\u001FB')?.cells, const [
        (x: 0, y: 0),
        (x: 1, y: 0),
      ]);
      expect(saved.single.tileByKey('C')?.cells, const [(x: 2, y: 0)]);
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);
      expect(find.text('已合并「B」与「A」'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
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

    testWidgets('拖到卡片中间：不合并，但把压到的卡片挤开（用户 2026-09-21 十二轮）', (
      tester,
    ) async {
      // 用户原话：「我希望添加碰撞移动的功能，就是像手机桌面一样，既要支持合并
      // 也要支持把卡片挤开」→ 老口径「拖到中间松手什么都不做」已作废。
      final saved = await pumpGrid(tester);
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));

      final gesture = await longPressDragTo(tester, 'A', bRect.center);
      // 未松手：落点的虚线框 + 被挤开的 B 的新位置（细实线框）都画出来了。
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);
      expect(find.byKey(const Key('homeGridPreviewPush-B')), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final next = saved.single;
      expect(next.isValid, isTrue);
      expect(next.allTitles.length, titles.length, reason: '一个服务都不许丢');
      expect(next.tileByKey('A')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('B')?.cells, const [(x: 2, y: 0)], reason: 'B 被往右挤了一格');
      expect(
        next.tileByKey('C')?.cells,
        const [(x: 0, y: 0)],
        reason: 'C 连锁出界 → 让位到空出来的第一格',
      );
      expect(next.tileByKey('D')?.cells, const [(x: 0, y: 1)], reason: '没撞到的 D 一格不动');
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

  group('编辑模式：分割线 / 断开接回（用户 2026-09-21 四轮）', () {
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

    testWidgets('普通模式不画分割线；进编辑模式才画，画面是实线', (tester) async {
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

      await repumpGrid(tester, saved, editMode: true, customEntries: three);

      expect(
        find.byKey(seamAB),
        findsOneWidget,
        reason: '用户口径 2：编辑模式下才显示分割线',
      );
      expect(seamPainter(tester).dashGap, 0, reason: '没断开的缝画实线');
      expect(saved, isEmpty, reason: '只是进出模式，布局不该变');
    });

    testWidgets('点分割线：这边断开、卡片当场分成两张，边界变虚线', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
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
      expect(saved, isEmpty, reason: '编辑模式里先不落盘，退出时才结算');
    });

    testWidgets('再点一次那条虚线：接回成一张卡', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
      );
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey(['A', 'B'])), findsNothing);

      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);
      expect(seamPainter(tester).dashGap, 0);
      await repumpGrid(tester, saved, editMode: false, customEntries: three);
      expect(saved, isEmpty, reason: '又接回去了 → 退出时没有任何要落盘的');
    });

    testWidgets('绕路还连着的缝：退出编辑模式自动接回去（布局不变）', (tester) async {
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
        editMode: true,
      );

      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cardKey(['A', 'B', 'C', 'D'])),
        findsOneWidget,
        reason: '2×2 从下面绕过去了 → 卡片没有分成两张',
      );
      expect(seamPainter(tester).dashGap, greaterThan(0), reason: '缝本身是断开的');

      await repumpGrid(tester, saved, editMode: false, customEntries: four);

      expect(saved, isEmpty, reason: '用户口径 2：还连着的缝要恢复连接，不落盘');
      expect(find.byKey(cardKey(['A', 'B', 'C', 'D'])), findsOneWidget);
    });

    testWidgets('真分成两块的缝：退出编辑模式落盘成两张卡，服务不丢', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
      );
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      await repumpGrid(tester, saved, editMode: false, customEntries: three);

      expect(saved, hasLength(1));
      expect(saved.single.isValid, isTrue);
      expect(saved.single.groupCount, 0);
      expect(saved.single.allTitles.length, 3, reason: '一个服务都不能丢');
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 0)]);
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('编辑模式里**按下即可拖**（不必长按）——老口径「模式内不响应拖动」已作废', (tester) async {
      // 用户 2026-09-21 九轮：「此模式下，拖动功能不需要长按，按下即可拖动」。
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
      );
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      // ⚠ 全程只 pump 16ms（**连一次 `kLongPressTimeout` 都没等**）：老口径下这时长按
      //   识别器还没到点，`homeGridLifted` 根本不会出现。
      final gesture = await tester.startGesture(aFace.center);
      await tester.pump(const Duration(milliseconds: 16));
      // 第一小步只走 8px：**小于祖先滚动视图的 18px 阈值**（`kTouchSlop`），却已经超过
      // 宫格自己的 4px（[kHomeGridEditTouchSlop] × 2 → `panSlop`）→ 必须是宫格先拿到
      // arena。手机上「按下即拖」想成立，靠的正是这条；不压阈值的话会被滚动视图抢走、
      // 变成滚页面（而不是拖卡片）。
      await gesture.moveTo(aFace.center + const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byKey(const Key('homeGridLifted')),
        findsOneWidget,
        reason: '走 8px 就该起手（老口径要等 500ms 长按）',
      );
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(aFace.center + Offset(0, 8 + 92 * i / 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 1)]);
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
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

  group('功能的抓取区不要太大（用户 2026-09-21 六轮口径）', () {
    // 用户原话：「我们希望每个卡片内，功能的点击区不要太大，不然就很难移动整个卡片」
    // → 每格只有**功能的内容块**（`homeGridFaceContentPadding`）长按才拖「这一个功能」，
    //   格子四周那一圈 + 格与格之间的缝都算「卡片其余部分」= 长按拖整张卡。
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

    /// 从**任意一点**长按起手拖到 [to]（[longPressDragFrom] 只能从 finder 的中心起手，
    /// 而「边界内侧 / 外侧」这类用例必须自己给点）。
    Future<TestGesture> dragFromPoint(
      WidgetTester tester,
      Offset from,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
      const steps = 6;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      return gesture;
    }

    /// 原地点一下长按（按住到超时后**不动**就松手）—— 用来守「没拖动 = 不改布局」。
    Future<void> longPressInPlace(WidgetTester tester, Offset point) async {
      final gesture = await tester.startGesture(point);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('抓取区 = 功能内容块；四周那一圈与格缝一起归整卡拖动', (tester) async {
      await pumpGrid(tester, customEntries: three, initial: twoInARow());
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      final aGrip = tester.getRect(find.byKey(const Key('homeGridGrip-A')));
      final bGrip = tester.getRect(find.byKey(const Key('homeGridGrip-B')));

      // 宽屏脸的内边距 = 16（`homeGridFaceContentPadding(compact: false)`）。
      expect(aGrip.left - aFace.left, 16);
      expect(aFace.right - aGrip.right, 16);
      expect(aGrip.top - aFace.top, 16);
      expect(aFace.bottom - aGrip.bottom, 16);
      expect(
        aGrip.width,
        lessThan(aFace.width),
        reason: '功能自己的抓取区必须比格子小，否则整卡没地方抓',
      );
      expect(aGrip.height, lessThan(aFace.height));
      // 相邻两个功能的抓取区之间空出 16 + 缝 12 + 16 = 44px 的整卡抓取走廊。
      expect(bGrip.left - aGrip.right, 16 * 2 + HomeGridMetrics.gap);
    });

    testWidgets('长按功能内容块（边界内侧）→ 只抬起这一格', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      final grip = tester.getRect(find.byKey(const Key('homeGridGrip-A')));
      final gesture = await dragFromPoint(
        tester,
        grip.topLeft + const Offset(3, 3),
        grip.topLeft + const Offset(3, 103),
      );
      final lifted = tester.getRect(find.byKey(const Key('homeGridLifted')));
      expect(
        lifted.width,
        closeTo(212 * 1.02, 0.5),
        reason: '内容块里长按 = 只拖这一个功能',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 1)]);
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('长按功能内容块之外的那一圈（边界外侧）→ 整张卡一起动', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      // 格子左边往内 6px（< 16 的圈宽）、纵向取中间那一行 → 落在圆角之内、抓取区之外。
      final ring = Offset(aFace.left + 6, aFace.center.dy);
      expect(
        find.byKey(const Key('homeGridGrip-A')).evaluate().isEmpty,
        isFalse,
        reason: '抓取区本身还在树里（只是不覆盖这个点）',
      );
      final gesture = await dragFromPoint(tester, ring, ring + const Offset(0, 100));
      final lifted = tester.getRect(find.byKey(const Key('homeGridLifted')));
      expect(
        lifted.width,
        closeTo((212 * 2 + HomeGridMetrics.gap) * 1.02, 0.5),
        reason: '空白圈里长按 = 拖整张卡（用户五轮口径）',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(saved.single.tileByKey('A\u001FB')?.cells, const [
        (x: 0, y: 1),
        (x: 1, y: 1),
      ]);
      expect(saved.single.tileByKey('C')?.cells, const [(x: 2, y: 0)]);
    });

    testWidgets('轻点那一圈照样打开功能（抓取区透明命中，轻点穿透到脸）', (tester) async {
      final tapped = <String>[];
      await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C'], onTap: tapped.add),
        initial: twoInARow(),
      );
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      // 抓取区之外、格子之内的四个方向各来一下（轻点区照旧是整格）。
      for (final point in [
        Offset(aFace.left + 6, aFace.center.dy),
        Offset(aFace.right - 6, aFace.center.dy),
        Offset(aFace.center.dx, aFace.top + 6),
        Offset(aFace.center.dx, aFace.bottom - 6),
        aFace.center,
      ]) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(tapped, ['A', 'A', 'A', 'A', 'A']);
    });

    testWidgets('窄屏紧凑磁贴同口径：抓取区按紧凑内边距收（8 / 14）', (tester) async {
      await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        viewSize: const Size(400, 900),
      );
      // 400 宽 → 紧凑形态、4 列、格宽 91、格高 94。
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      final aGrip = tester.getRect(find.byKey(const Key('homeGridGrip-A')));
      expect(aFace.width, closeTo(91, 0.01));
      expect(aFace.height, closeTo(94, 0.01));
      expect(aGrip.left - aFace.left, 8);
      expect(aFace.right - aGrip.right, 8);
      expect(aGrip.top - aFace.top, 14);
      expect(aFace.bottom - aGrip.bottom, 14);
    });

    testWidgets('长按不动就松手：什么都不落盘（不会把卡片拆成两张）', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
      );
      // ① 长按某一格的功能内容块（会先「抠出这一格」）——松手时落点就是原处 → 布局没变。
      await longPressInPlace(
        tester,
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      // ② 长按卡片其余部分（整卡拖动）也原地松手。
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      await longPressInPlace(
        tester,
        Offset(aFace.left + 6, aFace.center.dy),
      );

      expect(
        saved,
        isEmpty,
        reason: '原地长按松手 = 没拖动：既不该拆卡，也不该写库',
      );
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
    });
  });

  group('编辑模式里功能点不动 + 开关与重置都在设置页（用户 2026-09-21 七轮 / 十三轮）', () {
    // 用户原话：「我希望再添加一个一键重置功能；还有，处于分割状态下，功能不能被点击」
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

    testWidgets('编辑模式里功能点不动（脸上任意位置），退出后照旧可点', (tester) async {
      final tapped = <String>[];
      final withTap = someTitles(const ['A', 'B', 'C'], onTap: tapped.add);
      final saved = await pumpGrid(
        tester,
        customEntries: withTap,
        initial: twoInARow(),
        editMode: true,
      );
      final aFace = tester.getRect(find.byKey(const Key('homeTile-A')));
      // 功能内容块正中 + 格子四周的空白圈都点不动（模式开启时整张脸被 IgnorePointer 罩住）。
      // ⚠ 九轮起这两下不再是「什么都不做」：第一下**拿起**这一格，第二下**原地放下**
      //   （点的还是同一格 → 布局没变、也不落盘）。
      for (final point in [
        aFace.center,
        Offset(aFace.left + 6, aFace.center.dy),
      ]) {
        await tester.tapAt(point);
        await tester.pumpAndSettle();
      }
      expect(
        tapped,
        isEmpty,
        reason: '编辑模式里点一下只该是「拿起这一格 / 断开接回这条缝」——误点功能会跳走、把正在编辑的布局丢在半路',
      );
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
      expect(saved, isEmpty, reason: '拿起又原地放下 = 什么都没发生');

      // 缝照旧可点（这条路径没被误伤，顺带证明模式确实开着）。
      const seamKey = Key('homeGridSeam-0,0-1,0');
      expect(find.byKey(seamKey), findsOneWidget);
      await tester.tap(find.byKey(seamKey));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey(const ['A'])), findsOneWidget);

      // 退出编辑模式 → 功能恢复可点。
      await repumpGrid(tester, saved, editMode: false, customEntries: withTap);
      await tester.tapAt(
        tester.getRect(find.byKey(const Key('homeTile-A'))).center,
      );
      await tester.pumpAndSettle();
      expect(tapped, ['A']);
    });

    test('一键重置的存储口径：reset 清空 → 撤销把原布局写回', () async {
      final store = HomeGridStore(persist: false);
      await store.ensureLoaded();
      final before = twoInARow();
      await store.save(before);
      expect(store.layout, before);

      await store.reset(); // 设置页「恢复默认布局」做的事
      expect(store.layout, isNull);
      expect(store.hasCustomLayout, isFalse);

      await store.save(before); // 提示里的「撤销」做的事
      expect(store.layout, before);
      expect(store.hasCustomLayout, isTrue);
    });

    test('编辑模式开关与重置按钮都在设置页，顶栏不再有（源码守卫）', () {
      final screen = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      final settings = File(
        'lib/features/settings/presentation/widgets/settings_cards.dart',
      ).readAsStringSync();

      // 用户 2026-09-21 十三轮原话：「我希望标题栏不显示编辑模式按钮和重置按钮，
      // 这两个都放到设置里」—— 顶栏这两枚按钮（连同它们的提示）一律不许复活。
      expect(screen, isNot(contains('homeEditToggle')));
      expect(screen, isNot(contains('homeGridResetButton')));
      expect(screen, isNot(contains('homeGridResetSnack')));
      expect(screen, isNot(contains('_toggleEditMode')));
      expect(screen, isNot(contains('_resetGridLayout')));
      // 主页只负责「听」：宫格入参来自 provider。
      expect(screen, contains('ref.watch(homeEditModeProvider)'));
      expect(screen, contains('editMode: editMode'));

      // ① 编辑模式开关。
      expect(settings, contains("Key('homeEditModeSwitch')"));
      expect(settings, contains('ref.watch(homeEditModeProvider)'));
      expect(
        settings,
        contains('ref.read(homeEditModeProvider.notifier).state = next'),
      );
      expect(
        settings,
        contains("Key('homeGridEditHint')"),
        reason: '提示跟着开关搬到设置页（用户此时人在设置页）',
      );
      // 说明文案也跟着改（不能说「顶栏的剪刀按钮」了）。
      expect(settings, contains('下面打开「编辑模式」后回到主页'));
      expect(settings, isNot(contains('顶栏的剪刀按钮可以进入编辑模式')));

      // ② 恢复默认布局：先退出编辑模式，再 reset —— 那些「断开」是临时状态，
      //    退出时会结算落盘，留着会让「重置」看起来没生效。
      final from = settings.indexOf("Key('homeGridReset')");
      expect(from, greaterThan(0), reason: '设置页的恢复默认布局按钮找不到');
      final onPressed = settings.substring(
        from,
        settings.indexOf("label: const Text('恢复默认布局')", from),
      );
      expect(onPressed, contains('_setEditMode(context, ref, false)'));
      expect(onPressed, contains('gridStore.reset()'));
    });
  });

  group('编辑模式：点击拿起 → 再点放下（用户 2026-09-21 九轮）', () {
    // 用户原话：「我希望拆分模式更名为编辑模式，此模式下，拖动功能不需要长按，按下即可
    // 拖动，或者点击拿起，再次点击方下」。
    final three = someTitles(const ['A', 'B', 'C']);

    /// A、B 一行 + C 落在第二行 → 网格有两行高，**空格子 (0,1) 也在网格盒子之内**
    /// （点空白放下要靠 hit-test 命中网格自己的背景层，落到盒子外面就点不到了）。
    HomeGridLayout twoRows() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 1)),
      ],
    );

    Offset cellCenter(WidgetTester tester, int x, int y) {
      final grid = tester.getRect(find.byType(HomeServiceGrid));
      final metrics = HomeGridMetrics.of(grid.width);
      return grid.topLeft +
          Offset(
            x * metrics.pitchX + metrics.cellWidth / 2,
            y * metrics.pitchY + metrics.cellHeight / 2,
          );
    }

    /// 点一下「功能的内容块」正中 = 拿起这一个功能。
    Future<void> pickUpA(WidgetTester tester) async {
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('点一下拿起（卡片被抬起 + 虚线框），再点空格子放下', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoRows(),
        editMode: true,
      );

      await pickUpA(tester);
      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);
      expect(find.byKey(const Key('homeGridPreview')), findsOneWidget);
      expect(saved, isEmpty, reason: '只是拿起，什么都没动');

      // 空格子 (0,1)：这一下落到网格背景层（[Key] `homeGridEditBackground`）。
      await tester.tapAt(cellCenter(tester, 0, 1));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
      expect(saved, hasLength(1));
      expect(saved.single.allTitles.length, 3, reason: '一个服务都不能丢');
      expect(saved.single.tileByKey('A')?.cells, const [(x: 0, y: 1)]);
      expect(saved.single.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('点回原位 = 取消（不写库、卡片也不拆开）', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoRows(),
        editMode: true,
      );
      await pickUpA(tester);
      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);

      // 再点同一处 → 落点就是原处 → 语义指纹不变 → 一个字都不写。
      await pickUpA(tester);

      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
      expect(saved, isEmpty, reason: '拿起又原地放下，不该拆卡、也不该落盘');
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);
    });

    testWidgets('点在别的卡片正中：退化成纯移动，原主人让位（不丢服务）', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoRows(),
        editMode: true,
      );
      await pickUpA(tester);

      // C 那格正中：贴不到任何一条外露边（`kHomeGridEdgeBand` 之内才算边）→ 拖动版没有
      // 方案，但「点一下放下」必须有个结果 → `homeGridPlanTapDrop` 退化成纯移动。
      await tester.tapAt(cellCenter(tester, 2, 1));
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final next = saved.single;
      expect(next.allTitles.length, 3, reason: 'C 必须让位而不是被顶掉');
      expect(next.tileByKey('A')?.cells, const [(x: 2, y: 1)]);
      expect(next.tileByKey('C')?.cells, const [(x: 0, y: 0)]);
      expect(next.tileByKey('B')?.cells, const [(x: 1, y: 0)]);
    });

    testWidgets('手上有东西时点分割线 = 放下（不切换断开）', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: twoRows(),
        editMode: true,
      );
      const seamAB = Key('homeGridSeam-0,0-1,0');
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);

      await pickUpA(tester);
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cardKey(['A', 'B'])),
        findsOneWidget,
        reason: '拿着东西时点缝只是放下，不许顺手把卡片断开',
      );
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);

      // 没拿着东西时缝照旧可点。
      await tester.tap(find.byKey(seamAB));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey(['A', 'B'])), findsNothing);
      expect(find.byKey(const Key('homeGridCard-A')), findsOneWidget);
      expect(saved, isEmpty, reason: '编辑模式里断开是临时态，退出才结算');
    });

    testWidgets('普通模式下点击照旧打开功能（编辑模式的点击语义不外溢）', (tester) async {
      final tapped = <String>[];
      await pumpGrid(
        tester,
        customEntries: someTitles(const ['A', 'B', 'C'], onTap: tapped.add),
        initial: twoRows(),
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();
      expect(tapped, ['A']);
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
    });

    test('更名与手势接线（源码守卫）', () {
      final grid = File(
        'lib/features/home/presentation/home_service_grid.dart',
      ).readAsStringSync();
      final screen = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();

      // ① 老名字不许复活（`splitMode` / `homeSplitToggle` / `homeGridSplitHint`）。
      expect(grid, isNot(contains('splitMode')));
      expect(screen, isNot(contains('splitMode')));
      expect(screen, isNot(contains('homeSplitToggle')));
      expect(screen, isNot(contains('homeGridSplitHint')));

      // ② 新名字。开关与提示在**设置页**（用户 2026-09-21 十三轮：「我希望标题栏不显示
      //    编辑模式按钮和重置按钮，这两个都放到设置里」），主页只把值喂给宫格。
      expect(screen, isNot(contains('homeEditToggle')));
      expect(screen, isNot(contains('homeGridResetButton')));
      expect(screen, contains('ref.watch(homeEditModeProvider)'));
      expect(screen, contains('editMode: editMode'));

      final settings = File(
        'lib/features/settings/presentation/widgets/settings_cards.dart',
      ).readAsStringSync();
      expect(settings, contains("Key('homeEditModeSwitch')"));
      expect(settings, contains("Key('homeGridEditHint')"));
      expect(settings, contains("Key('homeGridReset')"));

      // ③ 手势：编辑模式 = pan（按下即拖）+ tap（拿起 / 放下）；抓取层两条分支都在。
      expect(grid, contains('kHomeGridEditTouchSlop'));
      expect(grid, contains('DeviceGestureSettings'));
      expect(grid, contains('onPanStart: (d) {'));
      expect(grid, contains('onTapUp: (d) => _tapGrab(tile, cell, d.globalPosition)'));
      expect(grid, contains('void _tapGrab('));
      expect(grid, contains('void _tapDrop('));
      expect(grid, contains('homeGridPlanTapDrop('));
      expect(grid, contains("Key('homeGridEditBackground')"));
      expect(grid, contains("Key('homeGridEditHover')"));
      // 老口径「编辑模式里不响应拖动」的早退必须已经删掉。
      expect(grid, isNot(contains('编辑模式只做')));
      expect(grid, isNot(contains('拆解模式只做')));
    });
  });

  group('功能脸的悬停提示：停留一会才显示 / 按着时不显示（用户 2026-09-21 十轮）', () {
    // 用户原话：「不要功能的悬停显示不要立刻显示，只有鼠标停留一会后才显示，但是如果是
    // 鼠标按下的状态，则不显示」。
    final three = someTitles(const ['A', 'B', 'C']);

    /// A、B 一行 + C 在第二行 → 网格两行高，**空格子 (2,0) 也在网格盒子之内**
    /// （「按着」那条用例要在空格子上按住：那里没有手势，按了不会变成拖动）。
    HomeGridLayout rowPlusOne() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 1)),
      ],
    );

    Offset cellCenter(WidgetTester tester, int x, int y) {
      final grid = tester.getRect(find.byType(HomeServiceGrid));
      final metrics = HomeGridMetrics.of(grid.width);
      return grid.topLeft +
          Offset(
            x * metrics.pitchX + metrics.cellWidth / 2,
            y * metrics.pitchY + metrics.cellHeight / 2,
          );
    }

    /// 副标题在页面上出现几次：脸自己那份**恒在**（1 次），悬停浮层建起来之后是 2 次。
    /// ⚠ 不能拿 `find.byTooltip` 判 —— `Tooltip` 一直在树里（十轮的修法只改
    ///   `waitDuration` 这个**属性**，树形不动），它跟「显不显示」无关。
    int tips(WidgetTester tester, String title) => tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => (t.data ?? t.textSpan?.toPlainText()) == '副标题 $title')
        .length;

    /// 鼠标真的悬停到某个功能上（`PointerEnterEvent` 才会来）。
    Future<TestGesture> hover(WidgetTester tester, String title) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(Key('homeTile-$title'))),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('悬停要停留一会才显示（不是一碰就弹）', (tester) async {
      await pumpGrid(tester);
      await hover(tester, 'A');
      expect(tips(tester, 'A'), 1, reason: '刚碰到不许弹');

      await tester.pump(const Duration(milliseconds: 300));
      expect(tips(tester, 'A'), 1, reason: '还没到 $kHomeGridTooltipWait');

      await tester.pump(kHomeGridTooltipWait);
      await tester.pump(const Duration(milliseconds: 200)); // 淡入
      expect(tips(tester, 'A'), 2, reason: '停留够了才显示副标题全文');
      expect(tips(tester, 'B'), 1, reason: '没悬停的功能照旧只有脸自己那一份');
    });

    testWidgets('指针按着的时候完全不显示；松开也要重新悬停才显示', (tester) async {
      await pumpGrid(tester, customEntries: three, initial: rowPlusOne());

      // 空格子 (2,0) 上按住（那里没有任何手势 → 不会变成拖动，纯「按下」状态）。
      final press = await tester.startGesture(cellCenter(tester, 2, 0));
      await tester.pump();
      final mouse = await hover(tester, 'A');
      await tester.pump(kHomeGridTooltipWait + const Duration(milliseconds: 200));
      expect(tips(tester, 'A'), 1, reason: '按着的时候一律不提示');

      await press.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tips(tester, 'A'),
        1,
        reason: '松开也不在原地补弹（悬停那一刻读到的就是不显示）',
      );

      // 真的移开再回来 → 提示照旧（这一条同时守住「不是把提示永久关掉」）。
      await mouse.moveTo(cellCenter(tester, 2, 0));
      await tester.pump();
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('homeTile-A'))),
      );
      await tester.pump(kHomeGridTooltipWait + const Duration(milliseconds: 200));
      expect(tips(tester, 'A'), 2, reason: '重新悬停 → 停留一会就显示');
    });

    testWidgets('正拖着东西时，鼠标滑到别的功能上也不显示', (tester) async {
      await pumpGrid(tester, customEntries: three, initial: rowPlusOne());

      // 普通模式：长按 A 起手拖（拖动中 `_dragKey != null`）。
      final drag = await longPressDragFrom(
        tester,
        find.byKey(const Key('homeTile-A')),
        cellCenter(tester, 2, 1) + const Offset(0, 40),
      );
      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);

      await hover(tester, 'B');
      await tester.pump(kHomeGridTooltipWait + const Duration(milliseconds: 200));
      expect(tips(tester, 'B'), 1, reason: '拖东西的时候不许弹提示（幽灵卡就在指针下面）');

      await drag.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6)); // 排空合并提示的计时器
    });

    test('悬停提示的接线（源码守卫）', () {
      final card = File(
        'lib/features/home/presentation/home_grid_card.dart',
      ).readAsStringSync();
      final grid = File(
        'lib/features/home/presentation/home_service_grid.dart',
      ).readAsStringSync();

      // ① 两档 `waitDuration` 都在，且脸按 `showTooltip` 选（默认 Duration.zero = 一碰就弹）。
      expect(card, contains('const Duration kHomeGridTooltipWait ='));
      expect(card, contains('const Duration kHomeGridTooltipSuppressed ='));
      expect(
        card,
        contains(
          'waitDuration:\n          showTooltip ? kHomeGridTooltipWait : kHomeGridTooltipSuppressed,',
        ),
      );
      expect(card, contains('triggerMode: TooltipTriggerMode.manual'));
      // ② 网格侧：按下状态 + 拖动状态一起门控，幽灵卡永远关提示。
      expect(grid, contains('bool _pointerDown = false;'));
      expect(grid, contains('onPointerDown: (_) => _setPointerDown(true)'));
      expect(grid, contains('showTooltip: !_pointerDown && _dragKey == null,'));
      expect(grid, contains('showTooltip: false,'));
      expect(grid, contains('Tooltip.dismissAllToolTips();'));
    });
  });

  group('拖某一格时原位留空（用户 2026-09-21 十轮 2）', () {
    // 用户原话：「我希望长按组合卡片的某一个功能时，此时原位置卡片的此功能不显示，
    // 而是只显示被我拖动的状态」。
    final three = someTitles(const ['A', 'B', 'C']);

    HomeGridLayout rowPlusOne() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 1)),
      ],
    );

    Offset cellCenter(WidgetTester tester, int x, int y) {
      final grid = tester.getRect(find.byType(HomeServiceGrid));
      final metrics = HomeGridMetrics.of(grid.width);
      return grid.topLeft +
          Offset(
            x * metrics.pitchX + metrics.cellWidth / 2,
            y * metrics.pitchY + metrics.cellHeight / 2,
          );
    }

    testWidgets('长按「组合卡片」里的某一个功能：原位不再显示它，只剩被拖走的那一张', (tester) async {
      final saved = await pumpGrid(
        tester,
        customEntries: three,
        initial: rowPlusOne(),
      );
      expect(find.byKey(const Key('homeTile-A')), findsOneWidget);
      expect(find.byKey(const Key('homeTile-B')), findsOneWidget);
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);

      final drag = await longPressDragFrom(
        tester,
        find.byKey(const Key('homeTile-A')),
        cellCenter(tester, 2, 0), // 空格子（(2,0) 没卡）→ 松手是纯移动
      );

      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);
      expect(
        find.byKey(const Key('homeTile-A')),
        findsOneWidget,
        reason: '源卡片那一格留空 → 页面上只剩被拖走的那一张 A',
      );
      expect(
        find.byKey(const Key('homeTile-B')),
        findsOneWidget,
        reason: '同一张卡里的另一个功能照旧',
      );
      expect(
        find.byKey(cardKey(['A', 'B'])),
        findsOneWidget,
        reason: '源卡片的形状 / key 一个字都不许变（变了拖动会断在半路）',
      );
      expect(saved, isEmpty, reason: '拖到一半还没松手，不许落盘');

      await drag.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('homeTile-A')),
        findsOneWidget,
        reason: '松手后回到常态',
      );
      expect(saved.single.tileByKey('A')?.cells, const [(x: 2, y: 0)]);
      expect(saved.single.allTitles.length, 3, reason: '一个服务都不能丢');
      await tester.pump(const Duration(seconds: 6)); // 排空合并提示的计时器
    });

    testWidgets('编辑模式点一下拿起：原位同样留空（不会出现两个 A）', (tester) async {
      await pumpGrid(
        tester,
        customEntries: three,
        initial: rowPlusOne(),
        editMode: true,
      );
      expect(find.byKey(const Key('homeTile-A')), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);
      expect(
        find.byKey(const Key('homeTile-A')),
        findsOneWidget,
        reason: '「点一下拿起」也是拖走 → 原位留空',
      );
      expect(find.byKey(const Key('homeTile-B')), findsOneWidget);

      // 原地再点一下 = 放下（取消）→ 空位补回来。
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('homeGridLifted')), findsNothing);
      expect(find.byKey(const Key('homeTile-A')), findsOneWidget);
    });

    test('空位只认「被抠出来的那一格」（源码守卫）', () {
      final card = File(
        'lib/features/home/presentation/home_grid_card.dart',
      ).readAsStringSync();
      final grid = File(
        'lib/features/home/presentation/home_service_grid.dart',
      ).readAsStringSync();

      expect(card, contains('final Set<GridCell> blankCells;'));
      expect(card, contains('Widget face = blankCells.contains(cell)'));
      // ⚠ 留空只能换 `faceWrapper` 收到的那个 `face`，两条手势带必须还在（否则拖动会断）。
      expect(card, contains('if (wrap != null) face = wrap(entry, cell, face);'));
      expect(
        grid,
        contains('final fromThis = _extractFrom == tile.key'),
      );
      expect(
        grid,
        contains(
          'final blankCells = fromThis '
          '? <GridCell>{extracted} : const <GridCell>{};',
        ),
      );
      expect(grid, contains('blankCells: blankCells,'));
    });
  });

  group('卡片形状也会变（用户 2026-09-21 十一轮）', () {
    // 用户原话：「不只是功能不显示，而是卡片形状也要改变，如果卡片仍在原位置，则显示为
    // 虚线，就像是其余部分将要添加当前拖动的一样，如果在其他位置，原卡片直接显示去除
    // 此功能的形状」。
    final three = someTitles(const ['A', 'B', 'C']);

    HomeGridLayout rowPlusOne() => HomeGridLayout(
      cols: 3,
      tiles: [
        HomeGridTile(
          titles: const ['A', 'B'],
          cells: const [(x: 0, y: 0), (x: 1, y: 0)],
        ),
        HomeGridTile.single('C', (x: 2, y: 1)),
      ],
    );

    Offset cellCenter(WidgetTester tester, int x, int y) {
      final grid = tester.getRect(find.byType(HomeServiceGrid));
      final metrics = HomeGridMetrics.of(grid.width);
      return grid.topLeft +
          Offset(
            x * metrics.pitchX + metrics.cellWidth / 2,
            y * metrics.pitchY + metrics.cellHeight / 2,
          );
    }

    HomeGridCard cardOf(WidgetTester tester, List<String> titles) =>
        tester.widget<HomeGridCard>(find.byKey(cardKey(titles)));

    /// 卡片轮廓画笔（一张卡只有一个 [HomeGridShapePainter]，用类型筛而不是 `.first`）。
    HomeGridShapePainter shapeOf(WidgetTester tester, List<String> titles) {
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(cardKey(titles)),
          matching: find.byType(CustomPaint),
        ),
      );
      return paints
          .map((w) => w.painter)
          .whereType<HomeGridShapePainter>()
          .single;
    }

    testWidgets('长按功能拖到别处：源卡片直接画「去掉这一格」的实心形状', (tester) async {
      await pumpGrid(tester, customEntries: three, initial: rowPlusOne());
      final metrics = HomeGridMetrics.of(
        tester.getRect(find.byType(HomeServiceGrid)).width,
      );

      final drag = await longPressDragFrom(
        tester,
        find.byKey(const Key('homeTile-A')),
        cellCenter(tester, 2, 0), // 空格子 → 松手是纯移动
      );

      final card = cardOf(tester, ['A', 'B']);
      expect(
        card.skinCells,
        const <GridCell>[(x: 1, y: 0)],
        reason: '形状去掉被拖走的那一格',
      );
      expect(card.dashedOutline, isFalse, reason: '已经挪到别处 = 实心形状');
      expect(card.blankCells, const <GridCell>[(x: 0, y: 0)]);
      expect(
        card.tile.cells.length,
        2,
        reason: 'tile 自己不许改：两条手势带还挂在上面（改了拖动会断在半路）',
      );
      // 轮廓真的少了一格：左边界落到第二列的左沿。
      final shape = shapeOf(tester, ['A', 'B']);
      expect(shape.path.getBounds().left, metrics.pitchX);
      expect(shape.dashed, isFalse);

      await drag.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6)); // 排空合并提示的计时器
    });

    testWidgets('点一下拿起、还没挪走：源卡片是「原来完整轮廓」的虚线', (tester) async {
      await pumpGrid(
        tester,
        customEntries: three,
        initial: rowPlusOne(),
        editMode: true,
      );

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();

      final card = cardOf(tester, ['A', 'B']);
      expect(card.dashedOutline, isTrue);
      expect(
        card.skinCells,
        isNull,
        reason: '虚线画的是原来完整的轮廓（放回来还是这个形状）',
      );
      expect(
        find.byKey(cardKey(['A', 'B'])),
        findsOneWidget,
        reason: 'key 不许变（变了手势识别器会随 Element 一起没）',
      );
      expect(shapeOf(tester, ['A', 'B']).path.getBounds().left, 0);
      expect(shapeOf(tester, ['A', 'B']).dashed, isTrue);
    });

    testWidgets('拿起后把指针挪走：源卡片换成去掉这一格的实心形状', (tester) async {
      await pumpGrid(
        tester,
        customEntries: three,
        initial: rowPlusOne(),
        editMode: true,
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('homeGridGrip-A'))),
      );
      await tester.pumpAndSettle();
      expect(cardOf(tester, ['A', 'B']).dashedOutline, isTrue);

      // 编辑模式下鼠标一移动就跟着走（`homeGridEditHover` 的 onHover → _updateDrag）。
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(cellCenter(tester, 2, 0));
      await tester.pumpAndSettle();

      final card = cardOf(tester, ['A', 'B']);
      expect(card.dashedOutline, isFalse, reason: '挪到别处 → 实心');
      expect(card.skinCells, const <GridCell>[(x: 1, y: 0)]);
    });

    test('形状 / 虚线两处口径（源码守卫）', () {
      final card = File(
        'lib/features/home/presentation/home_grid_card.dart',
      ).readAsStringSync();
      final grid = File(
        'lib/features/home/presentation/home_service_grid.dart',
      ).readAsStringSync();

      // 卡片：轮廓用的格子集合 + 虚线轮廓（虚线走与分割线同一个画笔口径）。
      expect(card, contains('final Set<GridCell>? skinCells;'));
      expect(card, contains('final bool dashedOutline;'));
      expect(
        card,
        contains('final skin = skinCells ?? gridCellSet(tile.cells);'),
      );
      expect(card, contains('dashed: dashedOutline,'));
      expect(card, contains('void paintDashedPath('));
      expect(card, contains('kHomeGridDashedBorderDash'));
      // 网格：在位判据 + 两条接线（形状 / 虚线）。
      expect(grid, contains('bool get _extractedAtHome'));
      expect(grid, contains('final atHome = fromThis && _extractedAtHome;'));
      expect(grid, contains('skinCells: skinCells,'));
      expect(grid, contains('dashedOutline: atHome || dashedPiece,'));
      expect(grid, contains('dashedPiece: pieceKeys.contains(tile.key),'));
    });
  });

  group('编辑模式点分割线立刻分开（用户 2026-09-21 十一轮）', () {
    // 用户原话：「我希望编辑模式，点击分割线后立刻分开，而不是只高亮分割线」。
    // 模型层面本来就是立刻分开的，但卡片纯白、页面底也是纯白 —— 12px 格缝肉眼看不出来，
    // 所以拆出来的每一块改画**主题红虚线轮廓**（缝上那条虚线同款），一眼就能看到「分开了」。
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

    HomeGridShapePainter shapeOf(WidgetTester tester, String title) {
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(Key('homeGridCard-$title')),
          matching: find.byType(CustomPaint),
        ),
      );
      return paints
          .map((w) => w.painter)
          .whereType<HomeGridShapePainter>()
          .single;
    }

    testWidgets('点一下缝：立刻分成两块，两块都换成红色虚线轮廓', (tester) async {
      await pumpGrid(
        tester,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
      );
      expect(find.byKey(cardKey(['A', 'B'])), findsOneWidget);
      expect(shapeOf(tester, 'A\u001FB').dashed, isFalse, reason: '没断开时是实心');

      await tester.tap(find.byKey(const Key('homeGridSeam-0,0-1,0')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cardKey(['A', 'B'])),
        findsNothing,
        reason: '点一下当场分开，不必等退出编辑模式',
      );
      for (final title in const ['A', 'B']) {
        final card = tester.widget<HomeGridCard>(
          find.byKey(Key('homeGridCard-$title')),
        );
        expect(card.tile.cells, hasLength(1));
        expect(
          card.dashedOutline,
          isTrue,
          reason: '拆出来的碎块画虚线（白卡白底时只有这圈虚线看得出来）',
        );
        expect(shapeOf(tester, title).dashed, isTrue);
      }
    });

    testWidgets('拆出来的两块画的是**虚线**轮廓（像素证据：虚线 vs 实线）', (tester) async {
      // ① 剪开之后：沿卡片上边缘扫一遍，必须有颜色、而且**一段段断开**。
      final shotKey = GlobalKey();
      await pumpGrid(
        tester,
        boundaryKey: shotKey,
        customEntries: three,
        initial: twoInARow(),
        editMode: true,
      );
      await tester.tap(find.byKey(const Key('homeGridSeam-0,0-1,0')));
      await tester.pumpAndSettle();

      final origin = tester.getTopLeft(find.byKey(shotKey));
      var (ink, runs) = _edgeInk(
        await _capture(tester, shotKey),
        tester.getRect(find.byKey(const Key('homeGridCard-A'))),
        origin,
      );
      expect(ink, greaterThan(20), reason: '虚线轮廓要有颜色（不是空的）');
      expect(runs, greaterThan(3), reason: '必须是一段段断开的虚线');

      // ② 没剪开时（普通模式同布局）：同一条边是**一整条实线** —— 对照组。
      final solidKey = GlobalKey();
      await pumpGrid(
        tester,
        boundaryKey: solidKey,
        customEntries: three,
        initial: twoInARow(),
      );
      final solidOrigin = tester.getTopLeft(find.byKey(solidKey));
      (ink, runs) = _edgeInk(
        await _capture(tester, solidKey),
        tester.getRect(find.byKey(cardKey(['A', 'B']))),
        solidOrigin,
      );
      expect(ink, greaterThan(20), reason: '实心卡片照样有淡描边');
      expect(runs, 1, reason: '实线 = 一整条（虚线的判据由此坐实）');
    });

    testWidgets('绕路还连着的缝：不拆卡，只把那条缝画成虚线', (tester) async {
      // 2×2 方块剪中间一条边，两边还能绕路相连 → 用户裁定「如果是这样，则显示虚线」。
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
      await pumpGrid(
        tester,
        customEntries: four,
        initial: square,
        editMode: true,
      );

      await tester.tap(find.byKey(const Key('homeGridSeam-0,0-1,0')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(cardKey(['A', 'B', 'C', 'D'])),
        findsOneWidget,
        reason: '绕路还连着 → 不拆卡',
      );
      final same = tester.widget<HomeGridCard>(
        find.byKey(cardKey(['A', 'B', 'C', 'D'])),
      );
      expect(
        same.dashedOutline,
        isFalse,
        reason: '卡片本身还是实心（只有那条缝变虚线）',
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('homeGridSeam-0,0-1,0')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(
        (paint.painter! as HomeGridDashedPainter).dashGap,
        greaterThan(0),
        reason: '「如果是这样，则显示虚线」',
      );
    });
  });

  // 用户 2026-09-21 十二轮原话（逐字）：「我希望添加碰撞移动的功能，就是像手机桌面一样，
  // 既要支持合并也要支持把卡片挤开」。
  group('碰撞移动：拖到别人身上就把卡片挤开（十二轮）', () {
    testWidgets('拖动时被压到的卡片当场滑开（预览位置 = 松手后的位置）', (tester) async {
      final saved = await pumpGrid(tester); // 3 列：A B C / D E
      final aRect = tester.getRect(find.byKey(const Key('homeTile-A')));
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final cRect = tester.getRect(find.byKey(const Key('homeTile-C')));

      final gesture = await longPressDragTo(tester, 'A', bRect.center);
      await tester.pumpAndSettle(); // 让滑行动画跑完

      // B 当场滑到 C 那一格；C 挤不动（右边出界）→ 让位到 A 腾出来的第一格。
      expect(
        tester.getRect(find.byKey(const Key('homeTile-B'))).topLeft,
        cRect.topLeft,
        reason: 'B 被挤到原来 C 的位置',
      );
      expect(
        tester.getRect(find.byKey(const Key('homeTile-C'))).topLeft,
        aRect.topLeft,
        reason: 'C 连锁让位到 A 原来的格子 —— 拖动中就能看见',
      );
      expect(find.byKey(const Key('homeGridLifted')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      final next = saved.single;
      expect(next.isValid, isTrue);
      expect(next.tileByKey('A')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('B')?.cells, const [(x: 2, y: 0)]);
      expect(next.tileByKey('C')?.cells, const [(x: 0, y: 0)]);
      expect(next.tileByKey('D')?.cells, const [(x: 0, y: 1)]);
      expect(find.byKey(cardKey(['B', 'A'])), findsNothing, reason: '压中间仍然不合并');
    });

    testWidgets('空位足够时只是「滑一格」，谁都不被扔到别处', (tester) async {
      // 5 列、只有 A B 两张卡：A 拖到 B 身上 → B 往右滑一格，其余一格都不动。
      final saved = await pumpGrid(
        tester,
        viewSize: const Size(1100, 1000),
        customEntries: someTitles(const ['A', 'B']),
        initial: HomeGridLayout(
          cols: 5,
          tiles: [
            HomeGridTile.single('A', (x: 0, y: 0)),
            HomeGridTile.single('B', (x: 1, y: 0)),
          ],
        ),
      );
      final aRect = tester.getRect(find.byKey(const Key('homeTile-A')));
      final bRect = tester.getRect(find.byKey(const Key('homeTile-B')));
      final pitch = bRect.left - aRect.left; // 一格 + 一道缝（1100 宽 → 5 列）
      final gesture = await longPressDragTo(tester, 'A', bRect.center);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(const Key('homeTile-B'))).left,
        closeTo(bRect.left + pitch, 0.5),
        reason: 'B 就往右滑一格',
      );

      await gesture.up();
      await tester.pumpAndSettle();
      final next = saved.single;
      expect(next.tileByKey('A')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('B')?.cells, const [(x: 2, y: 0)]);
    });

    test('被挤开的卡片先占住格子：谁让位不取决于卡片在列表里的顺序', () {
      // 乙（被挤开、目标位置 (2,0)）与 丙（原位就在 (2,0)）争同一格。
      // 列表按「行优先 + 标题」排，丙 排在 乙 前面；若不让被挤开的卡片先占位，
      // 丙 会先把格子占了、乙 反被扔到第一个空位（老实现实测就是这样）。
      final layout = HomeGridLayout(
        cols: 3,
        tiles: [
          HomeGridTile.single('甲', (x: 0, y: 0)),
          HomeGridTile.single('乙', (x: 1, y: 0)),
          HomeGridTile.single('丙', (x: 2, y: 0)),
        ],
      );
      final plan = homeGridPlanDrop(
        layout: layout,
        draggedKey: '甲',
        pointerCell: (x: 1, y: 0),
        grabCell: (x: 0, y: 0),
      )!;
      final next = plan.apply(layout);
      expect(next.tileByKey('甲')?.cells, const [(x: 1, y: 0)]);
      expect(next.tileByKey('乙')?.cells, const [(x: 2, y: 0)]);
      expect(next.tileByKey('丙')?.cells, const [(x: 0, y: 0)]);
    });

    test('挤开 / 滑动的接线（源码守卫）', () {
      final grid = File(
        'lib/features/home/presentation/home_service_grid.dart',
      ).readAsStringSync();
      expect(grid, contains('const Duration kHomeGridSlideDuration'));
      expect(grid, contains('AnimatedPositioned('));
      expect(grid, contains('duration: kHomeGridSlideDuration'));
      expect(grid, contains('plan.apply(_baseLayout(metrics)).tiles'));
      expect(grid, contains('pushedAt[tile.key] ?? tile'));
      final layout = File(
        'lib/features/home/domain/home_grid_layout.dart',
      ).readAsStringSync();
      expect(layout, contains('HomeGridDropTarget? _movePlan('));
      expect(layout, contains('final horizontal = dx != 0 && dx.abs() >= dy.abs();'));
      expect(layout, contains('Map<String, HomeGridTile> settled = const <String, HomeGridTile>{}'));
      expect(layout, contains('reflowed(anchored: landing, settled: pushed)'));
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

      // 编辑模式开关（用户 2026-09-21 十三轮：开关从顶栏搬到设置页）：
      // 拨一下 → provider 变 true + 给出一条「回到主页就生效」的提示。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsHomeLayoutCard)),
        listen: false,
      );
      expect(container.read(homeEditModeProvider), isFalse);
      await tester.ensureVisible(find.byKey(const Key('homeEditModeSwitch')));
      await tester.tap(find.byKey(const Key('homeEditModeSwitch')));
      await tester.pumpAndSettle();
      expect(container.read(homeEditModeProvider), isTrue);
      expect(find.byKey(const Key('homeGridEditHint')), findsOneWidget);
      expect(find.textContaining('编辑模式已打开'), findsOneWidget);

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
      expect(
        container.read(homeEditModeProvider),
        isFalse,
        reason: '重置顺带退出编辑模式（那些断开是临时状态）',
      );
      // 排空 SnackBar 的自动消失计时器，免得用例结束时还有 pending timer。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });
  });

}

/// 沿某张卡的**上边缘**扫一遍：返回（有墨的列数，连续段数）。
///
/// 虚线 → 段数很多（5 on / 4 off）；实线 → 恰好 1 段。判据 = 「这一格的不透明度明显高于
/// 卡面自己的不透明度」（见 [_Pixels.inkAt]）。
///
/// ⚠ 只能用 **alpha** 判，不能用亮度：`toByteData(rawRgba)` 是**预乘**的（alpha 196 的
/// 描边读回来是 RGB 88，而完全透明的格子读回来是 RGB 0 —— 越透明越黑），再加上虚线卡的
/// 卡面只是 6% 淡色（alpha 15）→ 按亮度判会把「断开的那一段」当成墨、把虚线读成实线。
(int, int) _edgeInk(_Pixels pixels, Rect card, Offset origin) {
  // 两端各让开 20px：12px 圆角处的描边会往下弯出这一两行，扫到那里会给实线多凑出
  // 一两个「段」（实测实线被读成 3 段）。
  final left = (card.left - origin.dx).round() + 20;
  final right = (card.right - origin.dx).round() - 20;
  final top = (card.top - origin.dy).round();
  // 卡面：不透明度 + 亮度。**两个判据都要**：
  // - 虚线卡（临时形状）的卡面只是 6% 淡色（alpha 15）→ 只能靠「比卡面更不透明」认描边；
  // - 实心卡的卡面是不透明白（alpha 255）→ alpha 判据废掉，只能靠「比白色深」认描边。
  final fillAlpha = pixels.alpha((left + right) ~/ 2, top + 6);
  final fillLum = pixels.luminance((left + right) ~/ 2, top + 6);
  var ink = 0;
  var runs = 0;
  var inRun = false;
  for (var x = left; x <= right; x++) {
    var found = false;
    for (var y = top; y <= top + 1; y++) {
      if (pixels.inkAt(x, y, fillAlpha, fillLum)) found = true;
    }
    if (found) {
      ink++;
      if (!inRun) runs++;
      inRun = true;
    } else {
      inRun = false;
    }
  }
  return (ink, runs);
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

  /// 这一格有没有「墨」= 描边 / 虚线的像素（两个判据取或，见 [_edgeInk] 的说明）。
  ///
  /// ⚠ 亮度那一支只在 alpha 已经饱和（≥200）时才算 —— `rawRgba` 是**预乘**的
  /// （越透明 RGB 越接近 0），不加这个门会把「断开的那一段」当成墨。
  bool inkAt(int x, int y, int fillAlpha, int fillLum) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final a = alpha(x, y);
    if (a > fillAlpha + 40) return true;
    return a >= 200 && luminance(x, y) < fillLum - 6;
  }
}
