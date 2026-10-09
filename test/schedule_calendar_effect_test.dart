/// 校历事件 → 课表效应（假期 / 补课）的守卫测试（用户 2026-10-08 需求）。
///
/// 用户原话：「关于课表的显示，应该响应校历里的事件。具体为如果是假期就不显示课程
/// （除非是移课移到那天），然后还有诸如 xx 天补 xx 周 xx 天课程，这样的课表也要动态
/// 响应。」
///
/// 本文件覆盖**纯领域层**：补课原文解析、假期名（首页无课原因）、效应索引
/// （判假复用 `CalendarMarkIndex`）、以及「日期 → 教学周」。
/// 课表列的实际取课见 `test/schedule_board_test.dart`。
///
/// ⚠ 用的是**内置离线快照**（`wxcalOfflineToDomain()`，261 = 2026-2027 第一学期）——
/// 官方原文里那句「2026-10-10 补第4周周五的课」就是本需求的真实样本：
/// 第 4 周周五 = 10-02，正在国庆假期（10-01~10-07）内，自洽 ✅。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 261（2026-2027 第一学期）的效应索引 —— 全部用例共用（纯内存，无 IO）。
final CalendarDayEffectIndex _idx = CalendarDayEffectIndex.build(
  terms: wxcalOfflineToDomain(),
);

/// 造一个只有一条事件的学期（覆盖人工边界）。
CalendarDayEffectIndex _idxWith({
  required String text,
  required DateTime from,
  DateTime? to,
  String? category,
}) => CalendarDayEffectIndex.build(
  terms: [
    WxSemesterArrangement(
      id: 1,
      term: '261',
      start: DateTime(2026, 9, 7),
      end: DateTime(2027, 1, 16),
      style: WxArrangementStyle.table,
      events: [
        WxCalEvent(
          from: from,
          to: to ?? from,
          text: text,
          category: category,
        ),
      ],
    ),
  ],
);

void main() {
  group('补课原文 → 「补哪一周的星期几」', () {
    test('带周次（官方主流写法）', () {
      expect(
        parseMakeupTarget('补第4周周五的课'),
        (week: 4, weekday: 5),
        reason: '261 的 2026-10-10 原文',
      );
      expect(parseMakeupTarget('补第10周周一的课程。'), (week: 10, weekday: 1));
      expect(parseMakeupTarget('补第 12 周 周 三 的课'), (week: 12, weekday: 3));
    });

    test('不带周次 → 同周（调休补课总是补本周被假期冲掉的那天）', () {
      expect(parseMakeupTarget('4月8日补周五的课'), (week: null, weekday: 5));
      expect(parseMakeupTarget('9月29日补周四的课'), (week: null, weekday: 4));
    });

    test('「星期 / 礼拜 / 天」都认；认不出的返回 null', () {
      expect(parseMakeupTarget('补星期二的课'), (week: null, weekday: 2));
      expect(parseMakeupTarget('补第3周礼拜日的课'), (week: 3, weekday: 7));
      expect(parseMakeupTarget('补第3周星期天的课'), (week: 3, weekday: 7));
      // 「补（缓）考」「因…自行安排补课」不是调休补课，不许误判。
      expect(parseMakeupTarget('本科生补（缓）考。'), isNull);
      expect(parseMakeupTarget('因法定节假日放假所差课程由教师自行安排补课。'), isNull);
      expect(parseMakeupTarget('国庆节放假'), isNull);
    });
  });

  group('假期名（首页「今天为什么没课」的文案）', () {
    test('法定节假日 → 「XX假期」', () {
      expect(holidayNameOf('国庆节放假'), '国庆节假期');
      expect(holidayNameOf('中秋节放假'), '中秋节假期');
      expect(holidayNameOf('元旦放假（以学校放假安排通知为准）'), '元旦假期');
      expect(holidayNameOf('劳动节放假。'), '劳动节假期');
    });

    test('寒 / 暑假整段保留原名', () {
      expect(holidayNameOf('寒假开始'), '寒假');
      expect(holidayNameOf('暑假开始。'), '暑假');
      expect(holidayNameOf('寒假（假期）'), '寒假');
    });

    test('兜底：认不出给「假期」，不把原文整句印上屏', () {
      expect(holidayNameOf('学期外假期'), '假期');
      expect(holidayNameOf(''), '假期');
    });
  });

  group('效应索引（真实快照 261）', () {
    test('2026-10-10 是补课日，且指向第 4 周周五', () {
      final e = _idx.effectOf(DateTime(2026, 10, 10));
      expect(e.kind, CalendarDayEffectKind.makeup);
      expect(e.isMakeup, isTrue);
      expect(e.sourceWeek, 4);
      expect(e.sourceWeekday, 5);
      expect(e.name, '补第4周周五的课');
      // 表头小字去掉「的课」尾巴；提示语说清「按谁上课」。
      expect(e.badge, '补第4周周五');
      expect(e.sourceText, '按第 4 周周五的课表');
    });

    test('国庆 / 中秋 / 元旦都是假期，且带得出假期名', () {
      final national = _idx.effectOf(DateTime(2026, 10, 1));
      expect(national.kind, CalendarDayEffectKind.holiday);
      expect(national.name, '国庆节假期');
      expect(national.isBreak, isFalse, reason: '法定节假日不是寒暑假整段');

      expect(
        _idx.effectOf(DateTime(2026, 10, 7)).kind,
        CalendarDayEffectKind.holiday,
        reason: '假期是闭区间，最后一天照样算',
      );
      expect(_idx.effectOf(DateTime(2026, 10, 8)).kind,
          CalendarDayEffectKind.normal, reason: '假期结束的次日就是普通日');

      expect(_idx.effectOf(DateTime(2026, 9, 26)).name, '中秋节假期');
      expect(_idx.effectOf(DateTime(2027, 1, 1)).name, '元旦假期');
    });

    test('寒假整段（从「寒假开始」延伸到下学期前）标为假期 + isBreak', () {
      final e = _idx.effectOf(DateTime(2027, 1, 20));
      expect(e.kind, CalendarDayEffectKind.holiday);
      expect(e.name, '寒假');
      expect(e.isBreak, isTrue);
    });

    test('普通教学日：无效应、无小字，但事件仍然带得出来', () {
      final e = _idx.effectOf(DateTime(2026, 10, 8));
      expect(e.kind, CalendarDayEffectKind.normal);
      expect(e.badge, isEmpty);
      expect(e.events, isEmpty);
      // 11-07 期中考试：不打「假/班」但事件要能被首页读到。
      final exam = _idx.effectOf(DateTime(2026, 11, 7));
      expect(exam.kind, CalendarDayEffectKind.normal);
      expect(exam.events.map((e) => e.text), contains('期中考试'));
    });

    test('「日期 → 教学周」：第 1 周 = 学期起始周（261 → 09-07 那一周）', () {
      expect(_idx.weekOf(DateTime(2026, 9, 7)), 1);
      expect(_idx.weekOf(DateTime(2026, 9, 13)), 1, reason: '周日仍属第 1 周');
      expect(_idx.weekOf(DateTime(2026, 9, 14)), 2);
      expect(_idx.weekOf(DateTime(2026, 10, 10)), 5, reason: '补课日自己落在第 5 周');
      expect(_idx.weekOf(DateTime(2026, 10, 2)), 4, reason: '被补的那天在第 4 周');
      expect(_idx.weekOf(DateTime(2026, 8, 20)), isNull, reason: '不属于任何已公布学段');
    });

    test('空索引：一切日期都是普通日、查不到教学周（不抛异常）', () {
      final empty = CalendarDayEffectIndex.empty();
      final e = empty.effectOf(DateTime(2026, 10, 1));
      expect(e.kind, CalendarDayEffectKind.normal);
      expect(empty.weekOf(DateTime(2026, 10, 1)), isNull);
      expect(empty.effectOf(DateTime(2026, 10, 10)).badge, isEmpty);
    });
  });

  group('人工边界（合成事件）', () {
    test('不带周次的补课：sourceWeek 留 null（由课表按「同周」解释）', () {
      final idx = _idxWith(text: '补周五的课', from: DateTime(2026, 9, 27));
      final e = idx.effectOf(DateTime(2026, 9, 27));
      expect(e.kind, CalendarDayEffectKind.makeup);
      expect(e.sourceWeek, isNull);
      expect(e.sourceWeekday, 5);
      expect(e.badge, '补周五');
    });

    test('补课原文里的「第N周」超出学期范围也照收（照原文说话）', () {
      final idx = _idxWith(text: '补第18周周一的课', from: DateTime(2027, 1, 4));
      final e = idx.effectOf(DateTime(2027, 1, 4));
      expect(e.sourceWeek, 18);
      expect(e.sourceWeekday, 1);
    });
  });

  group('「今天为什么没课」文案', () {
    test('假期优先于周末（10-03 既是周六又在国庆里）', () {
      final holiday = _idx.effectOf(DateTime(2026, 10, 3));
      expect(
        noClassReasonText(effect: holiday, isWeekend: true),
        '国庆节假期',
        reason: '学生要知道的是「放假」，不是「周末」',
      );
    });

    test('普通周末 → 周末；补课日没课不算假期；说不出原因 → null', () {
      final saturday = _idx.effectOf(DateTime(2026, 10, 17));
      expect(noClassReasonText(effect: saturday, isWeekend: true), '周末');
      expect(noClassReasonText(effect: saturday, isWeekend: false), isNull);

      final makeup = _idx.effectOf(DateTime(2026, 10, 10));
      expect(noClassReasonText(effect: makeup, isWeekend: true), isNull);

      expect(
        noClassReasonText(effect: saturday, isWeekend: false, beforeTermStart: true),
        '还没开学',
      );
    });

    test('没有校历可用时：只按周末判（不编假期名）', () {
      expect(noClassReasonText(isWeekend: true), '周末');
      expect(noClassReasonText(isWeekend: false), isNull);
    });
  });
}
