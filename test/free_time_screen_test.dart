/// 「找无课时间」页（2026-09-19 从公共查询页独立出来）的守卫测试。
///
/// **全 provider 造假**：不碰网络、不碰 Hive（`publicQueryReportProvider` /
/// `publicQueryComboBoxProvider` 都用 `overrideWith` 给固定 Future）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_profile_provider.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/free_time_screen.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/free_time_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';

const _terms = <PublicQueryTerm>[
  PublicQueryTerm(xn: 2026, xqM: 0, name: '2026-2027学年第一学期'),
];

const _campuses = <PublicQueryOption>[
  PublicQueryOption(code: '1', name: '蛟桥园校区'),
  PublicQueryOption(code: '3', name: '麦庐园校区'),
];

const _colleges = <PublicQueryOption>[
  PublicQueryOption(code: '14', name: '信息管理学院'),
];

const _majors = <PublicQueryOption>[
  PublicQueryOption(code: '4405', name: '计算机科学与技术'),
];

const _levels = <PublicQueryOption>[
  PublicQueryOption(code: '05', name: '本科'),
];

const _classes = <PublicQueryOption>[
  PublicQueryOption(code: 'c1', name: '[2508090D52]计算机科学与技术252'),
  PublicQueryOption(code: 'c2', name: '[2508090D53]计算机科学与技术253'),
  PublicQueryOption(code: 'c3', name: '[2508090D54]计算机科学与技术254'),
];

/// 班级 c1 周三 1-2 有课；c2 周四 3-5 有课（第 2-17 周）。
final _timetables = <PublicTimetable>[
  const PublicTimetable(
    fields: [
      (label: '班级', value: '计算机科学与技术252'),
      (label: '校区', value: '麦庐园校区'),
    ],
    owner: '计算机科学与技术252',
    cells: [
      PublicTimetableCell(
        weekday: 3,
        periodIndex: 1,
        startPeriod: 1,
        endPeriod: 2,
        text: '数据库原理 张三 [2-17]周 1-2节',
        parts: ['数据库原理', '张三', '[2-17]周', '1-2节'],
        startWeek: 2,
        endWeek: 17,
        parity: WeekParity.every,
      ),
    ],
  ),
];

const _profile = PublicQueryAccountProfile(
  enrollYear: '2025',
  college: '信息管理学院',
  major: '计算机科学与技术',
  className: '计算机科学与技术252',
  campusName: '麦庐园校区',
);

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicQueryTermsProvider.overrideWith((ref) async => _terms),
        publicQueryCampusesProvider.overrideWith((ref) async => _campuses),
        publicQueryCollegesProvider.overrideWith((ref, year) async => _colleges),
        publicQueryMajorsProvider.overrideWith((ref, key) async => _majors),
        publicQueryTrainLevelsProvider.overrideWith((ref) async => _levels),
        publicQueryAccountProfileProvider.overrideWith((ref) async => _profile),
        publicQueryComboBoxProvider.overrideWith(
          (ref, request) async => _classes,
        ),
        publicQueryReportProvider.overrideWith(
          (ref, request) async =>
              PublicQueryResult(html: '', timetables: _timetables),
        ),
      ],
      child: MaterialApp(home: FreeTimeScreen(now: DateTime(2026, 9, 16))),
    ),
  );
  // 预填是「校区 → 年级 → 学院 → 专业」四级依赖链，每级要多一帧。
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}


/// 点 InputChip 上的删除图标（M3 默认图标随版本变，按类型找更稳）。
Future<void> _removeClass(WidgetTester tester, String code) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(Key('freeTimeClassChip-$code')),
      matching: find.byType(Icon),
    ),
  );
  await tester.pump();
}

Future<void> _addClasses(WidgetTester tester, List<String> codes) async {
  await tester.tap(find.byKey(const Key('freeTimeAddClass')));
  await tester.pumpAndSettle();
  for (final code in codes) {
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('publicQueryOption-$code')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
  }
  await tester.tap(find.textContaining('确定（'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('首屏：按账号预填筛选条件 + 空态提示', (tester) async {
    await _pumpPage(tester);
    // 校区/学院/专业按「我的校区 + 学籍」预填（匹配不到的留空）。
    expect(find.text('麦庐园校区'), findsOneWidget);
    expect(find.text('信息管理学院'), findsOneWidget);
    expect(find.text('计算机科学与技术'), findsOneWidget);
    // 还没选班级 → 空态。
    expect(find.text('还没有选班级'), findsOneWidget);
    expect(find.byType(FreeTimeView), findsNothing);
  });

  testWidgets('添加班级后出周网格与空闲清单，删除胶囊后回到空态', (tester) async {
    await _pumpPage(tester);
    await _addClasses(tester, ['c1', 'c2']);
    expect(find.byKey(const Key('freeTimeClassChip-c1')), findsOneWidget);
    expect(find.byKey(const Key('freeTimeClassChip-c2')), findsOneWidget);
    expect(find.byType(FreeTimeView), findsOneWidget);

    // 删掉一个 → 只剩 c2，仍是同一块视图。
    await _removeClass(tester, 'c1');
    expect(find.byKey(const Key('freeTimeClassChip-c1')), findsNothing);
    expect(find.byType(FreeTimeView), findsOneWidget);

    // 再删掉最后一个 → 回到空态。
    await _removeClass(tester, 'c2');
    expect(find.byType(FreeTimeView), findsNothing);
    expect(find.text('还没有选班级'), findsOneWidget);
  });

  testWidgets('同一个班不会被加两次', (tester) async {
    await _pumpPage(tester);
    await _addClasses(tester, ['c1']);
    await _addClasses(tester, ['c1']);
    expect(find.byKey(const Key('freeTimeClassChip-c1')), findsOneWidget);
  });

  testWidgets('时间条件：周次 / 最短连续 / 含周末都在，并且能改', (tester) async {
    await _pumpPage(tester);
    expect(find.byKey(const Key('freeTimeWeek')), findsOneWidget);
    expect(find.byKey(const Key('freeTimeMinPeriods')), findsOneWidget);
    expect(find.byKey(const Key('freeTimeIncludeWeekend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('freeTimeIncludeWeekend')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('freeTimeIncludeWeekend')),
          )
          .value,
      isTrue,
    );
  });

  group('源码守卫', () {
    final screen = File(
      'lib/features/ims/public_query/presentation/free_time_screen.dart',
    ).readAsStringSync();
    final publicQuery = File(
      'lib/features/ims/public_query/presentation/public_query_screen.dart',
    ).readAsStringSync();
    final catalog = File(
      'lib/features/home/presentation/home_service_catalog.dart',
    ).readAsStringSync();

    test('公共查询页只留入口卡，内联的对照实现已整体搬走', () {
      expect(publicQuery.contains("Key('publicQueryFindFreeTime')"), isTrue);
      expect(publicQuery.contains('FreeTimeScreen('), isTrue);
      expect(publicQuery.contains('_compareCard'), isFalse);
      expect(publicQuery.contains('_freeTimeSection'), isFalse);
      expect(publicQuery.contains('_compareClasses'), isFalse);
      expect(publicQuery.contains('_pickCompareClasses'), isFalse);
      expect(
        publicQuery.contains('slotsOfTimetables'),
        isFalse,
        reason: '课表槽拼装已经全在 free_time_screen 里',
      );
    });

    test('「找无课时间」不再占首页磁贴（独立的是「找空闲教室」），只走公共查询页入口卡', () {
      // 用户 2026-09-19 二轮纠正：「我希望是把查空教室独立，而不是查无课时间独立」。
      expect(catalog.contains("'找无课时间'"), isFalse);
      expect(catalog.contains('FreeTimeScreen()'), isFalse);
      expect(catalog.contains("'找空闲教室'"), isTrue);
      expect(catalog.contains('ClassroomFreeScreen()'), isTrue);
      expect(publicQuery.contains("Key('publicQueryFindFreeTime')"), isTrue);
    });

    test('本页声明了「教务会话 + 公共查询」两节设置，且不自带刷新以外的入口', () {
      expect(
        screen.contains(
          'settingsSections: const [SettingsSection.imsSession, '
          'SettingsSection.publicQuery]',
        ),
        isTrue,
      );
      expect(screen.contains('PageAutoRefresher(onRefresh: _refreshAll)'), isTrue);
      expect(
        screen.contains('findFreeWindows') || screen.contains('buildOccupancyGrid'),
        isFalse,
        reason: '算法只在 domain/free_time.dart 里，页面只用 FreeTimeView',
      );
    });
  });
}
