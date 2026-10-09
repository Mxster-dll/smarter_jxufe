/// 「点顶部切换周数 → 横划动画」的守卫（用户 2026-10-08：「课表点击顶部切换周数时，
/// 也要显示切换动画」）。
///
/// 背景：标题栏的周次入口 = 「第 N 周」文字（`‹ ›` 早在 2026-09-16 就删了，见
/// `schedule_title_bar.dart`）——点它开周数选择弹窗，选中某一周即切周。这条路径
/// 从前是**直接跳**（`_goToWeek(smooth: false)` → 跨多周 `jumpToPage`），
/// 只有「长按回本周」才有横划动画（用户 2026-09-17）。本文件把「选周也要有动画」
/// 钉住，并守住第二轮报的「起点 / 终点是本周时动画错乱」。
///
/// 为什么起**真屏幕**（`ScheduleScreen` + 全套 provider 替身）而不是只 pump 视图：
/// 动画由屏幕的 `_smoothWeekRequest` 驱动（视图只管把序号透传给 `WeekPager`），
/// 只测视图等于测自己搭的线。这里走的是真链路：点周数 → 弹窗 → 选中 → 屏幕
/// `_goToWeek(smooth: true)` → `ScheduleGridView.pagerSmoothRequest` →
/// `SchedulePagedBoard` → `WeekPager.animateToPage`。
///
/// 判据刻意**不写死周号**（「本周」随真实日期变）：先读分页器当前位置，再挑一个
/// **跨 ≥ 3 周**的目标（跨多周正是旧行为会瞬移的那种情形），然后逐帧看位置。
///
/// ## ⚠ 第二轮：列集合必须与「正在看第几周」无关（用户 2026-10-08 二轮）
/// 「一旦切换周数时，起点或终点是本周，就会动画错乱」——真机偏好是
/// `showSaturday=false, showSunday=false`，而本周（第 5 周）的 10-10 是
/// 「补第 4 周周五的课」，于是**只有本周这一列有周六**。可见天若按「当前周」算，
/// 动画一离开本周那一帧列数就从 6 变 5、列宽重排 → 整屏在飞行中重排。
/// 现在口径 = **整学期**（`scheduleDaysWithClass(week: null)`，见 §9 / §39），
/// 下面两条用例逐帧断言「周六列一直在」。
library;

import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/schedule_repository.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/reschedule_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_screen.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_week_picker.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/week_pager.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_mapper.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_xml_parser.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/student_info_repository.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_effect_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 本学期最后教学周的兜底 = 课表自身最大 `endWeek`（这里给 16）。
const int _lastWeek = 16;

/// 真机保存的偏好：周六 / 周日都关（`app_data/scheduleprefs.hive` 实测值）。
const ScheduleDisplayPrefs _hideWeekend = ScheduleDisplayPrefs(
  showSaturday: false,
  showSunday: false,
);

ScheduleEntry _entry({
  required String code,
  required String name,
  required DayOfWeek day,
  int startWeek = 1,
  int endWeek = _lastWeek,
  int startPeriod = 1,
  int endPeriod = 2,
}) => ScheduleEntry(
  classCode: '$code-01',
  className: '$name(01)',
  courseCode: code,
  courseName: name,
  totalHours: 48,
  credits: 3,
  studyNature: '必修',
  teacherCode: 'T1',
  teacherName: '张三',
  selectionStatus: '已选',
  isCrossMajor: false,
  hasTextbook: true,
  classTimes: [
    ClassTime(
      startWeek: startWeek,
      endWeek: endWeek,
      weekParity: WeekParity.every,
      dayOfWeek: day,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      classroom: '麦三教101',
    ),
  ],
);

/// 周一到周五各一节课。
List<ScheduleEntry> _weekdayEntries() => [
  for (var day = 0; day < 5; day++)
    _entry(code: 'C$day', name: '测试课$day', day: DayOfWeek.values[day]),
];

/// 周一到周五 + **只有第 [week] 周**的周六一节课（真机 = 10-10 补第 4 周周五）。
List<ScheduleEntry> _entriesWithSaturday(int week) => [
  ..._weekdayEntries(),
  _entry(
    code: 'SAT',
    name: '补课',
    day: DayOfWeek.saturday,
    startWeek: week,
    endWeek: week,
    startPeriod: 3,
    endPeriod: 4,
  ),
];

/// 学籍替身：屏幕只用 `serialNo` / `enrollYear` 两项（`_serialNo` 为空会直接
/// 进错误态、连课表都不画）。走真解析器 + 真映射器造一个最小 `StudentInfo`，
/// 免得手抄 80 多个必填字段。
StudentInfo _studentInfo() => StudentInfoMapper().fromParsed(
  StudentInfoXmlParser().parse(
    '<xh>2202500001</xh><xm>同学甲</xm><rxnj>2025</rxnj>',
  ),
);

/// 课表仓库替身：只实现屏幕真正调用的 `getSchedule`。
class _FakeScheduleRepository implements ScheduleRepository {
  _FakeScheduleRepository(this.entries);

  final List<ScheduleEntry> entries;

  @override
  Future<List<ScheduleEntry>> getSchedule({
    required String year,
    required String semester,
    required String studentId,
  }) async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 学籍仓库替身：只给缓存读。
class _FakeStudentInfoRepository implements StudentInfoRepository {
  _FakeStudentInfoRepository(this.info);

  final StudentInfo info;

  @override
  Either<Failure, StudentInfo?> getCachedStudentInfo() => Right(info);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 调课仓库替身：读出来永远是空表（屏幕只调 `load`）。
class _FakeRescheduleRepository implements RescheduleRepository {
  @override
  Future<List<Reschedule>> load({
    required String year,
    required String semester,
  }) async => const <Reschedule>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  List<ScheduleEntry>? entries,
  ScheduleDisplayPrefs? prefs,
}) => ProviderScope(
  overrides: [
    studentInfoRepositoryProvider.overrideWith(
      (ref) async => _FakeStudentInfoRepository(_studentInfo()),
    ),
    scheduleRepositoryProvider.overrideWith(
      (ref) async => _FakeScheduleRepository(entries ?? _weekdayEntries()),
    ),
    rescheduleStoreProvider.overrideWith(
      (ref) => RescheduleStore(repository: _FakeRescheduleRepository()),
    ),
    currentPeriodTableProvider.overrideWith((ref) async => PeriodTable.builtin),
    cachedPeriodTableProvider.overrideWith((ref) async => PeriodTable.builtin),
    // 教务校历（只用于算「最后教学周」）给一份空表 → 退回课表自身周次范围。
    schoolCalendarProvider.overrideWith(
      (ref, term) async => SchoolCalendar(
        title: '',
        xn: term.xn,
        xq: term.xq,
        months: const [],
        notes: const [],
      ),
    ),
    // 校历效应走空索引：本用例只测动画，不碰小程序校历（也就不会去开 Hive）。
    calendarDayEffectIndexProvider.overrideWithValue(
      CalendarDayEffectIndex.empty(),
    ),
    if (prefs != null)
      scheduleDisplayPrefsStoreProvider.overrideWith(
        (ref) => ScheduleDisplayPrefsStore(initial: prefs),
      ),
  ],
  child: MaterialApp(theme: appLightTheme, home: const ScheduleScreen()),
);

/// 课表里那个分页器的当前页（小数 = 正在补间途中）。
double _pagerPage(WidgetTester tester) {
  final views = find.byType(PageView);
  expect(views, findsOneWidget, reason: '周视图应只有一个分页器');
  final controller = tester.widget<PageView>(views).controller!;
  final page = controller.page;
  expect(page, isNotNull, reason: '分页器已 attach');
  return page!;
}

/// 打开周数弹窗、选中 [week]，返回随后逐帧（50ms 一帧）的读数。
///
/// 每帧 = `(分页位置, 周六列可见数)`：前者判断「还在飞 / 已落定」，后者就是列集合。
Future<List<(double, int)>> _pickWeekAndSample(
  WidgetTester tester,
  int week, {
  int frames = 16,
}) async {
  await tester.tap(find.byKey(scheduleWeekButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(scheduleWeekCellKey(week)));
  await tester.pump(); // 弹窗开始退场
  final samples = <(double, int)>[];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    samples.add((
      _pagerPage(tester),
      find.text('周六').evaluate().length,
    ));
  }
  return samples;
}

/// 断言「**选中之后每一帧**（含飞行途中）周六列数都是 [expected]」。
///
/// 用户 2026-10-08 三轮定稿的口径 = 选周的列集合**跟目标周一起换**，换的那一下发生在
/// 补间**起手之前** —— 所以从选中后的第一帧起就该是目标周的口径，**中途不许再变**
/// （用户三轮原话：「从第 6 周切到第 5 周…此时就会导致周六列的突然出现」说的就是
/// 「落定后才换」留下的那一下）。用「逐帧恒定」同时挡住两种错法：
/// ① 跟着 `onPageChanged` 逐页变 → 中途出现另一档值；② 冻结到落定才换 → 前几帧是
/// 起始周的口径、落定后才变。
void _expectConstantAfterPick(List<(double, int)> samples, int expected) {
  expect(samples, isNotEmpty, reason: '采样不能为空');
  var moved = 0;
  for (final (page, saturday) in samples) {
    expect(
      saturday,
      expected,
      reason: '选中后列集合应恒为 $expected（目标周口径），实测 page=$page 时 $saturday',
    );
    moved++;
  }
  expect(moved, greaterThan(0));
}

void main() {
  setUpAll(() {
    // 偏好 / 调课那几处 Hive 取值一律「尽力而为」，给个临时目录免得报噪音。
    Hive.init(
      Directory.systemTemp.createTempSync('schedule_pick_week_anim').path,
    );
  });

  testWidgets('点顶部周数选周 → 分页器横划过去（不是瞬移）', (tester) async {
    // 手机竖屏：竖版周视图内部就是分页板（桌面宽屏下同样有，只是手势被关掉）。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final startIndex = _pagerPage(tester).round();
    // 跨 ≥ 3 周：旧行为（`smooth: false`）在跨多周时是 `jumpToPage`，
    // 而这正是本用例要区分的情形。
    final targetIndex = startIndex + 3 <= _lastWeek - 1
        ? startIndex + 3
        : startIndex - 3;
    final targetWeek = targetIndex + 1;
    expect(
      (targetIndex - startIndex).abs(),
      greaterThan(WeekPager.jumpThreshold),
      reason: '距离必须落在「旧行为会瞬移」的那一档，否则本用例区分不出接线',
    );

    // 点周数 → 弹窗 → 点目标周格子。
    await tester.tap(find.byKey(scheduleWeekButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('选择周数'), findsOneWidget, reason: '弹窗打开');

    await tester.tap(find.byKey(scheduleWeekCellKey(targetWeek)));
    await tester.pump(); // 弹窗开始退场
    await tester.pump(const Duration(milliseconds: 300)); // 退场结束 → 屏幕请求补间

    final justAfterPick = _pagerPage(tester);
    expect(
      (justAfterPick - targetIndex).abs() > 0.01,
      isTrue,
      reason: '弹窗关掉后应仍在途中 —— 瞬移（jumpToPage）在这一帧就已经到位',
    );

    await tester.pump(const Duration(milliseconds: 120));
    final mid = _pagerPage(tester);
    expect(mid, isNot(closeTo(justAfterPick, 0.001)), reason: '确实在移动');

    await tester.pumpAndSettle();
    expect(
      _pagerPage(tester),
      closeTo(targetIndex.toDouble(), 0.01),
      reason: '最终停在选中的第 $targetWeek 周',
    );
    expect(find.text('第 $targetWeek 周'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('选中的就是当前周 → 不动（`_goToWeek` 同值早退）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final index = _pagerPage(tester).round();
    await tester.tap(find.byKey(scheduleWeekButtonKey));
    await tester.pumpAndSettle();
    // 弹窗里「第 index+1 周」就是当前高亮那一周。
    await tester.tap(find.byKey(scheduleWeekCellKey(index + 1)));
    await tester.pumpAndSettle();

    expect(_pagerPage(tester), closeTo(index.toDouble(), 0.01));

    await tester.pumpWidget(const SizedBox());
  });

  // ─── 桌面（非 compact）几何：列集合变化**不许动到分页器视口** ─────────────────
  //
  // 用户 2026-10-08 四轮：「现在起点或终点为本周的bug又回来了」。根因不在列集合，
  // 而在**几何**：非 compact 时列宽被夹在 `[_minColWidth, _maxColWidth]` → 列数一变
  // 整表总宽就变（6 列 996 / 5 列 836），而分页器正裹在这块宽度里 → **视口宽度在补间
  // 飞行途中变了** → 正在飞的补间像素目标失效 → 落点错（实测：900→700 的视口变化会
  // 让「第 5 周 → 第 12 周」落在第 15 周）。
  // 手机 compact 下总宽恒等于可用宽度，所以只有桌面/宽窗口会犯。
  //
  // ⚠ 桌面平台必须显式指定：widget 测试默认 android，而 android 在 1920×1080 下会按
  // 「手机横屏」挑**横版**视图（那里天数是行、行高变化不影响横向分页视口，复现不出来）。
  group('桌面宽窗口（非 compact）', () {
    // ⚠ 测试环境 defaultTargetPlatform 恒为 android（foundation/platform.dart:25）
    // → 桌面端行为必须显式覆盖；且**必须在测试体内复位** —— `_verifyInvariants`
    // 在测试体跑完那一刻就断言它已归 null，tearDown 来不及（口径同 `ai_ui_test.dart`）。

    testWidgets('★ 切到没有周六的周：视口宽度不变 + 落点正好是目标周', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(prefs: _hideWeekend));
        await tester.pumpAndSettle();
        final cur = _pagerPage(tester).round() + 1;
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(
          _app(prefs: _hideWeekend, entries: _entriesWithSaturday(cur)),
        );
        await tester.pumpAndSettle();
        final widthBefore = tester.getSize(find.byType(PageView)).width;
        expect(find.text('周六'), findsOneWidget, reason: '本周周六有课 → 周六列在');

        final target = cur + 6;
        await _pickWeekAndSample(tester, target);
        final widthAfter = tester.getSize(find.byType(PageView)).width;
        expect(
          widthAfter,
          closeTo(widthBefore, 0.5),
          reason: '列数 6→5 不许改变分页器视口宽度（改了就必然落错周）',
        );

        await tester.pumpAndSettle();
        expect(
          _pagerPage(tester),
          closeTo((target - 1).toDouble(), 0.01),
          reason: '落点必须正好是选中的第 $target 周（视口变化会让它落到别处）',
        );
        expect(find.text('周六'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('★ 从没有周六的周切回本周：视口宽度不变 + 落点正好是本周', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(prefs: _hideWeekend));
        await tester.pumpAndSettle();
        final cur = _pagerPage(tester).round() + 1;
        await tester.pumpWidget(const SizedBox());

        await tester.pumpWidget(
          _app(prefs: _hideWeekend, entries: _entriesWithSaturday(cur)),
        );
        await tester.pumpAndSettle();

        await _pickWeekAndSample(tester, cur + 5, frames: 20);
        await tester.pumpAndSettle();
        final widthBefore = tester.getSize(find.byType(PageView)).width;

        await _pickWeekAndSample(tester, cur);
        final widthAfter = tester.getSize(find.byType(PageView)).width;
        expect(
          widthAfter,
          closeTo(widthBefore, 0.5),
          reason: '列数 5→6 不许改变分页器视口宽度',
        );

        await tester.pumpAndSettle();
        expect(
          _pagerPage(tester),
          closeTo((cur - 1).toDouble(), 0.01),
          reason: '落点必须正好是本周（第 $cur 周）',
        );
        expect(find.text('周六'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ─── 第二轮：起点 / 终点是本周时不许「错乱」（用户 2026-10-08）──────────────
  //
  // 真机复现条件三件套：① 偏好 `showSaturday=false, showSunday=false`；
  // ② 本周那一周的周六有课（真机 = 10-10「补第4周周五的课」）；③ 其它周周六没课。
  //
  // 口径（用户同日三轮定稿）= **选周的列集合跟目标周一起换**：
  // 换列发生在补间**起手之前**（画面还没动、弹窗正在退场），此后飞行途中与落定后
  // 都不再变 —— 「第 5 周的周六列随第 5 周一起滑进来」，不再在停稳后蹦出来。
  // 两条守卫因此逐帧断言「选中后列集合恒为目标周的口径」。

  testWidgets('★ 切到没有周六的周：选中后列集合立刻换成目标周（不再落定才变）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 先拿「本周」（模拟真机：只有当周周六有课）。⚠ 读完必须**卸载整棵树**，
    // 否则第二次 pumpWidget 会复用同一个 State（`_week` / `_entries` 都不重取）。
    await tester.pumpWidget(_app(prefs: _hideWeekend));
    await tester.pumpAndSettle();
    final cur = _pagerPage(tester).round() + 1;
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      _app(prefs: _hideWeekend, entries: _entriesWithSaturday(cur)),
    );
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsOneWidget, reason: '本周周六有课 → 周六列在');
    expect(find.text('周日'), findsNothing, reason: '整学期周日都没课 → 仍按设置收起');

    final target = cur + 6;
    final samples = await _pickWeekAndSample(tester, target);
    _expectConstantAfterPick(samples, 0); // 目标周（第 11 周）没有周六
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsNothing, reason: '第 $target 周周六没课 → 收起');
    expect(find.text('周日'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('★ 从没有周六的周切回本周：周六列随本周一起滑进来', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 同上：先读「本周」，再卸载重挂（否则复用旧 State、拿不到新课程表）。
    await tester.pumpWidget(_app(prefs: _hideWeekend));
    await tester.pumpAndSettle();
    final cur = _pagerPage(tester).round() + 1;
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      _app(prefs: _hideWeekend, entries: _entriesWithSaturday(cur)),
    );
    await tester.pumpAndSettle();

    // 先离开本周（选到周六没课的那一周），再选回本周（终点 = 本周）。
    await _pickWeekAndSample(tester, cur + 5, frames: 20);
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsNothing, reason: '第 ${cur + 5} 周周六没课 → 已收起');

    // 用户三轮原话：从第 6 周切到第 5 周，第 5 周显示周六 → 不许等落定才冒出来。
    final samples = await _pickWeekAndSample(tester, cur);
    _expectConstantAfterPick(samples, 1);
    await tester.pumpAndSettle();
    expect(_pagerPage(tester), closeTo((cur - 1).toDouble(), 0.01));
    expect(
      find.text('周六'),
      findsOneWidget,
      reason: '落定在本周（周六有补课）→ 周六列在（且全程都在）',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
