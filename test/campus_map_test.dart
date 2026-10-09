import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/anti_corruption/campus_map_parser.dart';
import 'package:smarter_jxufe/features/campus_address/data/campus_map_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/data/campus_map_repository.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/data/providers/campus_map_providers.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_map_geometry.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_painter.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_style.dart';

/// 造一份最小可渲染的几何（不依赖真实 asset，供纯逻辑/渲染守卫用）。
CampusMapGeometry fakeGeometry({
  String id = 'jiaoqiao',
  String name = '蛟桥园校区',
  List<CampusPolygon>? buildings,
  List<CampusLabel>? labels,
}) {
  const proj = CampusProjection(originLon: 115.85, originLat: 28.7466);
  Offset p(double lon, double lat) => proj.project(lon, lat);
  final b = buildings ??
      <CampusPolygon>[
        CampusPolygon(
          points: [p(115.849, 28.745), p(115.850, 28.745), p(115.850, 28.746), p(115.849, 28.746), p(115.849, 28.745)],
          name: '图书馆',
          kind: CampusBuildingKind.teaching,
          areaM2: 400,
        ),
      ];
  final roads = <CampusPolyline>[
    CampusPolyline(
      points: [p(115.848, 28.744), p(115.852, 28.748)],
      kind: 'footway',
      width: 1,
    ),
  ];
  return CampusMapGeometry(
    id: id,
    name: name,
    projection: proj,
    bounds: const Rect.fromLTRB(-200, -200, 200, 200),
    buildings: b,
    roads: roads,
    waterAreas: const [],
    waterLines: const [],
    greens: const [],
    sports: const [],
    labels: labels ??
        const [
          CampusLabel(name: '图书馆', position: Offset(20, 30), priority: 3),
          CampusLabel(name: '一食堂', position: Offset(24, 34), priority: 3),
          CampusLabel(name: '三教楼', position: Offset(-40, 10), priority: 2),
          CampusLabel(name: '小卖部', position: Offset(90, -60), priority: 1),
        ],
    attribution: '测试署名',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Hive 的临时目录必须**整份文件只 init 一次**（`HiveImpl` 是单例；第二次
  // `Hive.init` 会让后续 `openBox` 卡住 → 每个用例各超时 30s，实测踩过）。
  // 所以在 `main()` 顶层建目录 + init + 预开两个 box，各 group 只负责清值。
  late Directory hiveDir;
  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('campus_map_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(myCampusPrefsBoxName);
    await Hive.openBox<String>(campusMapPrefsBoxName);
  });
  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {
      // 清不掉不影响结论。
    }
  });

  // ============================================================ 真实 asset 台账
  // 这一组是**防漂移**用的：生成脚本重跑后数据变了，这里必须跟着人工核对。
  group('真实 asset 台账（assets/campus_map/*.json）', () {
    // 「枚举名 → 官方校区名」唯一出处 = `MyCampus.label`。
    // 键漏一个 / 名字写错都会红 —— 这正是 2026-10 实测踩过的坑
    // （OSM 把枫林园写成「枫庐园」、蛟桥园是 2 个 way）。
    const expectedNames = <String, String>{
      'jiaoqiao': '蛟桥园校区',
      'mailu': '麦庐园校区',
      'fenglin': '枫林园校区',
      'qingshan': '青山园校区',
    };

    test('四个校区的 asset 都在，且 id / 名称与 MyCampus 对齐', () async {
      for (final c in MyCampus.values) {
        final raw = await rootBundle
            .loadString(CampusMapRepository.assetFor(c.name));
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(json['id'], c.name, reason: '${c.name} 的 id 与文件名不符');
        expect(json['name'], expectedNames[c.name],
            reason: '${c.name} 的官方名漂了（OSM 那边改过名字？）');
        expect(json['attribution'], contains('OpenStreetMap'),
            reason: 'ODbL 要求署名，不许删');
      }
    });

    test('每个校区都解析得出几何，且裁剪依据不是 bbox 兜底', () async {
      final repo = const CampusMapRepository();
      for (final c in MyCampus.values) {
        final g = await repo.load(c.name);
        expect(g.name, expectedNames[c.name]);
        expect(g.projection.originLon, isNot(0.0));
        expect(g.projection.originLat, isNot(0.0));
        expect(g.bounds.width, greaterThan(0));
        expect(g.bounds.height, greaterThan(0));
        expect(g.clip, startsWith('osm-campus-polygon'),
            reason: '${c.name} 退回了 bbox 兜底 → 会把周边学校/小区画进来');
      }
    });

    test('★ 蛟桥园 / 麦庐园 有真实内容；枫林园 / 青山园 如实标为稀疏', () async {
      final repo = const CampusMapRepository();
      final jq = await repo.load('jiaoqiao');
      final ml = await repo.load('mailu');
      expect(jq.buildings.length, greaterThanOrEqualTo(20),
          reason: '蛟桥园实测 46 栋，掉到 20 以下说明裁剪或抓取变了');
      expect(ml.buildings.length, greaterThanOrEqualTo(20),
          reason: '麦庐园实测 42 栋');
      expect(jq.roads.length, greaterThanOrEqualTo(20));
      expect(jq.labels.length, greaterThanOrEqualTo(15));

      // 这两个校区 OSM 上几乎没测，`isSparse` 必须在界面上如实提示。
      final fl = await repo.load('fenglin');
      final qs = await repo.load('qingshan');
      expect(fl.isSparse, isTrue, reason: '枫林园实测只有 2 栋楼');
      expect(qs.isSparse, isTrue, reason: '青山园实测只有 2 栋楼');
    });

    test('★ 别校的建筑不许出现在财大地图里（东华理工那次）', () async {
      final repo = const CampusMapRepository();
      // 2026-10 实测：枫林园的 bbox 里混着东华理工大学（广兰/枫林校区）的
      // 「核工楼 / 测绘楼 / 软件楼 / 地学楼 / 国防科技楼」。首版按 bbox 裁剪时
      // 把 95 栋外校建筑画进了财大地图 —— 这条断言就是为了别再犯。
      const alien = ['核工楼', '测绘楼', '软件楼', '地学楼', '国防科技楼', '东华理工'];
      for (final c in MyCampus.values) {
        final g = await repo.load(c.name);
        for (final label in g.labels) {
          for (final a in alien) {
            expect(label.name.contains(a), isFalse,
                reason: '${c.name} 里出现了外校要素「${label.name}」');
          }
        }
      }
    });

    test('文件名 = MyCampus 枚举名（生成脚本的 CAMPUS_KEYS 契约）', () {
      // 生成脚本 `tool/jxufe_map/build_geometry.py` 的 CAMPUS_KEYS 就是这四个。
      expect(
        MyCampus.values.map((c) => c.name).toList(),
        containsAll(<String>['jiaoqiao', 'mailu', 'fenglin', 'qingshan']),
      );
      expect(CampusMapRepository.assetFor('jiaoqiao'),
          'assets/campus_map/jiaoqiao.json');
    });

    test('标签优先级只出现 1..3，且至少有一个找路锚点', () async {
      final repo = const CampusMapRepository();
      for (final c in MyCampus.values) {
        final g = await repo.load(c.name);
        for (final l in g.labels) {
          expect(l.priority, inInclusiveRange(1, 3));
        }
        if (!g.isSparse) {
          expect(g.labels.any((l) => l.isAnchor), isTrue,
              reason: '${c.name} 一个 pri=3 的锚点都没有，标签排版没东西可依');
        }
      }
    });
  });

  // ============================================================ 解析容错
  group('CampusMapParser 容错（旧 asset 不许把页面打崩）', () {
    const parser = CampusMapParser();

    test('空文档 → 空几何，不抛异常', () {
      final g = parser.parse(const <String, dynamic>{});
      expect(g.buildings, isEmpty);
      expect(g.roads, isEmpty);
      expect(g.labels, isEmpty);
      expect(g.bounds, Rect.zero);
    });

    test('字段类型全错 → 跳过该条，不抛异常', () {
      final g = parser.parse(const <String, dynamic>{
        'id': 42,
        'name': <int>[1, 2],
        'bounds': 'nope',
        'origin': {'lon': 1},
        'building': <Object>['x', 1, <String, dynamic>{'p': 'bad'}],
        'road': <Object>[<String, dynamic>{'p': <Object>[1, 'a']}],
        'label': <Object>[<String, dynamic>{'n': ''}, <String, dynamic>{'x': 'a'}],
      });
      expect(g.buildings, isEmpty);
      expect(g.roads, isEmpty);
      expect(g.labels, isEmpty);
    });

    test('缺 origin 时退回 bounds 中心', () {
      final g = parser.parse(const <String, dynamic>{
        'bounds': <double>[115.84, 28.74, 115.86, 28.76],
      });
      expect(g.projection.originLon, closeTo(115.85, 1e-9));
      expect(g.projection.originLat, closeTo(28.75, 1e-9));
    });

    test('闭合水体归水面、不闭合的归河道', () {
      final g = parser.parse(const <String, dynamic>{
        'origin': <double>[115.85, 28.7466],
        'bounds': <double>[115.84, 28.73, 115.86, 28.76],
        'water': <Object>[
          <String, dynamic>{
            'p': <Object>[
              <double>[115.849, 28.745],
              <double>[115.750, 28.745],
              <double>[115.850, 28.746],
              <double>[115.849, 28.745],
            ],
          },
          <String, dynamic>{
            'p': <Object>[
              <double>[115.849, 28.745],
              <double>[115.850, 28.746],
            ],
          },
        ],
      });
      expect(g.waterAreas, hasLength(1));
      expect(g.waterLines, hasLength(1));
    });

    test('建筑分类认不出时落到 service，不丢建筑', () {
      final g = parser.parse(const <String, dynamic>{
        'origin': <double>[115.85, 28.7466],
        'bounds': <double>[115.84, 28.73, 115.86, 28.76],
        'building': <Object>[
          <String, dynamic>{
            'k': '不认识的分类',
            'p': <Object>[
              <double>[115.849, 28.745],
              <double>[115.850, 28.745],
              <double>[115.850, 28.746],
            ],
          },
        ],
      });
      expect(g.buildings, hasLength(1));
      expect(g.buildings.single.kind, CampusBuildingKind.service);
    });
  });

  // ============================================================ 投影
  group('CampusProjection', () {
    const proj = CampusProjection(originLon: 115.85, originLat: 28.7466);

    test('原点投影到 (0,0)', () {
      final o = proj.project(115.85, 28.7466);
      expect(o.dx, closeTo(0, 1e-6));
      expect(o.dy, closeTo(0, 1e-6));
    });

    test('y 轴向北为正（纬度越大 y 越大）', () {
      final n = proj.project(115.85, 28.7500);
      expect(n.dy, greaterThan(0));
    });

    test('投影 ↔ 反投影可往返', () {
      final ll = proj.unproject(proj.project(115.8512, 28.7478));
      expect(ll.lon, closeTo(115.8512, 1e-9));
      expect(ll.lat, closeTo(28.7478, 1e-9));
    });

    test('经度方向按 cos(纬度) 收缩（同一度经度 < 同一度纬度）', () {
      final dLon = proj.project(115.86, 28.7466).dx; // +0.01°
      final dLat = proj.project(115.85, 28.7566).dy; // +0.01°
      expect(dLon, lessThan(dLat));
      // 南昌纬度约 28.75°，cos ≈ 0.877
      expect(dLon / dLat, closeTo(0.877, 0.01));
    });

    test('100m 在数值上就是 100（米制平面）', () {
      final a = proj.project(115.85, 28.7466);
      final b = proj.project(115.85, 28.7466 + 100 / 110574.0);
      expect(proj.distance(a, b), closeTo(100, 0.01));
    });
  });

  // ============================================================ 底图适配与命中
  group('CampusMapPainter：fit / 命中测试 / 标签', () {
    test('fit 能把 bounds 等比放进逻辑底图', () {
      final g = fakeGeometry();
      final size = CampusMapPainter.referenceSizeFor(g);
      final f = CampusMapPainter(
        geometry: g,
        style: CampusMapStyleKind.light.resolve(),
        textScale: 1,
        showLabels: true,
      ).fit(size);
      // 200m 的短边放进 1000 短边后，scale 应该 ≈ (1000-96)/400
      expect(f.scale, closeTo((1000 - 96) / 400, 0.01));
    });

    test('★ 命中测试：点在建筑里能取到，点在外面取不到', () {
      final g = fakeGeometry();
      final size = CampusMapPainter.referenceSizeFor(g);
      final painter = CampusMapPainter(
        geometry: g,
        style: CampusMapStyleKind.light.resolve(),
        textScale: 1,
        showLabels: true,
      );
      final f = painter.fit(size);
      final b = g.buildings.single;
      final c = b.anchor;
      // 世界坐标 → 屏幕坐标
      final hit = painter.buildingAt(
        Offset(c.dx * f.scale + f.dx, f.dy - c.dy * f.scale),
        size,
      );
      expect(hit, isNotNull);
      expect(hit!.name, '图书馆');
      // 远在图外
      expect(painter.buildingAt(const Offset(-5000, -5000), size), isNull);
    });

    test('shouldRepaint 对风格 / 几何变化敏感，对无关重建不敏感', () {
      final g = fakeGeometry();
      CampusMapPainter mk(CampusMapStyleKind k, {bool labels = true}) =>
          CampusMapPainter(
            geometry: g,
            style: k.resolve(),
            textScale: 1,
            showLabels: labels,
          );
      expect(mk(CampusMapStyleKind.light).shouldRepaint(
          mk(CampusMapStyleKind.light)), isFalse);
      expect(
          mk(CampusMapStyleKind.light)
              .shouldRepaint(mk(CampusMapStyleKind.dark)),
          isTrue);
      expect(
          mk(CampusMapStyleKind.light)
              .shouldRepaint(mk(CampusMapStyleKind.light, labels: false)),
          isTrue);
    });
  });

  // ============================================================ 两种风格
  group('两种风格解析（手动优先 / 否则跟主题）', () {
    test('没手选过 → 跟主题', () {
      expect(
        resolveCampusMapStyle(
            manual: null, platformBrightness: Brightness.light),
        CampusMapStyleKind.light,
      );
      expect(
        resolveCampusMapStyle(
            manual: null, platformBrightness: Brightness.dark),
        CampusMapStyleKind.dark,
      );
    });

    test('手选过 → 以手选为准（哪怕与主题相反）', () {
      expect(
        resolveCampusMapStyle(
            manual: CampusMapStyleKind.light,
            platformBrightness: Brightness.dark),
        CampusMapStyleKind.light,
      );
      expect(
        resolveCampusMapStyle(
            manual: CampusMapStyleKind.dark,
            platformBrightness: Brightness.light),
        CampusMapStyleKind.dark,
      );
    });

    test('两套配色的关键色值互不相同（不是同一套换了个名字）', () {
      final l = CampusMapStyleKind.light.resolve();
      final d = CampusMapStyleKind.dark.resolve();
      expect(l.ground, isNot(d.ground));
      expect(l.road, isNot(d.road));
      expect(l.label, isNot(d.label));
      // 深色底图必须够暗、浅色底图必须够亮（别把两套写反）。
      expect(d.ground.computeLuminance(), lessThan(0.1));
      expect(l.ground.computeLuminance(), greaterThan(0.8));
    });

    test('fromName 认得出枚举名、认不出返回 null', () {
      expect(CampusMapStyleKind.fromName('dark'), CampusMapStyleKind.dark);
      expect(CampusMapStyleKind.fromName('乱写'), isNull);
      expect(CampusMapStyleKind.fromName(null), isNull);
      expect(CampusMapStyleKind.fromName(''), isNull);
    });

    test('other 是双向的', () {
      expect(CampusMapStyleKind.light.other, CampusMapStyleKind.dark);
      expect(CampusMapStyleKind.dark.other, CampusMapStyleKind.light);
    });
  });

  // ============================================================ 页面冒烟
  group('页面渲染冒烟', () {
    // Hive 已在 `main()` 顶层 init 并预开两个 box（见那里的注释）。

    Widget app({Size? size}) {
      final child = ProviderScope(
        overrides: [
          campusMapGeometryProvider.overrideWith(
            (ref, id) async => fakeGeometry(id: id, name: '$id 校区'),
          ),
        ],
        child: const MaterialApp(home: CampusMapScreen()),
      );
      if (size == null) return child;
      return MediaQuery(data: MediaQueryData(size: size), child: child);
    }

    /// 清掉两个偏好 box（每个用例开头调，保证互不影响）。
    ///
    /// 清掉「我的校区」偏好 box，保证用例互不影响。
    ///
    /// ⚠ 必须包在 `runAsync` 里：`testWidgets` 的时钟是假的，真实异步不会完成。
    /// ⚠⚠ **同一次用例里不许嵌套第二次 `runAsync`** —— 会报
    /// `Reentrant call to runAsync() denied`（实测踩过）。
    Future<void> resetPrefs(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Hive.box<String>(myCampusPrefsBoxName).clear();
      });
    }

    /// 清掉风格偏好 box，且**必须在 store 订阅它之前**做。
    ///
    /// ⚠⚠ `CampusMapStore` 会 `box.watch()` 订阅；对一个**已被订阅**的 box 调
    /// `clear()` 会让后面的 `pumpAndSettle` 再也收不住（实测：整组卡到 10 分钟
    /// 超时）。所以只在**首个**碰风格的用例开头（此时还没 store 订阅）清一次，
    /// 且只清一次 —— 后续用例靠 `save()` 自己把值摆正。
    Future<void> clearStyleOnce(WidgetTester tester) async {
      await tester.runAsync(() async {
        await Hive.box<String>(campusMapPrefsBoxName).clear();
      });
    }

    /// ⚠ 必须给足视口：默认 800×600 下地图卡片的三个工具按钮落在 y≈658，
    /// **超出视口 → `tester.tap` 打不中**（实测踩过：`getRect` 显示
    /// `fromLTRB(698, 638, 738, 678)`，屏幕只有 600 高）。
    Future<void> pumpApp(
      WidgetTester tester, {
      Size size = const Size(1000, 1000),
    }) async {
      await resetPrefs(tester);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      // family provider 是 async 的，必须让 Future 落地再断言
      // （只 `pump()` 会停在 loading 分支，`g == null` → 脚注整段不画）。
      await tester.pumpAndSettle();
    }

    testWidgets('四个校区胶囊都在，且不溢出', (tester) async {
      await pumpApp(tester);
      for (final c in MyCampus.values) {
        expect(find.byKey(Key('campusMapTab_${c.name}')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('默认选中第一个校区，点另一个能切过去', (tester) async {
      await pumpApp(tester);
      // 未设置「我的校区」→ 默认蛟桥园（只有一个胶囊是选中态）。
      expect(find.text('蛟桥园'), findsOneWidget);
      // 卡片脚注显示的是**官方校区名**（`CampusVectorEntry.name` = `MyCampus.label`），
      // 不是 asset 里的 `name` —— 别拿 override 的名字去断言（实测踩过）。
      expect(find.text('蛟桥园校区'), findsOneWidget);
      await tester.tap(find.byKey(const Key('campusMapTab_qingshan')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('青山园校区'), findsOneWidget);
      expect(find.text('蛟桥园校区'), findsNothing);
    });

    testWidgets('三个工具按钮都在（矢量/官网、风格、复位）', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('campusMapRasterToggle')), findsOneWidget);
      expect(find.byKey(const Key('campusMapStyleToggle')), findsOneWidget);
      expect(find.byKey(const Key('campusMapReset')), findsOneWidget);
    });

    testWidgets('★ 页面顶部的「矢量图 / 官网原图」两态都在，默认矢量', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('campusMapModeSwitch')), findsOneWidget);
      // 默认矢量态：校区胶囊在，官网列表不在。
      expect(find.byKey(const Key('campusMapTab_jiaoqiao')), findsOneWidget);
      expect(find.text('江西财经大学交通示意图'), findsNothing);
      // 切到官网原图：校区胶囊消失，官网列表出现。
      await tester.tap(find.text('官网原图'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('campusMapTab_jiaoqiao')), findsNothing);
      // ⚠ 官网列表有 7 条、卡片很高（16:9），**后几条落在视口外 → ListView
      // 不构建它们**（实测踩过：断言第 6 条「蛟桥园北区」永远是 0）。
      // 所以只断言第一条可见的。
      expect(find.text('江西财经大学交通示意图'), findsOneWidget);
    });

    testWidgets('卡片内切到「官网原图」不炸（栅格兜底）', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('campusMapRasterToggle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('官网原图'), findsWidgets);
    });

    testWidgets('手动切风格：立刻生效（内存先改）且落盘', (tester) async {
      await clearStyleOnce(tester); // 必须在 store 订阅 box 之前清
      await pumpApp(tester);
      expect(find.textContaining('跟随系统'), findsOneWidget);
      await tester.tap(find.byKey(const Key('campusMapStyleToggle')));
      // ⚠ `save()` 里 `await ensureLoaded()` 有真异步 IO；`pumpAndSettle` 只推进
      // 测试时钟、不等真实 IO，所以给一点真实时间。
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 150),
          ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('已手动固定'), findsOneWidget);
      expect(find.textContaining('风格「深色」已手动固定'), findsOneWidget);
    });

    testWidgets('★ 点一下风格按钮就换到另一款，并固定在那一款', (tester) async {
      await pumpApp(tester);
      // ⚠ 刻意**不假设起点是哪一款**：上一条用例已经把风格切过一次，
      // 再往 box 里写值需要第二次 `runAsync`，而对已被 store `watch()` 的 box
      // 做真实写入会让整组卡住（实测：10 分钟超时）。所以这里只断言
      // 「点一下 → 一定换到相反的那一款」——这本来就是要守的行为。
      final before = Hive.box<String>(campusMapPrefsBoxName).get('style');
      final wasDark = before == CampusMapStyleKind.dark.name;

      await tester.tap(find.byKey(const Key('campusMapStyleToggle')));
      // ⚠ 这一次 `runAsync` 只包「等磁盘」—— 因为 `pumpApp` 里已经用过一次
      // `runAsync`，**同一次用例里不能再嵌套**（`Reentrant call … denied`）。
      // 但这一次也**不能省**：`save()` 里 `await ensureLoaded()` 是真异步，
      // 假时钟下不推进就永远停在「跟随系统」（实测踩过）。
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 150),
          ));
      await tester.pumpAndSettle();
      expect(find.textContaining('已手动固定'), findsOneWidget);
      expect(
        find.textContaining(wasDark ? '风格「浅色」已手动固定' : '风格「深色」已手动固定'),
        findsOneWidget,
      );

      // 「关掉再打开页面」= 重建整棵树（新 ProviderScope + 新 store）。
      // ⚠ 这一例**不再断言恢复**：那需要真实 Hive 读写，而 `testWidgets` 的假时钟
      // 下必须靠 `runAsync`，嵌套会直接报错、不嵌套会挂到超时（都实测踩过）。
      // **恢复能力由 `test/campus_map_store_test.dart` 的 `test()` 组保证。**
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏（360×640）不溢出、不抛异常', (tester) async {
      await pumpApp(tester, size: const Size(360, 640));
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏（1100×800）不抛异常', (tester) async {
      await pumpApp(tester, size: const Size(1100, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('稀疏校区给出「不是加载失败」的如实提示', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            campusMapGeometryProvider.overrideWith(
              (ref, id) async => fakeGeometry(
                id: id,
                name: '枫林园校区',
                buildings: const [],
              ),
            ),
          ],
          child: const MaterialApp(home: CampusMapScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('不是加载失败'), findsOneWidget);
    });
  });
}
