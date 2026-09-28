import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart'
    show schoolTermLabel;
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart';

/// 学校时间轴（学年 / 学期 / 假期）—— 用户 2026-09-27 口径：
/// 「学年的时间范围就定为该学年第一学期第一天到下学年第一天前一天；
///   假期时间也可以从校历页查」。
///
/// 备注数据 = **教务校历页实测原文**（2026-09-27 探针
/// `.scratch/xt_cal_probe*.py` 抓的 `jwxt.jxufe.edu.cn/public/
/// SchoolCalendar.show.jsp` 右侧 `<textarea name="bz">`）。
void main() {
  group('备注解析：教务校历页的四行日期', () {
    test('四行齐 → 学期 / 假期起止各归其位', () {
      final dates = schoolTermDatesFromNotes(
        const [
          '学期开始日期：2026-09-07',
          '学期结束日期：2027-01-15',
          '假期开始日期：2027-01-16',
          '假期结束日期：2027-01-19',
        ],
        xn: 2026,
        xq: 0,
      );
      expect(dates.termStart, DateTime(2026, 9, 7));
      expect(dates.termEnd, DateTime(2027, 1, 15));
      expect(dates.breakStart, DateTime(2027, 1, 16));
      expect(dates.breakEnd, DateTime(2027, 1, 19));
      expect(dates.isPublished, isTrue);
      expect(dates.termDays, 131);
      expect(dates.label, '2026-2027 学年第一学期');
    });

    test('只有学期两行（第二学段 / 暑期段就是这种）', () {
      final dates = schoolTermDatesFromNotes(
        const ['学期开始日期：2026-03-02', '学期结束日期：2026-07-05'],
        xn: 2025,
        xq: 1,
      );
      expect(dates.termStart, DateTime(2026, 3, 2));
      expect(dates.breakStart, isNull);
      expect(dates.breakEnd, isNull);
      expect(dates.isPublished, isTrue);
      expect(dates.termDays, 126);
    });

    test('容错：全角冒号、前后空白、无关键都忽略、乱序也行', () {
      final dates = schoolTermDatesFromNotes(
        const [
          '  假期结束日期: 2026-03-01 ',
          '如有调整，另行通知。',
          '学期开始日期： 2025-09-01',
          '假期开始日期	：2026-01-16',
          '学期结束日期：2026-01-15',
        ],
        xn: 2025,
        xq: 0,
      );
      expect(dates.termStart, DateTime(2025, 9, 1));
      expect(dates.termEnd, DateTime(2026, 1, 15));
      expect(dates.breakStart, DateTime(2026, 1, 16));
      expect(dates.breakEnd, DateTime(2026, 3, 1));
    });

    test('空壳页（未公布学年，723 字节）→ 四行全无', () {
      final dates = schoolTermDatesFromNotes(const [], xn: 2027, xq: 0);
      expect(dates.isPublished, isFalse);
      expect(dates.termStart, isNull);
      expect(dates.termEnd, isNull);
      expect(dates.termDays, isNull);
      expect(dates.breakStart, isNull);
    });

    test('schoolTermDatesOf 从校历页取（notes 就是备注行）', () {
      final dates = schoolTermDatesOf(
        _cal(2024, 0, const [
          '学期开始日期：2024-09-02',
          '学期结束日期：2025-01-10',
          '假期开始日期：2025-01-11',
          '假期结束日期：2025-02-16',
        ]),
      );
      expect(dates.xn, 2024);
      expect(dates.xq, 0);
      expect(dates.termStart, DateTime(2024, 9, 2));
      expect(dates.breakEnd, DateTime(2025, 2, 16));
    });
  });

  group('学年：第一学期第一天 ~ 下学年第一天前一天', () {
    test('下学年已公布 → 结束日 = 下学年第一学段开始 − 1 天', () {
      final table = _tableThrough2026();
      final year = table.yearOf(2025);
      expect(year.firstDay, DateTime(2025, 9, 1));
      expect(year.lastDay, DateTime(2026, 9, 6));
      expect(year.isComplete, isTrue);
      expect(year.label, '2025-2026学年');
      expect(year.rangeText, '2025-09-01 ~ 2026-09-06');
      // 与教务页 2025 学年第二阶段的「假期结束日期：2026-09-06」逐字吻合。
      expect(table.termAt(2025, 2)!.breakEnd, DateTime(2026, 9, 6));
    });

    test('下学年未公布 → 结束日留 null（不猜，用户 2026-09-27 裁定）', () {
      final year = _tableThrough2026().yearOf(2026);
      expect(year.firstDay, DateTime(2026, 9, 7));
      expect(year.lastDay, isNull);
      expect(year.isKnown, isTrue);
      expect(year.isComplete, isFalse);
      expect(year.rangeText, '2026-09-07 起（下学年校历未公布）');
    });

    test('结束日未知 → 开区间：不早于第一天即属本学年', () {
      final year = _tableThrough2026().yearOf(2026);
      expect(year.contains(DateTime(2026, 9, 7)), isTrue);
      expect(year.contains(DateTime(2030, 1, 1)), isTrue);
      expect(year.contains(DateTime(2026, 9, 6)), isFalse);
      expect(year.contains(DateTime(2027, 1, 20)), isTrue);
    });

    test('封闭学年按端点判定（含首尾两天）', () {
      final year = _tableThrough2026().yearOf(2025);
      expect(year.contains(DateTime(2025, 9, 1)), isTrue);
      expect(year.contains(DateTime(2026, 9, 6)), isTrue);
      expect(year.contains(DateTime(2026, 9, 7)), isFalse);
      // 时刻部分不参与判定（同一天任意时刻同结果）。
      expect(year.contains(DateTime(2025, 8, 31, 23, 59)), isFalse);
      expect(year.contains(DateTime(2026, 9, 6, 23, 59)), isTrue);
    });

    test('学年完全未收录 → 未知、contains 恒 false', () {
      final year = SchoolTimeTable.empty.yearOf(2026);
      expect(year.isKnown, isFalse);
      expect(year.isComplete, isFalse);
      expect(year.contains(DateTime(2026, 10, 1)), isFalse);
      expect(year.rangeText, '2026-2027学年（校历未公布）');
    });

    test('schoolYearOf 直接给两个学段也能算', () {
      final year = schoolYearOf(
        xn: 2024,
        first: schoolTermDatesFromNotes(
          const ['学期开始日期：2024-09-02'],
          xn: 2024,
          xq: 0,
        ),
        nextFirst: schoolTermDatesFromNotes(
          const ['学期开始日期：2025-09-01'],
          xn: 2025,
          xq: 0,
        ),
      );
      expect(year.lastDay, DateTime(2025, 8, 31));
    });
  });

  group('假期：寒 / 暑假（结束日一律派生自下一段起点）', () {
    test('已公布学年 → 两个假期都有确定天数', () {
      final breaks = _tableThrough2026().breaksOf(2025);
      expect(breaks.length, 2);

      final winter = breaks.firstWhere((b) => b.kind == SchoolBreakKind.winter);
      expect(winter.label, '寒假');
      expect(winter.start, DateTime(2026, 1, 16));
      expect(winter.end, DateTime(2026, 3, 1));
      expect(winter.days, 45);
      expect(winter.certain, isTrue);
      expect(winter.contains(DateTime(2026, 2, 1)), isTrue);
      expect(winter.contains(DateTime(2026, 3, 2)), isFalse);

      final summer = breaks.firstWhere((b) => b.kind == SchoolBreakKind.summer);
      expect(summer.label, '暑假');
      expect(summer.start, DateTime(2026, 7, 11));
      expect(summer.end, DateTime(2026, 9, 6));
      expect(summer.days, 58);
    });

    test('2024 学年：寒假 37 天 / 暑假 58 天（与实测台账一致）', () {
      final breaks = _tableThrough2026().breaksOf(2024);
      final winter = breaks.firstWhere((b) => b.kind == SchoolBreakKind.winter);
      final summer = breaks.firstWhere((b) => b.kind == SchoolBreakKind.summer);
      expect(winter.start, DateTime(2025, 1, 11));
      expect(winter.end, DateTime(2025, 2, 16));
      expect(winter.days, 37);
      expect(summer.start, DateTime(2025, 7, 5));
      expect(summer.end, DateTime(2025, 8, 31));
      expect(summer.days, 58);
    });

    test('2026 学年：寒假被串成 4 天 → 判占位，结束日 null', () {
      final breaks = _tableThrough2026().breaksOf(2026);
      final winter = breaks.firstWhere((b) => b.kind == SchoolBreakKind.winter);
      expect(winter.start, DateTime(2027, 1, 16));
      expect(winter.certain, isFalse);
      expect(winter.end, isNull);
      expect(winter.days, isNull);
      // 开始日已知 → 那一天仍算假期。
      expect(winter.contains(DateTime(2027, 1, 16)), isTrue);
      expect(winter.contains(DateTime(2027, 2, 1)), isTrue);
    });

    test('2026 学年：下学年未公布 → 暑假结束日 null', () {
      final breaks = _tableThrough2026().breaksOf(2026);
      final summer = breaks.firstWhere((b) => b.kind == SchoolBreakKind.summer);
      expect(summer.start, DateTime(2027, 8, 1));
      expect(summer.end, isNull);
      expect(summer.certain, isFalse);
      // 教务页那个「假期结束日期：2027-09-30」是占位，只作存档。
      expect(
        _tableThrough2026().termAt(2026, 2)!.breakEnd,
        DateTime(2027, 9, 30),
      );
    });

    test('跨度恰好达标即采信（边界：寒假 14 天 / 暑假 21 天）', () {
      final winter = schoolBreaksOfYear(
        xn: 2026,
        first: schoolTermDatesFromNotes(
          const ['学期开始日期：2026-09-07', '假期开始日期：2027-01-20'],
          xn: 2026,
          xq: 0,
        ),
        second: schoolTermDatesFromNotes(
          const ['学期开始日期：2027-02-03'],
          xn: 2026,
          xq: 1,
        ),
      ).firstWhere((b) => b.kind == SchoolBreakKind.winter);
      expect(winter.days, 14); // 01-20 ~ 02-02
      expect(winter.certain, isTrue);

      final summer = schoolBreaksOfYear(
        xn: 2026,
        summer: schoolTermDatesFromNotes(
          const ['假期开始日期：2027-07-11'],
          xn: 2026,
          xq: 2,
        ),
        nextFirst: schoolTermDatesFromNotes(
          const ['学期开始日期：2027-08-01'],
          xn: 2027,
          xq: 0,
        ),
      ).firstWhere((b) => b.kind == SchoolBreakKind.summer);
      expect(summer.days, 21);
      expect(summer.certain, isTrue);
    });

    test('没有假期开始日但有学期结束日 → 用「学期结束 + 1 天」兜', () {
      final breaks = schoolBreaksOfYear(
        xn: 2026,
        first: schoolTermDatesFromNotes(
          const ['学期结束日期：2027-01-15'],
          xn: 2026,
          xq: 0,
        ),
        second: schoolTermDatesFromNotes(
          const ['学期开始日期：2027-03-01'],
          xn: 2026,
          xq: 1,
        ),
      );
      expect(breaks.single.start, DateTime(2027, 1, 16));
      expect(breaks.single.end, DateTime(2027, 2, 28));
    });

    test('两个学段都空 → 不给假期（不造空壳）', () {
      expect(schoolBreaksOfYear(xn: 2026), isEmpty);
      expect(SchoolTimeTable.empty.breaksOf(2026), isEmpty);
    });
  });

  group('时间表：归属查询与构建', () {
    test('fromCalendars 建表 + termAt 查找', () {
      final table = SchoolTimeTable.fromCalendars([
        _cal(2025, 0, const [
          '学期开始日期：2025-09-01',
          '学期结束日期：2026-01-15',
        ]),
        _cal(2026, 0, const ['学期开始日期：2026-09-07']),
      ]);
      expect(table.terms.length, 2);
      expect(table.termAt(2025, 0)!.termStart, DateTime(2025, 9, 1));
      expect(table.termAt(2025, 1), isNull);
      expect(table.toString(), contains('2 个学段'));
    });

    test('yearContaining：学期中、寒假中、新学年第一天', () {
      final table = _tableThrough2026();
      final inTerm = table.yearContaining(DateTime(2025, 10, 1));
      expect(inTerm!.xn, 2025);

      // 寒假（2026-01-16 ~ 03-01）仍属 2025-2026 学年（学年止于 09-06）。
      final inWinter = table.yearContaining(DateTime(2026, 1, 20));
      expect(inWinter!.xn, 2025);

      // 2026-09-07 = 2026 学年第一天 → 归属新学年。
      expect(table.yearContaining(DateTime(2026, 9, 7))!.xn, 2026);
      expect(table.yearContaining(DateTime(2027, 3, 1))!.xn, 2026);

      // 早于全部已知数据 → null。
      expect(table.yearContaining(DateTime(2001, 1, 1)), isNull);
    });

    test('2023 / 2024 学年台账复核（探针原始数据）', () {
      final table = _tableThrough2026();
      expect(table.yearOf(2023).lastDay, DateTime(2024, 9, 1));
      expect(table.yearOf(2024).lastDay, DateTime(2025, 8, 31));
      final y2023 = table.breaksOf(2023);
      expect(
        y2023.firstWhere((b) => b.kind == SchoolBreakKind.winter).days,
        37,
      );
      expect(
        y2023.firstWhere((b) => b.kind == SchoolBreakKind.summer).days,
        53,
      );
    });
  });

  group('学期标识归一（跨模块唯一换算）', () {
    test('短码三位', () {
      expect(schoolTermOfText('261'), (xn: 2026, xq: 0));
      expect(schoolTermOfText('252'), (xn: 2025, xq: 1));
      expect(schoolTermOfText('253'), (xn: 2025, xq: 2));
      expect(schoolYearOfTermText('251'), 2025);
    });

    test('完整学期名（中文数字 / 阿拉伯数字、空格有无）', () {
      expect(schoolTermOfText('2025-2026学年第一学期'), (xn: 2025, xq: 0));
      expect(schoolTermOfText('2025-2026 学年第二学期'), (xn: 2025, xq: 1));
      expect(schoolTermOfText('2025-2026学年第2学期'), (xn: 2025, xq: 1));
      expect(schoolYearOfTermText('2025-2026学年第三学期'), 2025);
    });

    test('只写学年 → 给得出学年、给不出学期号', () {
      expect(schoolYearOfTermText('2025-2026学年'), 2025);
      expect(schoolYearOfTermText('2025-2026 学年'), 2025);
      expect(schoolTermOfText('2025-2026学年'), isNull);
    });

    test('认不出 → null（绝不兜默认年份）', () {
      expect(schoolYearOfTermText(''), isNull);
      expect(schoolYearOfTermText('第一学期'), isNull);
      expect(schoolYearOfTermText('251学期'), isNull);
      expect(schoolTermOfText('2611'), isNull);
      expect(schoolTermOfText('abc'), isNull);
    });

    test('与既有实现的等价性（迁移口径）', () {
      // 旧：`zc_year_sources.dart` 的 zcSemesterStartYear
      for (final raw in ['251', '252', '253', '2025-2026学年第一学期']) {
        expect(schoolYearOfTermText(raw), isNotNull, reason: raw);
      }
      // 旧：`ims/grades/domain/semester.dart` 的 Semester.parse（中文数字）
      final term = schoolTermOfText('2025-2026学年第一学期')!;
      expect(term.xn, 2025);
      expect(term.xq + 1, 1); // semesterNumber
    });

    test('schoolTermCodeOfText / schoolTermOfCode 转发一致', () {
      expect(schoolTermCodeOfText('2025-2026学年第一学期'), '251');
      expect(schoolTermCodeOfText('认不出'), '');
      expect(schoolTermOfCode('261'), (xn: 2026, xq: 0));
      expect(schoolTermOfCode('263'), (xn: 2026, xq: 2));
      expect(schoolTermOfCode('26'), isNull);
      expect(schoolTermOfCode('999'), isNull);
    });

    test('学期全名（教务原文格式，无空格）与短码互转', () {
      expect(schoolTermFullName(2025, 0), '2025-2026学年第一学期');
      expect(schoolTermFullName(2026, 1), '2026-2027学年第二学期');
      expect(schoolTermFullName(2026, 2), '2026-2027学年第三学期');
      expect(schoolTermTextOfCode('262'), '2026-2027学年第二学期');
      expect(schoolTermTextOfCode(''), '');
      expect(schoolTermTextOfCode('xx'), '');
      // 带空格的界面口径不被污染（school_term.dart 的 schoolTermLabel）。
      expect(schoolTermLabel(2025, 0), '2025-2026 学年第一学期');
    });
  });

  group('固定口径兜底与「日期 → 学年」（2026-09-27 从 zongce / 志愿时长收上来）', () {
    test('schoolYearFallback：09-01 起算、次年 08-31 收尾（含首尾整日）', () {
      final year = schoolYearFallback(2026);
      expect(year.xn, 2026);
      expect(year.firstDay, DateTime(2026, 9, 1));
      expect(year.lastDay, DateTime(2027, 8, 31));
      expect(year.isComplete, isTrue);
      expect(year.contains(DateTime(2026, 9, 1)), isTrue);
      expect(year.contains(DateTime(2027, 8, 31, 23, 59, 59)), isTrue,
          reason: '时刻部分不参与判定，末日整天都算');
      expect(year.contains(DateTime(2026, 8, 31)), isFalse);
      expect(year.contains(DateTime(2027, 9, 1)), isFalse);
      expect(year.rangeText, '2026-09-01 ~ 2027-08-31');
    });

    test('schoolYearOrFallback：没传校历 / 该学年未收录 → 固定口径', () {
      expect(schoolYearOrFallback(null, 2026).firstDay, DateTime(2026, 9, 1));
      expect(
        schoolYearOrFallback(SchoolTimeTable.empty, 2026).lastDay,
        DateTime(2027, 8, 31),
      );
    });

    test('schoolYearOrFallback：有校历 → 真实学年末（比 08-31 多 6 天）', () {
      final table = _tableThrough2026();
      final y2025 = schoolYearOrFallback(table, 2025);
      expect(y2025.firstDay, DateTime(2025, 9, 1));
      expect(y2025.lastDay, DateTime(2026, 9, 6));
      expect(y2025.contains(DateTime(2026, 9, 3)), isTrue,
          reason: '2026-2027 学年 09-07 才开学 → 09-03 仍属 2025-2026 学年');
      expect(schoolYearFallback(2025).contains(DateTime(2026, 9, 3)), isFalse,
          reason: '固定口径 08-31 就截断了');
      // 当下学年：下学年未公布 → 开到 09-07 之后
      final y2026 = schoolYearOrFallback(table, 2026);
      expect(y2026.firstDay, DateTime(2026, 9, 7));
      expect(y2026.lastDay, isNull);
      expect(y2026.contains(DateTime(2027, 5, 1)), isTrue);
      expect(y2026.contains(DateTime(2026, 9, 6)), isFalse);
    });

    test('schoolYearStartOf：09-01 为界', () {
      expect(schoolYearStartOf(DateTime(2026, 9, 1)), 2026);
      expect(schoolYearStartOf(DateTime(2026, 9, 30)), 2026);
      expect(schoolYearStartOf(DateTime(2026, 8, 31)), 2025);
      expect(schoolYearStartOf(DateTime(2026, 3, 1)), 2025);
    });
  });

  group('源码守卫：唯一出处', () {
    test('学年 / 假期类型与学期归一只有一份实现', () {
      _expectSingleDefinition('class SchoolYear {');
      _expectSingleDefinition('class SchoolBreak {');
      _expectSingleDefinition('class SchoolTermDates {');
      _expectSingleDefinition('class SchoolTimeTable {');
      _expectSingleDefinition('int? schoolYearOfTermText(');
      _expectSingleDefinition('List<SchoolBreak> schoolBreaksOfYear(');
      _expectSingleDefinition('SchoolYear schoolYearFallback(int xn)');
      _expectSingleDefinition('SchoolYear schoolYearOrFallback(');
      _expectSingleDefinition('int schoolYearStartOf(DateTime day)');
    });

    test('zongce / 志愿时长的学年窗口只剩转发（不许再写日期算术）', () {
      final models = _read('lib/features/zongce/domain/zc_models.dart');
      final stats = _read(
        'lib/features/comprehensive_service/domain/volunteer_hours_stats.dart',
      );
      for (final src in [models, stats]) {
        expect(src.contains('DateTime(xn'), isFalse);
        expect(src.contains('DateTime(yearEnd'), isFalse);
        expect(src.contains('bool _inYear('), isFalse);
      }
      // 两处都明确指向本层
      expect(models.contains('schoolYearFallback(yearEnd - 1)'), isTrue);
      expect(models.contains('int zcDefaultYear(DateTime now) => schoolYearStartOf(now);'),
          isTrue);
      expect(stats.contains('schoolYearOrFallback(table, xn)'), isTrue);
      // 竞赛奖励的「本学年」筛选预设同样走本层（「本学期」的近似区间有意保留）
      final award = _read('lib/features/competition_award/presentation/award_common.dart');
      final yearBranch = award.substring(
        award.indexOf('AwardRangePreset.currentYear'),
        award.indexOf('for (final t in terms)'),
      );
      expect(yearBranch.contains('schoolYearFallback(term.xn)'), isTrue);
      expect(yearBranch.contains('DateTime('), isFalse,
          reason: '「本学年」分支里不许再出现日期算术');
    });

    test('志愿时长的两个取数入口都把校历传下去了', () {
      final home = _read('lib/features/home/data/providers/dashboard_providers.dart');
      final zc = _read('lib/features/zongce/data/zc_providers.dart');
      expect(home.contains('schoolTimeTableProvider(term.xn)'), isTrue);
      expect(home.contains('volunteerHoursStats(activities, xn: term.xn, table: table)'),
          isTrue);
      expect(zc.contains('schoolTimeTableProvider(yearEnd - 1)'), isTrue);
      expect(zc.contains('zcVolunteerHoursForYear(acts, yearEnd: yearEnd, table: table)'),
          isTrue);
      // 综测的转发层也要能收表
      final sources = _read('lib/features/zongce/domain/zc_year_sources.dart');
      expect(sources.contains('table: table'), isTrue);
    });
  });
}

/// 2023 ~ 2026 四学年的实测备注（探针原文，见文件头表格）。
SchoolTimeTable _tableThrough2026() => SchoolTimeTable.fromCalendars([
      _cal(2023, 0, const [
        '学期开始日期：2023-09-04',
        '学期结束日期：2024-01-19',
        '假期开始日期：2024-01-20',
        '假期结束日期：2024-02-25',
      ]),
      _cal(2023, 1, const [
        '学期开始日期：2024-02-26',
        '学期结束日期：2024-07-03',
      ]),
      _cal(2023, 2, const [
        '学期开始日期：2024-07-04',
        '学期结束日期：2024-07-10',
        '假期开始日期：2024-07-11',
        '假期结束日期：2024-09-01',
      ]),
      _cal(2024, 0, const [
        '学期开始日期：2024-09-02',
        '学期结束日期：2025-01-10',
        '假期开始日期：2025-01-11',
        '假期结束日期：2025-02-16',
      ]),
      _cal(2024, 1, const [
        '学期开始日期：2025-02-17',
        '学期结束日期：2025-06-29',
      ]),
      _cal(2024, 2, const [
        '学期开始日期：2025-06-30',
        '学期结束日期：2025-07-04',
        '假期开始日期：2025-07-05',
        '假期结束日期：2025-08-31',
      ]),
      _cal(2025, 0, const [
        '学期开始日期：2025-09-01',
        '学期结束日期：2026-01-15',
        '假期开始日期：2026-01-16',
        '假期结束日期：2026-03-01',
      ]),
      _cal(2025, 1, const [
        '学期开始日期：2026-03-02',
        '学期结束日期：2026-07-05',
      ]),
      _cal(2025, 2, const [
        '学期开始日期：2026-07-06',
        '学期结束日期：2026-07-10',
        '假期开始日期：2026-07-11',
        '假期结束日期：2026-09-06',
      ]),
      _cal(2026, 0, const [
        '学期开始日期：2026-09-07',
        '学期结束日期：2027-01-15',
        '假期开始日期：2027-01-16',
        '假期结束日期：2027-01-19',
      ]),
      _cal(2026, 1, const [
        '学期开始日期：2027-01-20',
        '学期结束日期：2027-07-05',
      ]),
      _cal(2026, 2, const [
        '学期开始日期：2027-07-06',
        '学期结束日期：2027-07-31',
        '假期开始日期：2027-08-01',
        '假期结束日期：2027-09-30',
      ]),
    ]);

SchoolCalendar _cal(int xn, int xq, List<String> notes) => SchoolCalendar(
      title: '',
      xn: xn,
      xq: xq,
      months: const [],
      notes: notes,
    );

const String _timeSrcPath =
    'lib/features/school_calendar/domain/school_time.dart';

/// 读一个仓库内文件（守卫用）。
String _read(String path) => File(path).readAsStringSync();

/// 该声明**只在 `school_time.dart` 出现**（唯一出处）。
void _expectSingleDefinition(String needle) {
  final hits = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.contains('/old/')) continue;
    if (entity.readAsStringSync().contains(needle)) hits.add(path);
  }
  expect(hits, [_timeSrcPath], reason: '「$needle」应只有 school_time.dart 一处');
}
