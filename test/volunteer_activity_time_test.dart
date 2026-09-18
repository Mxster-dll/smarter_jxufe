import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/volunteer_detail_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';

/// 真实「短期校内活动申报详情」页（`apply_one_detail.html?id=…&type=0`）的
/// 表单片段，已脱敏（姓名 → 某同学、手机号 → 13800000000、长数字 → 2000000000）。
/// ⚠ 页面里 **`id="startTime"` 出现两次**：真实开始时间框（有值，在前）与
/// 备注输入框（空值，在后）—— 解析必须只认第一个 `<input>`。
String _fixture() =>
    File('test/fixtures/volunteer_detail_260526.html').readAsStringSync();

VolunteerActivity _activity({
  int index = 1,
  String hours = '4',
  String start = '',
  String end = '',
}) {
  return VolunteerActivity(
    index: index,
    activityName: '测试活动$index',
    initiator: '发起人',
    responsiblePerson: '负责人',
    department: '社会与人文学院',
    activityCategory: '短期校内活动',
    recognizedHours: hours,
    applicationStatus: '申请通过',
    recognitionStatus: '已认定',
    detailId: '847517',
    detailType: '0',
    startDate: start,
    endDate: end,
  );
}

void main() {
  group('详情页时间解析（志愿活动的时间来源）', () {
    test('从真实详情页取到开始 / 结束时间', () {
      final time = parseVolunteerActivityTime(_fixture());
      expect(time.start, '2026-05-26');
      expect(time.end, '2026-05-26');
    });

    test('id=startTime 出现两次时只认第一个 input（备注框在后面且为空）', () {
      final html = _fixture();
      final inputs = RegExp(
        r'<input[^>]*id="startTime"',
      ).allMatches(html).length;
      expect(inputs, 2, reason: 'fixture 必须保留「备注也叫 startTime」这个陷阱');
      expect(
        parseVolunteerActivityTime(html).start,
        isNotEmpty,
        reason: '取到第二个（备注）就会是空串',
      );
    });

    test('没有时间字段时返回空串', () {
      final time = parseVolunteerActivityTime('<html><body>出错了</body></html>');
      expect(time.start, '');
      expect(time.end, '');
    });

    test('属性顺序颠倒也能取到值', () {
      const html =
          '<input value="2026-01-02" readonly id="startTime" name="startTime">'
          '<input value="2026-01-03" id="endTime">';
      final time = parseVolunteerActivityTime(html);
      expect(time.start, '2026-01-02');
      expect(time.end, '2026-01-03');
    });
  });

  group('活动时间文案与日期解析', () {
    test('起止同日只显示一天', () {
      expect(volunteerTimeText('2026-05-26', '2026-05-26'), '2026-05-26');
      expect(volunteerTimeText('', '2026-05-26'), '2026-05-26');
    });

    test('跨天显示区间；两值皆空为空串', () {
      expect(
        volunteerTimeText('2026-05-25', '2026-05-26'),
        '2026-05-25 ~ 2026-05-26',
      );
      expect(volunteerTimeText('', ''), '');
    });

    test('兼容详情页与登记表两种日期写法', () {
      expect(volunteerParseDate('2026-05-26'), DateTime(2026, 5, 26));
      expect(volunteerParseDate('2026年5月28日'), DateTime(2026, 5, 28));
      expect(volunteerParseDate('2026年10月27日'), DateTime(2026, 10, 27));
      expect(volunteerParseDate(''), isNull);
      expect(volunteerParseDate('2026/05/26'), isNull);
      expect(volunteerParseDate('待定'), isNull);
    });

    test('活动模型：时长、时间文案与归集日期（开始优先、回退结束）', () {
      final a = _activity(hours: '8', start: '2026-05-26', end: '2026-05-26');
      expect(a.hours, 8);
      expect(a.activityTimeText, '2026-05-26');
      expect(a.activityDate, DateTime(2026, 5, 26));

      final b = _activity(hours: '4.5', start: '', end: '2025-10-27');
      expect(b.hours, 4.5);
      expect(b.activityDate, DateTime(2025, 10, 27));

      final c = _activity(hours: 'abc');
      expect(c.hours, 0);
      expect(c.activityTimeText, '');
      expect(c.activityDate, isNull);
    });
  });

  group('本学年志愿时长口径（当下教学学年，非综测测评学年）', () {
    test('总时长含全部；本学年按当下学年归集，上一学年单列', () {
      // now = 2026-09-16 → currentSchoolTerm().xn = 2026 → 本学年 2026-09-01 ~ 2027-08-31，
      // 而 5 条记录都在 2025-2026 学年（上一学年）。
      final stats = volunteerHoursStats([
        _activity(index: 1, hours: '4', start: '2025-10-27'),
        _activity(index: 2, hours: '8', start: '2026-05-26'),
        _activity(index: 3, hours: '4'), // 无日期 → 只进总时长
        _activity(index: 4, hours: '2', start: '2024-03-01'), // 更早，两档都不计
      ], xn: 2026);

      expect(stats.total, 18);
      expect(stats.currentYear, 0, reason: '2026-2027 学年尚无记录');
      expect(stats.previousYear, 12, reason: '2025-10-27 与 2026-05-26 属上一学年');
      expect(stats.yearKnown, isTrue);
      expect(stats.xn, 2026);
      expect(stats.yearLabel, '2026-2027学年');
      expect(stats.previousYearLabel, '2025-2026学年');
    });

    test('学年窗口边界：09-01 起算、08-31 收尾', () {
      final stats = volunteerHoursStats([
        _activity(index: 1, hours: '1', start: '2026-09-01'),
        _activity(index: 2, hours: '2', start: '2027-08-31'),
        _activity(index: 3, hours: '4', start: '2026-08-31'),
        _activity(index: 4, hours: '8', start: '2027-09-01'),
      ], xn: 2026);
      expect(stats.total, 15);
      expect(stats.currentYear, 3);
      expect(stats.previousYear, 4);
    });

    test('3 月（第二学期）时 xn = 上一年，学年窗口跟着走', () {
      // 2026-03-01 属 252（2025-2026 第二学期）→ xn = 2025
      final stats = volunteerHoursStats([
        _activity(index: 1, hours: '4', start: '2024-10-01'),
        _activity(index: 2, hours: '8', start: '2025-10-01'),
      ], xn: 2025);
      expect(stats.currentYear, 8, reason: '2025-10-01 在 2025-2026 学年内');
      expect(stats.previousYear, 4);
      expect(stats.yearLabel, '2025-2026学年');
    });

    test('一条日期都取不到时 yearKnown=false（界面应显示「—」而不是 0）', () {
      final stats = volunteerHoursStats([
        _activity(index: 1, hours: '4'),
        _activity(index: 2, hours: '8'),
      ], xn: 2026);
      expect(stats.total, 12);
      expect(stats.currentYear, 0);
      expect(stats.previousYear, 0);
      expect(stats.yearKnown, isFalse);
    });

    test('空列表不炸', () {
      final stats = volunteerHoursStats(const [], xn: 2026);
      expect(stats.total, 0);
      expect(stats.currentYear, 0);
      expect(stats.yearKnown, isFalse);
    });
  });

  group('志愿页显示每个活动的时间（用户 2026-09-16 要求）', () {
    Widget app(List<VolunteerActivity> activities) {
      return ProviderScope(
        overrides: [
          volunteerActivitiesProvider.overrideWith((ref) async => activities),
        ],
        child: const MaterialApp(home: VolunteerHoursScreen()),
      );
    }

    testWidgets('有时间的活动显示「活动时间：…」行', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app([_activity(hours: '8', start: '2026-05-26', end: '2026-05-26')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('活动时间：2026-05-26'), findsOneWidget);
      expect(find.text('8 小时'), findsOneWidget);
    });

    testWidgets('跨天活动显示区间；取不到时间的活动不显示该行', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app([
          _activity(hours: '4', start: '2025-05-25', end: '2025-05-27'),
          _activity(index: 2, hours: '2'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('活动时间：2025-05-25 ~ 2025-05-27'), findsOneWidget);
      expect(find.textContaining('活动时间：'), findsOneWidget);
    });
  });

  group('接入点守卫（仪表盘胶囊 / 志愿页时间行 / 列表详情接口）', () {
    test('仪表盘「志愿时长」卡带本学年胶囊，口径来自 volunteerHoursStats', () {
      final panel = File(
        'lib/features/home/presentation/dashboard_panel.dart',
      ).readAsStringSync();
      expect(panel.contains("Key('dash_volunteer_year')"), isTrue);
      expect(panel.contains('本学年'), isTrue);
      expect(panel.contains('volunteerHoursStats'), isTrue);
      expect(
        panel.contains('FutureProvider<VolunteerHoursStats>'),
        isTrue,
        reason: '仪表盘 provider 必须返回统计结果（总时长 + 本学年），别退回 double',
      );
      expect(
        panel.contains('currentSchoolTerm(') &&
            panel.contains('offlineSemesterTermsProvider'),
        isTrue,
        reason: '本学年 = 当下教学学年（currentSchoolTerm 口径），别用综测的测评学年',
      );
    });

    test('志愿页卡片渲染活动时间行', () {
      final screen = File(
        'lib/features/comprehensive_service/presentation/volunteer_hours_screen.dart',
      ).readAsStringSync();
      expect(screen.contains('activity.activityTimeText'), isTrue);
      expect(screen.contains('活动时间：'), isTrue);
    });

    test('仓库层逐行并发补齐时间（单条失败只让该行缺时间）', () {
      final repo = File(
        'lib/features/comprehensive_service/data/volunteer_hours_repository.dart',
      ).readAsStringSync();
      expect(repo.contains('fetchActivityTime'), isTrue);
      expect(repo.contains('Future.wait'), isTrue);
    });
  });
}
