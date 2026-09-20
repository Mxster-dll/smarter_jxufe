/// 「找空闲教室」页面的 widget 测试（**全 provider 造假**，不碰网络与 Hive）。
///
/// 覆盖两件在真机上不好复现的事：
/// 1. 「我的校区」预填（store 异步加载 → 必须 `watch` + 拿到值才落闸）；
/// 2. 两个模式在页面上的接线（条件 → 结果卡、点某行跳到「按教室查空闲」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/classroom_free_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';

/// 假的「我的校区」store：直接把偏好当已加载（不走 Hive）。
class _FakeCampusStore extends MyCampusStore {
  _FakeCampusStore(this._value);

  final MyCampus? _value;

  @override
  MyCampus? get campus => _value;
}

/// 假的「公共查询偏好」store：直接给出默认教学楼（不走 Hive）。
class _FakePrefsStore extends PublicQueryPrefsStore {
  _FakePrefsStore(this._building);

  final PublicQueryBuilding? _building;

  @override
  PublicQueryBuilding? get defaultBuilding => _building;

  @override
  Future<void> ensureLoaded() async {}
}

const _terms = <PublicQueryTerm>[
  PublicQueryTerm(xn: 2026, xqM: 0, name: '2026-2027学年第一学期'),
  PublicQueryTerm(xn: 2025, xqM: 1, name: '2025-2026学年第二学期'),
];

const _campuses = <PublicQueryOption>[
  PublicQueryOption(code: '1', name: '蛟桥园校区'),
  PublicQueryOption(code: '3', name: '麦庐园校区'),
];

const _buildings = <PublicQueryOption>[
  PublicQueryOption(code: '32', name: '北区综合楼'),
  PublicQueryOption(code: '35', name: '白云楼'),
];

const _classrooms = <PublicQueryOption>[
  PublicQueryOption(code: '1000264', name: '麦一教1108[40][一般教室]'),
  PublicQueryOption(code: '1000265', name: '麦一教1109[60][公共实验室]'),
  PublicQueryOption(code: '1000266', name: '麦一教1110[30][公共实验室]'),
];

/// 一间有课的教室（周三 1-2 节，2-17 周）+ 一间整学期没课。
final _timetables = <PublicTimetable>[
  const PublicTimetable(
    fields: [
      (label: '校区', value: '麦庐园校区'),
      (label: '楼房', value: '一教楼'),
      (label: '教室类型', value: '一般教室'),
      (label: '教室', value: '麦一教1108(40)'),
    ],
    owner: '麦一教1108',
    cells: [
      PublicTimetableCell(
        weekday: 3,
        periodIndex: 1,
        startPeriod: 1,
        endPeriod: 2,
        text: '高等数学 4 张三 [2-17]周 1-2节',
        parts: ['高等数学', '4', '张三', '[2-17]周', '1-2节'],
        startWeek: 2,
        endWeek: 17,
        parity: WeekParity.every,
      ),
    ],
  ),
  const PublicTimetable(
    fields: [
      (label: '校区', value: '麦庐园校区'),
      (label: '楼房', value: '一教楼'),
      (label: '教室类型', value: '公共实验室'),
      (label: '教室', value: '麦一教1110(30)'),
    ],
    owner: '麦一教1110',
    cells: [],
  ),
];

/// 作息表固定成内置兜底表。
///
/// 节次自动选段要读它，而**真实仓库会去开 Hive / 联网** → widget 测试里必须 override，
/// 否则那条 Hive 错误会冒到 zone 上把测试判失败（与 `theme_dark_test` 同一类坑）。
const PeriodTable _periodTable = PeriodTable.builtin;

List<Override> _periodOverrides() => [
  currentPeriodTableProvider.overrideWith((ref) async => _periodTable),
  cachedPeriodTableProvider.overrideWith((ref) async => _periodTable),
];

Future<void> _pumpPage(
  WidgetTester tester, {
  MyCampus? myCampus = MyCampus.mailu,
  List<PublicQueryOption> classrooms = _classrooms,
  PublicQueryBuilding? defaultBuilding,
  DateTime? now,
}) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._periodOverrides(),
        myCampusStoreProvider.overrideWith((ref) => _FakeCampusStore(myCampus)),
        publicQueryPrefsStoreProvider.overrideWith(
          (ref) => _FakePrefsStore(defaultBuilding),
        ),
        publicQueryTermsProvider.overrideWith((ref) async => _terms),
        publicQueryCampusesProvider.overrideWith((ref) async => _campuses),
        publicQueryBuildingsProvider.overrideWith(
          (ref, campusCode) async => _buildings,
        ),
        publicQueryClassroomsProvider.overrideWith(
          (ref, key) async => classrooms,
        ),
        publicQueryReportProvider.overrideWith(
          (ref, request) async =>
              PublicQueryResult(html: '', timetables: _timetables),
        ),
      ],
      child: MaterialApp(
        home: ClassroomFreeScreen(now: now ?? DateTime(2026, 9, 16)),
      ),
    ),
  );
  // 首帧（provider 还在飞）→ 放几帧让 fake future 落地。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('「我的校区」预填：进页面就带上麦庐园校区，并出结果', (tester) async {
    await _pumpPage(tester);
    // 「查询范围」的校区下拉已经选中麦庐园（不再是「请选择校区」的占位）。
    expect(find.text('麦庐园校区'), findsOneWidget);
    expect(find.text('先选一个校区'), findsNothing);
    // 默认条件：第 N 周 + 周三 + 1-2 节。麦一教1108 周三 1-2 有课 → 只剩没课的教室。
    expect(find.byKey(const Key('classroomFreeSummary')), findsOneWidget);
    expect(find.byKey(const Key('classroomFreeRow-麦一教1110')), findsOneWidget);
    expect(find.byKey(const Key('classroomFreeRow-麦一教1108')), findsNothing);
  });

  testWidgets('没设「我的校区」→ 保持「请选择校区」并给提示', (tester) async {
    await _pumpPage(tester, myCampus: null);
    expect(find.text('请选择校区'), findsOneWidget);
    expect(find.text('先选一个校区'), findsOneWidget);
    expect(find.byKey(const Key('classroomFreeSummary')), findsNothing);
  });

  testWidgets('点结果行 → 切到「按教室查空闲」并带上这间教室', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byKey(const Key('classroomFreeRow-麦一教1110')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 模式 B 的选区出现，且教室名已填。
    expect(find.byKey(const Key('classroomFreePickRoom')), findsOneWidget);
    final label = tester
        .widget<Text>(find.byKey(const Key('classroomFreeRoomLabel')))
        .data;
    expect(label, contains('麦一教1110'));
    expect(find.byKey(const Key('classroomRoomHeader')), findsOneWidget);
  });

  testWidgets('按教室模式：弹层选教室 → 出整学期固定空闲', (tester) async {
    await _pumpPage(tester);
    // 手工切到模式 B（分段按钮第二段）。
    await tester.tap(find.text('按教室查空闲'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('classroomFreePickRoom')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('classroomFreeRoomOption-1000264')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeRoomLabel')))
          .data,
      contains('麦一教1108'),
    );
    // 麦一教1108 只占周三 1-2（2-17 周）→ 周三 1-2 不该进「每周都空」。
    expect(find.byKey(const Key('classroomRoomCommon')), findsOneWidget);
    expect(find.text('周三 1-2 节'), findsNothing);
    expect(find.text('周一 1-5 节'), findsOneWidget);
  });

  testWidgets('选楼房会连带清掉已选教室（避免跨楼旧值）', (tester) async {
    await _pumpPage(tester);
    await tester.tap(find.byKey(const Key('classroomFreeBuilding')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('白云楼').last);
    await tester.pumpAndSettle();
    expect(find.text('白云楼'), findsOneWidget);
    // 模式 A 的提示文案要说明「只列该楼有排课记录的教室」。
    expect(find.textContaining('只列**该楼有排课记录**的教室'), findsOneWidget);
  });

  testWidgets('报表里的教室名与教室清单对不上 → 给出可操作的提示（不发空码请求）', (tester) async {
    // 教室清单里没有「麦一教1110」（只有 1108/1109）→ 跳到模式 B 后查不到 code。
    await _pumpPage(tester, classrooms: _classrooms.sublist(0, 2));
    await tester.tap(find.byKey(const Key('classroomFreeRow-麦一教1110')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('这间教室在教室列表里找不到编号'), findsOneWidget);
    expect(find.byKey(const Key('classroomRoomHeader')), findsNothing);
  });

  testWidgets('整校区报表被服务端回「凭证已失效」页 → 给出「先选楼房」的可执行提示', (tester) async {
    // 实测：不选楼房 = 整校区 1.7 MB 报表，服务端有时直接回那张 alert 页
    // （登录没过期，同一会话查班级/课程课表都正常）→ 文案必须说清楚并给下一步。
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._periodOverrides(),
          myCampusStoreProvider.overrideWith((ref) => _FakeCampusStore(MyCampus.mailu)),
          publicQueryPrefsStoreProvider.overrideWith(
            (ref) => _FakePrefsStore(null),
          ),
          publicQueryTermsProvider.overrideWith((ref) async => _terms),
          publicQueryCampusesProvider.overrideWith((ref) async => _campuses),
          publicQueryBuildingsProvider.overrideWith((ref, c) async => _buildings),
          publicQueryClassroomsProvider.overrideWith((ref, k) async => _classrooms),
          publicQueryReportProvider.overrideWith(
            (ref, request) async =>
                throw StateError('凭证已失效，请重新登录！'),
          ),
        ],
        child: MaterialApp(
        home: ClassroomFreeScreen(now: DateTime(2026, 9, 16)),
      ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('classroomFreeError')), findsOneWidget);
    expect(find.textContaining('先在上面「楼房」里选一栋教学楼再查'), findsOneWidget);
    expect(find.byKey(const Key('classroomFreeRetry')), findsOneWidget);
  });

  FilterChip periodChip(WidgetTester tester, int period) =>
      tester.widget<FilterChip>(find.byKey(Key('classroomFreePeriod-$period')));

  /// 某一格星期胶囊的文字色。
  Color? weekdayLabelColor(WidgetTester tester, int day) => tester
      .widget<FilterChip>(find.byKey(Key('classroomFreeWeekday-$day')))
      .labelStyle
      ?.color;

  /// 某一格节次胶囊的文字色。
  Color? periodLabelColor(WidgetTester tester, int period) => tester
      .widget<FilterChip>(find.byKey(Key('classroomFreePeriod-$period')))
      .labelStyle
      ?.color;

  testWidgets('默认星期 = 今天（注入 2026-09-16 = 周三），节次按现在自动选段', (
    tester,
  ) async {
    await _pumpPage(tester);
    final wed = tester.widget<FilterChip>(
      find.byKey(const Key('classroomFreeWeekday-3')),
    );
    final mon = tester.widget<FilterChip>(
      find.byKey(const Key('classroomFreeWeekday-1')),
    );
    expect(wed.selected, isTrue, reason: '用户 2026-09-19：时间自动选到今天');
    expect(mon.selected, isFalse);
    // 注入的 now = 2026-09-16 00:00（还没到第一节课）→ 自动选第 1 段（1-5 节）。
    for (var p = 1; p <= 5; p++) {
      expect(periodChip(tester, p).selected, isTrue, reason: '第 $p 节');
    }
    expect(periodChip(tester, 6).selected, isFalse);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data,
      contains('1-5 节'),
    );
    expect(
      find.byKey(const Key('classroomFreePeriodAutoHint')),
      findsOneWidget,
      reason: '自动选段要有说明，用户才知道为什么是这几节',
    );
  });

  testWidgets('按现在时间自动选段：09:40 → 3-5 节（下节课起到午休前）', (tester) async {
    await _pumpPage(tester, now: DateTime(2026, 9, 16, 9, 40));
    expect(periodChip(tester, 1).selected, isFalse);
    expect(periodChip(tester, 2).selected, isFalse, reason: '第 2 节 09:35 已下课');
    for (var p = 3; p <= 5; p++) {
      expect(periodChip(tester, p).selected, isTrue, reason: '第 $p 节');
    }
    expect(periodChip(tester, 6).selected, isFalse, reason: '14:00 是新的一段');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data,
      contains('3-5 节'),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreePeriodAutoHint')))
          .data,
      allOf(
        contains('第 3 节 09:55 开始'),
        contains('下一段从第 6 节（14:00）开始'),
      ),
    );
  });

  testWidgets('手动勾过之后不再被自动覆盖，点「按现在时间」才回到自动', (tester) async {
    await _pumpPage(tester, now: DateTime(2026, 9, 16, 9, 40));
    await tester.tap(find.byKey(const Key('classroomFreePeriod-6')));
    await tester.pump();
    expect(periodChip(tester, 6).selected, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data,
      contains('3-6 节'),
      reason: '自动的 3-5 + 手勾的 6 连成一段',
    );
    expect(
      find.byKey(const Key('classroomFreePeriodAutoHint')),
      findsNothing,
      reason: '手选之后不再显示自动选段说明',
    );
    await tester.tap(find.byKey(const Key('classroomFreePeriodAuto')));
    await tester.pump();
    expect(periodChip(tester, 6).selected, isFalse);
    expect(periodChip(tester, 3).selected, isTrue);
    expect(find.byKey(const Key('classroomFreePeriodAutoHint')), findsOneWidget);
  });

  testWidgets('星期与节次都能多选：摘要按选中节次写全', (tester) async {
    await _pumpPage(tester);
    // 自动是 1-5；再勾第 6 节 → 连成 1-6。
    await tester.tap(find.byKey(const Key('classroomFreePeriod-6')));
    await tester.pump();
    expect(periodChip(tester, 6).selected, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data,
      contains('1-6 节'),
    );
    // 取消第 1 节 → 只剩 2-6。
    await tester.tap(find.byKey(const Key('classroomFreePeriod-1')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data,
      contains('2-6 节'),
    );
    // 星期也能多选：把周五也勾上（摘要里的星期列表要跟着变）。
    await tester.tap(find.byKey(const Key('classroomFreeWeekday-5')));
    await tester.pump();
    expect(periodChip(tester, 2).selected, isTrue);
  });

  testWidgets('节次一个都不选 → 给提示而不是算了空结果', (tester) async {
    await _pumpPage(tester);
    for (var p = 1; p <= 5; p++) {
      await tester.tap(find.byKey(Key('classroomFreePeriod-$p')));
      await tester.pump();
    }
    expect(find.text('至少选一个节次'), findsOneWidget);
    expect(find.byKey(const Key('classroomFreeSummary')), findsNothing);
  });

  testWidgets('节次胶囊的选中色 = 成绩页那套红实心件（不是页面强调色）', (tester) async {
    // 用户 2026-09-20：「单个按钮被选中，显示为 #C62828 底；连续选中的按钮之间要显示为
    // 用 #C62828 连接」—— 即成绩页那套红实心件（AppColors.errorFill / onErrorFill）。
    await _pumpPage(tester); // 00:00 → 自动选中 1-5
    final ctx = tester.element(find.byKey(const Key('classroomFreePeriod-3')));
    final red = AppColors.errorFill(ctx);
    final onRed = AppColors.onErrorFill(ctx);
    final accent = fp(ctx).publicQuery;

    // 连成一段：整段共用一块**不透明红底**（不是强调色的淡化档）。
    final run = tester.widget<Container>(
      find.byKey(const Key('classroomFreePeriodRun-1-5')),
    );
    final runFill = (run.decoration! as BoxDecoration).color!;
    expect(runFill, red);
    expect(runFill.a, 1.0, reason: '实心，不是半透明淡底');
    expect(runFill, isNot(accent), reason: '不再是页面强调色（紫）');
    expect(periodLabelColor(tester, 3), onRed, reason: '红底上用 onErrorFill 白字');
    // ⚠ **胶囊自己也必须画这块红**：只靠外层容器时，`FilterChip` 会用
    // `colorScheme.surface`（深色 #121212）把容器整片盖住，真机上只剩「每格左边 11px
    // 的红边」（窗口像素实测最长连续红段仅 24px），用户看到的还是黑按钮。
    expect(periodChip(tester, 3).selectedColor, red);
    expect(periodChip(tester, 3).backgroundColor, red);
    expect(
      periodChip(tester, 6).backgroundColor,
      Colors.transparent,
      reason: '未选中的格子不涂底色（与选中态宽度一致）',
    );

    // 只留一格选中 → 同样是这块红（单格走 classroomFreePeriodFill-<p>）。
    for (final p in const [1, 2, 3, 4]) {
      await tester.tap(find.byKey(Key('classroomFreePeriod-$p')));
      await tester.pump();
    }
    expect(find.byKey(const Key('classroomFreePeriodRun-1-5')), findsNothing);
    final single = tester.widget<Container>(
      find.byKey(const Key('classroomFreePeriodFill-5')),
    );
    expect((single.decoration! as BoxDecoration).color, red);
    expect(periodLabelColor(tester, 5), onRed);
    // 未选中的格子仍是描边、文字走灰。
    expect(periodLabelColor(tester, 6), isNot(onRed));
  });
  testWidgets('星期胶囊选中后也是同一块红实心件（原来只有紫字，深色下像没选中）', (
    tester,
  ) async {
    // 用户 2026-09-20 四轮：「我希望按钮选中后也要显示 c62828，而不是黑色」。
    await _pumpPage(tester); // 注入 2026-09-16（周三）→ 默认只选周三
    final ctx = tester.element(find.byKey(const Key('classroomFreeWeekday-3')));
    final red = AppColors.errorFill(ctx);
    final onRed = AppColors.onErrorFill(ctx);

    final wed = tester.widget<Container>(
      find.byKey(const Key('classroomFreeWeekdayFill-3')),
    );
    final fill = (wed.decoration! as BoxDecoration).color!;
    expect(fill, red);
    expect(fill.a, 1.0, reason: '实心，不是半透明淡底');
    expect(weekdayLabelColor(tester, 3), onRed, reason: '红底白字');

    // 未选中的星期：没有底色容器，文字也不是白的。
    expect(find.byKey(const Key('classroomFreeWeekdayFill-1')), findsNothing);
    expect(weekdayLabelColor(tester, 1), isNot(onRed));
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('classroomFreeWeekday-7')))
          .selectedColor,
      red,
      reason: '星期胶囊同样要自己画出红底（否则被 surface 盖住）',
    );

    // 点周一 → 它也变红；再点周三 → 红底消失。
    await tester.tap(find.byKey(const Key('classroomFreeWeekday-1')));
    await tester.pump();
    expect(
      find.byKey(const Key('classroomFreeWeekdayFill-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('classroomFreeWeekday-3')));
    await tester.pump();
    expect(find.byKey(const Key('classroomFreeWeekdayFill-3')), findsNothing);
  });

  testWidgets('选中的格子不显示对勾，且格子尺寸与选中态无关', (tester) async {
    await _pumpPage(tester);
    // 自动选中的是 1-5 节。
    expect(
      periodChip(tester, 3).showCheckmark,
      isFalse,
      reason: '用户 2026-09-19 三轮：对勾会额外占宽，格子宽度会跳变',
    );
    expect(periodChip(tester, 8).showCheckmark, isFalse);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('classroomFreeWeekday-3')))
          .showCheckmark,
      isFalse,
      reason: '星期格同一个问题（同一张卡、同一种交互）',
    );
    // 尺寸不变式：点一下（选中 → 未选中）前后，格子自身尺寸必须一模一样。
    final before = tester.getSize(find.byKey(const Key('classroomFreePeriod-3')));
    await tester.tap(find.byKey(const Key('classroomFreePeriod-3')));
    await tester.pump();
    expect(tester.getSize(find.byKey(const Key('classroomFreePeriod-3'))), before);
  });

  testWidgets('连续选中的节次合并成一张卡片，但每一格仍可独立点击', (tester) async {
    await _pumpPage(tester); // 00:00 → 自动 1-5 节
    final run = find.byKey(const Key('classroomFreePeriodRun-1-5'));
    expect(run, findsOneWidget, reason: '1-5 连续选中 → 视觉上一张卡片');
    expect(
      find.descendant(of: run, matching: find.byType(FilterChip)),
      findsNWidgets(5),
    );
    // 「一张卡片」的几何判据：合并容器的底要**连续覆盖** 1..5 全部格子（含格子之间
    // 的间隙）—— 格子自己是透明的，所以容器一跨到底 = 视觉上一整块。
    final runRect = tester.getRect(run);
    final firstRect = tester.getRect(
      find.byKey(const Key('classroomFreePeriod-1')),
    );
    final lastRect = tester.getRect(
      find.byKey(const Key('classroomFreePeriod-5')),
    );
    expect(runRect.left, closeTo(firstRect.left, 1));
    expect(runRect.right, closeTo(lastRect.right, 1));
    expect(runRect.height, closeTo(firstRect.height, 1));
    // 未选中的格子各自独立，不许出现「单格合并容器」。
    expect(find.byKey(const Key('classroomFreePeriodRun-6-6')), findsNothing);
    // 独立点击：点中间那一格只改它自己 → 合并段裂成两段。
    await tester.tap(find.byKey(const Key('classroomFreePeriod-3')));
    await tester.pump();
    expect(periodChip(tester, 3).selected, isFalse);
    expect(periodChip(tester, 2).selected, isTrue);
    expect(periodChip(tester, 4).selected, isTrue);
    expect(find.byKey(const Key('classroomFreePeriodRun-1-5')), findsNothing);
    expect(find.byKey(const Key('classroomFreePeriodRun-1-2')), findsOneWidget);
    expect(find.byKey(const Key('classroomFreePeriodRun-4-5')), findsOneWidget);
  });

  testWidgets('合并前后总宽不变：后面的格子不会因为合并而挪位', (tester) async {
    await _pumpPage(tester, now: DateTime(2026, 9, 16, 9, 40)); // 自动 3-5
    // 先取消第 5 节 → 3、4 各自独立；记下第 6 节的位置。
    await tester.tap(find.byKey(const Key('classroomFreePeriod-5')));
    await tester.pump();
    final loose = tester.getTopLeft(find.byKey(const Key('classroomFreePeriod-6')));
    // 再勾回第 5 节 → 3-5 合并成一张卡片。
    await tester.tap(find.byKey(const Key('classroomFreePeriod-5')));
    await tester.pump();
    expect(find.byKey(const Key('classroomFreePeriodRun-3-5')), findsOneWidget);
    final merged = tester.getTopLeft(find.byKey(const Key('classroomFreePeriod-6')));
    expect(
      merged.dx,
      closeTo(loose.dx, 0.01),
      reason: '合并段内部间隔 = Wrap.spacing，合并前后总宽一致',
    );
    expect(merged.dy, loose.dy, reason: '也不许因此换行');
  });
  testWidgets('相连的节次之间不画分格线、选中格不带描边', (tester) async {
    // 用户 2026-09-20 六轮：「相连的节数按钮之间不要显示分割线」+「被选中的节数按钮
    // 不要显示边框」。
    await _pumpPage(tester); // 00:00 → 自动选中 1-5
    final run = find.byKey(const Key('classroomFreePeriodRun-1-5'));

    // 段内只剩等宽**透明占位**（宽 = Wrap.spacing），没有任何画出来的分格件。
    expect(
      find.descendant(
        of: run,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == kClassroomChipGap && w.child == null,
        ),
      ),
      findsNWidgets(4),
      reason: '5 格之间 4 个占位；几何不变式靠它维持，但画面上看不见',
    );
    expect(
      find.descendant(
        of: run,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 1 &&
              w.constraints?.maxHeight == 16,
        ),
      ),
      findsNothing,
      reason: '旧版那条 1px×16 的分格线必须消失',
    );

    // 合并段 = 一整块：段内格子方角、只有段首/段尾保留 8 圆角（用户 2026-09-20 七轮：
    // 「看起来还是不连续，感觉是按钮边框的问题」—— 圆角是最后一处「按钮感」）。
    BorderRadius radiusOf(int period) =>
        (periodChip(tester, period).shape as RoundedRectangleBorder)
            .borderRadius as BorderRadius;
    expect(radiusOf(1), const BorderRadius.horizontal(left: Radius.circular(8)));
    expect(radiusOf(5), const BorderRadius.horizontal(right: Radius.circular(8)));
    for (final p in const [2, 3, 4]) {
      expect(radiusOf(p), BorderRadius.zero, reason: '第 $p 节在段内必须是方角');
    }
    // 段外 / 未选中的格子仍是圆角胶囊（它们本来就是独立按钮）。
    expect(radiusOf(6), BorderRadius.circular(8));
    expect(
      (tester
                  .widget<FilterChip>(
                    find.byKey(const Key('classroomFreeWeekday-3')),
                  )
                  .shape
              as RoundedRectangleBorder)
          .borderRadius,
      BorderRadius.circular(8),
      reason: '星期格不是合并段，保持圆角',
    );

    // 选中 = 红实心件 + 透明描边；未选中仍保留细描边胶囊。
    for (final p in const [1, 2, 3, 4, 5]) {
      expect(
        periodChip(tester, p).side?.color,
        Colors.transparent,
        reason: '第 $p 节已选中：不许再套一圈边框',
      );
    }
    expect(
      periodChip(tester, 6).side?.color,
      isNot(Colors.transparent),
      reason: '未选中的格子仍是描边胶囊（否则看不出还能点）',
    );
    // 星期格同一口径（注入 2026-09-16 = 周三 → 3 号选中）。
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('classroomFreeWeekday-3')))
          .side
          ?.color,
      Colors.transparent,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('classroomFreeWeekday-1')))
          .side
          ?.color,
      isNot(Colors.transparent),
    );
  });

  testWidgets('设置页的「默认教学楼」预填（当前校区里有这栋楼才选）', (tester) async {
    await _pumpPage(
      tester,
      defaultBuilding: const PublicQueryBuilding(
        campusCode: '3',
        campusName: '麦庐园校区',
        buildingCode: '35',
        buildingName: '白云楼',
      ),
    );
    expect(find.text('白云楼'), findsOneWidget);
    expect(find.text('不限（整个校区）'), findsNothing);
  });

  testWidgets('默认教学楼不在当前校区 → 不预选（楼房码按校区编）', (tester) async {
    await _pumpPage(
      tester,
      defaultBuilding: const PublicQueryBuilding(
        campusCode: '1',
        campusName: '蛟桥园校区',
        buildingCode: '99',
        buildingName: '不存在的楼',
      ),
    );
    expect(find.text('不存在的楼'), findsNothing);
    expect(find.text('不限（整个校区）'), findsOneWidget);
  });
}
