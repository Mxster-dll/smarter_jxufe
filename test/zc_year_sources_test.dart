/// 综测「按学年算」守卫（用户 2026-09-16 裁定）。
///
/// 覆盖两层：
/// 1. 纯函数 —— 学期码解析、学年内课程加权、学年内志愿时长；
/// 2. 源码守卫 —— provider 必须是 `family<double?, int>`（参数 = 学年结束年），
///    页面必须传 `_year`，且不能再出现「跨学年累计」的旧写法。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_prior_grades.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_year_sources.dart';

GePriorGrade _g(String name, double score, double credits, String semester) =>
    GePriorGrade(
      courseCode: name,
      courseName: name,
      score: score,
      credits: credits,
      semester: semester,
    );

VolunteerActivity _act(String hours, String start, String end) =>
    VolunteerActivity(
      index: 1,
      activityName: '活动',
      initiator: '某同学',
      responsiblePerson: '某同学',
      department: '学院',
      activityCategory: '志愿服务',
      recognizedHours: hours,
      applicationStatus: '已通过',
      recognitionStatus: '已认定',
      detailId: '1',
      detailType: '0',
      startDate: start,
      endDate: end,
    );

void main() {
  group('学期码 → 学年起始年', () {
    test('短编号 yy+学段：三个学段都属于同一学年', () {
      expect(zcSemesterStartYear('251'), 2025);
      expect(zcSemesterStartYear('252'), 2025);
      expect(zcSemesterStartYear('253'), 2025, reason: '第二阶段仍属同一学年');
      expect(zcSemesterStartYear('261'), 2026);
      expect(zcSemesterStartYear('242'), 2024);
    });

    test('完整学期名也认', () {
      expect(zcSemesterStartYear('2025-2026学年第一学期'), 2025);
      expect(zcSemesterStartYear('2026-2027 学年第二阶段'), 2026);
    });

    test('认不出 → null（不能兜底成某年，否则会算进别的学年的课）', () {
      expect(zcSemesterStartYear(''), isNull);
      expect(zcSemesterStartYear('  '), isNull);
      expect(zcSemesterStartYear('25'), isNull);
      expect(zcSemesterStartYear('250'), isNull, reason: '末位 0 不是合法学段');
      expect(zcSemesterStartYear('25x'), isNull);
      expect(zcSemesterStartYear('2025-2026'), isNull, reason: '缺「学年」二字');
      expect(zcSemesterStartYear('第一学期'), isNull);
    });
  });

  group('课程加权按学年', () {
    test('只算该学年的课，学分为 0 的不进权重', () {
      final grades = <GePriorGrade>[
        _g('A', 90, 2, '251'),
        _g('B', 80, 3, '252'),
        _g('C', 100, 2, '261'), // 2026-2027，不属于 2025-2026
        _g('D', 60, 0, '251'), // 学分缺失 → 不计入
      ];
      // (90×2 + 80×3) / (2+3) = 84
      expect(zcWeightedForYear(grades, yearEnd: 2026), 84);
      // 2026-2027 只有 C
      expect(zcWeightedForYear(grades, yearEnd: 2027), 100);
      // 2024-2025 没有课
      expect(zcWeightedForYear(grades, yearEnd: 2025), isNull);
    });

    test('学期认不出的课并入该学年（= 成绩页「课程加权」口径，用户 2026-09-17 裁定）', () {
      // 用户原话：「综测页智育部分自动获取的成绩应该是课程加权，而不是推免加权」。
      // 成绩页「课程加权」（_calcAvgScore）从不按学年过滤 → 智育若把认不出
      // 学期的课丢掉（如实训课），就会与成绩页对不上（实测 91.89091 vs 91.85965）。
      final grades = <GePriorGrade>[
        _g('A', 90, 2, '251'),
        _g('E', 50, 4, ''), // 学期码为空（教务不给）→ 并入本学年
      ];
      expect(
        zcWeightedForYear(grades, yearEnd: 2026),
        closeTo((90 * 2 + 50 * 4) / 6, 0.0001),
      );
      // 但一门认不出学期的课**不能**把每个学年都凑出一个分：
      // 该学年没有学期码明确的课 → 仍是 null（界面回退手动填写）。
      expect(zcWeightedForYear([_g('E', 50, 4, '')], yearEnd: 2026), isNull);
      expect(zcWeightedForYear([_g('A', 90, 2, '261')], yearEnd: 2026), isNull);
    });

    test('空列表 / 全无学分 / 全是他学年 → null（界面回退手动填写）', () {
      expect(zcWeightedForYear(const [], yearEnd: 2026), isNull);
      expect(zcWeightedForYear([_g('A', 90, 0, '251')], yearEnd: 2026), isNull);
      expect(zcWeightedForYear([_g('A', 90, 2, '261')], yearEnd: 2026), isNull);
    });
  });

  group('志愿时长按学年', () {
    test('按活动日期归入学年窗口（2025-09-01 ~ 2026-08-31）', () {
      final acts = <VolunteerActivity>[
        _act('8', '2026-05-26', '2026-05-26'),
        _act('4', '2025-10-22', '2025-10-23'),
        _act('2', '2026-10-01', '2026-10-01'), // 下一学年
      ];
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2026), 12);
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2027), 2);
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2025), 0);
    });

    test('学年窗口边界：08-31 计入、09-01 归下一学年', () {
      final acts = <VolunteerActivity>[
        _act('3', '2026-08-31', '2026-08-31'),
        _act('5', '2026-09-01', '2026-09-01'),
      ];
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2026), 3);
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2027), 5);
    });

    test('一条日期都取不到 → null（别显示 0）', () {
      final acts = <VolunteerActivity>[_act('8', '', ''), _act('4', '', '')];
      expect(zcVolunteerHoursForYear(acts, yearEnd: 2026), isNull);
    });

    test('空列表 → null', () {
      expect(zcVolunteerHoursForYear(const [], yearEnd: 2026), isNull);
    });
  });

  group('源码守卫：自动源必须按学年', () {
    test('provider 是 family<double?, int> 且走学年纯函数', () {
      final src = File(
        'lib/features/zongce/data/zc_providers.dart',
      ).readAsStringSync();
      expect(
        'FutureProvider.family<double?, int>'.allMatches(src).length,
        2,
        reason: '两个自动源都要按学年取数',
      );
      expect(src, contains('zcWeightedForYear'));
      expect(src, contains('zcVolunteerHoursForYear'));
      expect(src, contains('gePriorGradesProvider'));
      expect(
        src.contains('weightedGradeRankingProvider'),
        isFalse,
        reason: '教务「全部课程加权」是跨学年累计，已弃用',
      );
    });

    test('页面用 _year 作参数，刷新时连带失效底层数据源', () {
      final src = File(
        'lib/features/zongce/presentation/zongce_screen.dart',
      ).readAsStringSync();
      expect(src, contains('ref.watch(zcAutoWeightProvider(_year))'));
      expect(src, contains('ref.watch(zcAutoVolunteerProvider(_year))'));
      expect(src, contains('ref.invalidate(zcAutoWeightProvider(_year))'));
      expect(src, contains('ref.invalidate(zcAutoVolunteerProvider(_year))'));
      expect(src, contains('ref.invalidate(gePriorGradesProvider)'));
      expect(src, contains('ref.invalidate(volunteerActivitiesProvider)'));
    });

    test('行内文案按学年口径', () {
      final src = File(
        'lib/features/zongce/presentation/zongce_screen.dart',
      ).readAsStringSync();
      expect(src, contains('学年志愿时长(h)'));
      // 用户 2026-09-18 五轮：「加权和体测成绩不要显示『自动』字样」
      expect(
        src,
        contains("tag: manual ? '手动' : null,"),
        reason: '自动带入的值不挂标，只有手动覆盖挂「手动」',
      );
      expect(
        src,
        isNot(contains("(autoValue == null ? null : '自动')")),
        reason: '「自动」小标已按用户 2026-09-18 五轮裁定撤掉',
      );
      expect(
        src,
        isNot(contains('_ticeFilled')),
        reason: '体测的「自动」小标连带字段一起删（避免留下没人读的字段）',
      );
      // 用户 2026-09-18 四轮：行内说明（含课程加权口径那句）已随「纯文字悬停」
      // 一起撤掉 → 口径改由上面的数据链路守卫，这里只守「加权仍是 2 位」与
      // 「页面不留纯文字悬停」。
      expect(src, contains('_fmt2(r.weightUsed)'));
      expect(src, isNot(contains('Tooltip(')));
      expect(src.contains('自动累计'), isFalse, reason: '「自动累计」是跨学年口径的旧文案');
    });
  });
}
