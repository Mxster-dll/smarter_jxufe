import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

// ─── 构造工具 ───────────────────────────────────────────────────

ClassTime _ct({
  int startWeek = 1,
  int endWeek = 16,
  WeekParity parity = WeekParity.every,
  DayOfWeek day = DayOfWeek.wednesday,
  int startPeriod = 3,
  int endPeriod = 4,
  String classroom = '麦三教3407',
}) => ClassTime(
  startWeek: startWeek,
  endWeek: endWeek,
  weekParity: parity,
  dayOfWeek: day,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  classroom: classroom,
);

ScheduleEntry _entry({
  String courseCode = 'C1',
  String courseName = '高等数学',
  String teacher = '张三',
  String classCode = '001-01',
  List<ClassTime>? classTimes,
}) => ScheduleEntry(
  classCode: classCode,
  className: '主干+',
  courseCode: courseCode,
  courseName: courseName,
  totalHours: 48,
  credits: 3,
  studyNature: '初修',
  teacherCode: 'T1',
  teacherName: teacher,
  selectionStatus: '选中',
  isCrossMajor: false,
  hasTextbook: true,
  classTimes: classTimes ?? [_ct()],
);

Reschedule _rec({
  String id = 'r1',
  RescheduleKind kind = RescheduleKind.move,
  RescheduleScope scope = RescheduleScope.once,
  int week = 10,
  String courseCode = 'C1',
  String courseName = '高等数学',
  String classCode = '001-01',
  String originTeacher = '张三',
  DayOfWeek? originDay = DayOfWeek.wednesday,
  int? originStart = 3,
  int? originEnd = 4,
  String originClassroom = '麦三教3407',
  DayOfWeek? targetDay = DayOfWeek.friday,
  int? targetStart = 6,
  int? targetEnd = 7,
  String targetClassroom = '麦三教3501',
  String? newTeacher,
  String note = '',
}) => Reschedule(
  id: id,
  kind: kind,
  scope: scope,
  week: week,
  courseCode: courseCode,
  courseName: courseName,
  classCode: classCode,
  originTeacher: originTeacher,
  originDay: originDay,
  originStartPeriod: originStart,
  originEndPeriod: originEnd,
  originClassroom: originClassroom,
  targetDay: targetDay,
  targetStartPeriod: targetStart,
  targetEndPeriod: targetEnd,
  targetClassroom: targetClassroom,
  newTeacher: newTeacher,
  note: note,
  createdAt: DateTime(2026, 9, 10),
  updatedAt: DateTime(2026, 9, 10),
);

void main() {
  group('无调课记录时保持原样', () {
    test('周内课节原样输出，标记为 normal', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: const [],
        week: 5,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.normal);
      expect(out.single.classroom, '麦三教3407');
      expect(out.single.dayIndex, 3);
      expect(out.single.isLive, isTrue);
    });

    test('单双周与周次区间过滤仍生效', () {
      final entries = [
        _entry(
          classTimes: [
            _ct(startWeek: 1, endWeek: 8),
            _ct(startWeek: 9, endWeek: 16),
          ],
        ),
      ];
      expect(
        effectiveClasses(entries: entries, reschedules: const [], week: 5),
        hasLength(1),
      );
      expect(
        effectiveClasses(entries: entries, reschedules: const [], week: 12),
        hasLength(1),
      );

      final odd = [
        _entry(classTimes: [_ct(parity: WeekParity.odd)]),
      ];
      expect(
        effectiveClasses(entries: odd, reschedules: const [], week: 4),
        isEmpty,
      );
      expect(
        effectiveClasses(entries: odd, reschedules: const [], week: 5),
        hasLength(1),
      );
    });
  });

  group('单次调课', () {
    test('目标周：原位留「已调走」占位 + 目标位出现「调」课', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [_rec()],
        week: 10,
      );
      expect(out, hasLength(2));

      final away = out.firstWhere((c) => c.mark == EffectiveMark.movedAway);
      expect(away.dayIndex, 3);
      expect(away.classroom, '麦三教3407');
      expect(away.isLive, isFalse, reason: '原位占位不该参与实况窗');

      final moved = out.firstWhere((c) => c.mark == EffectiveMark.moved);
      expect(moved.dayIndex, 5);
      expect(moved.startPeriod, 6);
      expect(moved.classroom, '麦三教3501');
      expect(moved.isRescheduled, isTrue);
      expect(moved.isLive, isTrue);
    });

    test('非目标周不受影响', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [_rec()],
        week: 9,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.normal);
      expect(out.single.classroom, '麦三教3407');
    });

    test('调课记录只落在原课真实上课的那一周', () {
      // 单周课（1-16 周(单)）
      final oddCourse = [
        _entry(classTimes: [_ct(parity: WeekParity.odd)]),
      ];
      // 第 10 周是双周，这门课本来就不上 → 记录不该凭空造出一节课
      expect(
        effectiveClasses(
          entries: oddCourse,
          reschedules: [_rec(week: 10)],
          week: 10,
        ),
        isEmpty,
      );

      // 第 11 周（单周）：调课生效，且生效后的周次区间收成「就这一周」
      final out = effectiveClasses(
        entries: oddCourse,
        reschedules: [_rec(week: 11)],
        week: 11,
      );
      final moved = out.firstWhere((c) => c.mark == EffectiveMark.moved);
      expect(moved.classTime.startWeek, 11);
      expect(moved.classTime.endWeek, 11);
      expect(moved.classTime.weekParity, WeekParity.every);
      expect(moved.dayIndex, 5);
    });

    test('未填目标教室时沿用原教室', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [_rec(targetClassroom: '')],
        week: 10,
      );
      final moved = out.firstWhere((c) => c.mark == EffectiveMark.moved);
      expect(moved.classroom, '麦三教3407');
    });

    test('改教师写入 teacherOverride', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [_rec(newTeacher: '李四')],
        week: 10,
      );
      final moved = out.firstWhere((c) => c.mark == EffectiveMark.moved);
      expect(moved.teacherName, '李四');
      expect(out.firstWhere((c) => c.mark == EffectiveMark.movedAway).teacherName, '张三');
    });
  });

  group('长期调课', () {
    final rec = _rec(scope: RescheduleScope.recurring, week: 10);

    test('生效周之前原样，之后都移动', () {
      final before = effectiveClasses(
        entries: [_entry()],
        reschedules: [rec],
        week: 9,
      );
      expect(before.single.mark, EffectiveMark.normal);

      for (final w in [10, 11, 16]) {
        final out = effectiveClasses(
          entries: [_entry()],
          reschedules: [rec],
          week: w,
        );
        final moved = out.firstWhere((c) => c.mark == EffectiveMark.moved);
        expect(moved.dayIndex, 5);
        expect(moved.classTime.startWeek, 10, reason: '周次区间应从生效周接上');
        expect(moved.classTime.endWeek, 16);
      }
    });

    test('超出原周次区间的周不出现', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [rec],
        week: 17,
      );
      expect(out, isEmpty);
    });
  });

  group('停课', () {
    test('留占位、不参与实况窗', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [
          _rec(kind: RescheduleKind.cancel, targetDay: null, targetStart: null, targetEnd: null),
        ],
        week: 10,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.cancelled);
      expect(out.single.isLive, isFalse);
      expect(out.single.dayIndex, 3, reason: '停课占位留在原时段');
    });

    test('停课与调课同时命中时以停课为准', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [
          _rec(id: 'a', kind: RescheduleKind.move),
          _rec(id: 'b', kind: RescheduleKind.cancel),
        ],
        week: 10,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.cancelled);
    });
  });

  group('补课', () {
    final rec = _rec(
      kind: RescheduleKind.extra,
      originDay: null,
      originStart: null,
      originEnd: null,
      targetDay: DayOfWeek.saturday,
      targetStart: 1,
      targetEnd: 2,
      targetClassroom: '麦三教3201',
    );

    test('只在指定周出现，且带「补」标记', () {
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [rec],
        week: 10,
      );
      expect(out, hasLength(2));
      final extra = out.firstWhere((c) => c.isExtra);
      expect(extra.dayIndex, 6);
      expect(extra.courseName, '高等数学');
      expect(extra.classroom, '麦三教3201');
      expect(extra.isLive, isTrue);

      expect(
        effectiveClasses(entries: [_entry()], reschedules: [rec], week: 11),
        hasLength(1),
      );
    });

    test('未填教室时显示「教室待定」', () {
      final out = effectiveClasses(
        entries: const [],
        reschedules: [_rec(kind: RescheduleKind.extra, originDay: null, originStart: null, originEnd: null, targetClassroom: '')],
        week: 10,
      );
      expect(out.single.classroom, '教室待定');
    });
  });

  group('整学期模板视图（week = null）', () {
    test('忽略单次调课、应用长期调课', () {
      final once = _rec();
      final out = effectiveClasses(
        entries: [_entry()],
        reschedules: [once],
        week: null,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.normal);

      final recurring = _rec(scope: RescheduleScope.recurring, week: 10);
      final out2 = effectiveClasses(
        entries: [_entry()],
        reschedules: [recurring],
        week: null,
      );
      expect(out2.where((c) => c.mark == EffectiveMark.moved), hasLength(1));
    });

    test('单次调课在原课位累计角标数', () {
      final marks = onceMarksBySlot([
        _rec(id: 'a'),
        _rec(id: 'b'),
        _rec(id: 'c', scope: RescheduleScope.recurring),
        _rec(id: 'd', kind: RescheduleKind.extra, originDay: null, originStart: null, originEnd: null),
      ]);
      final key = classSlotKey('C1', _ct());
      expect(marks[key], 2);
    });
  });

  group('匹配容错', () {
    test('课程代码忽略大小写与空白', () {
      final out = effectiveClasses(
        entries: [_entry(courseCode: 'c1')],
        reschedules: [_rec(courseCode: ' C1 ')],
        week: 10,
      );
      expect(out.where((c) => c.isRescheduled), hasLength(1));
    });

    test('上课班代码只在两边都非空时才比对', () {
      final out = effectiveClasses(
        entries: [_entry(classCode: '')],
        reschedules: [_rec(classCode: '999-99')],
        week: 10,
      );
      expect(out.where((c) => c.isRescheduled), hasLength(1));

      final out2 = effectiveClasses(
        entries: [_entry(classCode: '002-02')],
        reschedules: [_rec(classCode: '999-99')],
        week: 10,
      );
      expect(out2.where((c) => c.isRescheduled), isEmpty);
    });

    test('不同星期的同名课不会被误伤', () {
      final out = effectiveClasses(
        entries: [
          _entry(classTimes: [_ct(day: DayOfWeek.monday)]),
        ],
        reschedules: [_rec()],
        week: 10,
      );
      expect(out, hasLength(1));
      expect(out.single.mark, EffectiveMark.normal);
    });
  });

  group('类型与 JSON 容错', () {
    test('往返序列化保持一致', () {
      final r = _rec(newTeacher: '李四', note: '老师出差');
      final back = Reschedule.fromJson(r.toJson())!;
      expect(back.id, r.id);
      expect(back.kind, r.kind);
      expect(back.scope, r.scope);
      expect(back.week, r.week);
      expect(back.targetDay, DayOfWeek.friday);
      expect(back.newTeacher, '李四');
      expect(back.note, '老师出差');
      expect(back.matchesOriginSlot(_ct()), isTrue);
    });

    test('坏 JSON 返回 null 而不是抛异常', () {
      expect(Reschedule.fromJson(null), isNull);
      expect(Reschedule.fromJson({'id': 'x'}), isNull);
      expect(Reschedule.fromJson({'courseName': '高数'}), isNull);
      expect(Reschedule.fromJson('nope'), isNull);
    });

    test('范围与类型描述', () {
      expect(_rec().weekText, '第 10 周');
      expect(
        _rec(scope: RescheduleScope.recurring).weekText,
        '第 10 周起',
      );
      expect(
        _rec(kind: RescheduleKind.cancel, targetDay: null, targetStart: null, targetEnd: null).summary,
        contains('停课'),
      );
    });
  });
}
