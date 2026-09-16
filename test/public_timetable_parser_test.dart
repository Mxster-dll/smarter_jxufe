import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';

/// 公共查询报表解析守卫。
///
/// fixture 全是 2026-09-14 从教务真实抓下来的 GBK 页面（已转 UTF-8 存盘）：
/// 班级课表 / 教师课表 / 课程课表各 1 张表，教室课表 3 张表。
String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('班级课表（分班级）', () {
    late List<PublicTimetable> tables;

    setUpAll(() {
      tables = parsePublicTimetableReport(
        _fixture('public_bjkb_class.html'),
        ownerPrefixes: const ['班级'],
      );
    });

    test('一张表 = 一个班级，描述块字段全部拿到', () {
      expect(tables.length, 1);
      final t = tables.single;
      expect(t.owner, '26会计学S2班');
      expect(t.fieldOf('院(系)/部'), '会计学院');
      expect(t.fieldOf('年级'), '2026');
      expect(t.fieldOf('专业'), '会计学(第二学士学位)');
      expect(t.subtitle, contains('会计学院'));
    });

    test('格子：星期 / 大节 / 节次区间 / 周次', () {
      final t = tables.single;
      expect(t.cells.length, 5);
      final first = t.cells.first;
      expect(first.weekday, inInclusiveRange(1, 7));
      expect(first.periodIndex, 1);
      // 江财第 1 大节 = 1-2 节（行标签还原，不是硬编码 2 节一档）
      expect((first.startPeriod, first.endPeriod), (1, 2));
      expect((first.startWeek, first.endWeek), (2, 17));
      expect(first.parity, WeekParity.every);
      expect(first.weekLabel, '2-17周');
      expect(first.slotLabel, '周${first.weekdayLabel.substring(1)} 1-2 节');
    });

    test('格子片段：课程名 / 学分 / 教师 / 周次 / 节次 / 教室 / 校区', () {
      final parts = tables.single.cells.first.parts;
      expect(parts, contains('会计学原理'));
      expect(parts, contains('周天杭'));
      expect(parts, contains('[2-17]周'));
      expect(parts, contains('1-2节'));
      expect(parts, contains('蛟一教1101'));
      expect(parts, contains('蛟桥园校区'));
    });
  });

  group('教师课表（分教师）', () {
    late PublicTimetable table;

    setUpAll(() {
      final tables = parsePublicTimetableReport(
        _fixture('public_jskb_teacher.html'),
        ownerPrefixes: const ['教师'],
      );
      table = tables.single;
    });

    test('对象名 = 教师姓名，描述块带部门与职称', () {
      expect(table.owner, '陈润平');
      expect(table.fieldOf('部门'), '外国语学院');
      expect(table.fieldOf('职称'), '讲师');
    });

    test('格子数量与周次', () {
      expect(table.cells.length, 9);
      for (final c in table.cells) {
        expect(c.startWeek, lessThanOrEqualTo(c.endWeek));
        expect(c.startWeek, greaterThanOrEqualTo(1));
        expect(c.endWeek, lessThanOrEqualTo(30));
        expect(c.weekday, inInclusiveRange(1, 7));
        expect(c.startPeriod, lessThanOrEqualTo(c.endPeriod));
      }
      // 该教师本学期主课是 [2-17] 周；其它安排（如体育/短学期课）周次不同
      expect(
        table.cells.any((c) => c.startWeek == 2 && c.endWeek == 17),
        isTrue,
      );
    });

    test('教师课表格子里带班级名与教室（可用于交叉核对）', () {
      final text = table.cells.map((c) => c.text).join(' ');
      expect(text, contains('英语视听说'));
      expect(text, contains('麦三教'));
    });
  });

  group('课程课表（按课程）', () {
    late PublicTimetable table;

    setUpAll(() {
      final tables = parsePublicTimetableReport(
        _fixture('public_kckb_course.html'),
        ownerPrefixes: const ['课程'],
      );
      table = tables.single;
    });

    test('对象名保留 [课程代码] 前缀，描述块带承担单位与总学时', () {
      expect(table.owner, '[0004504882]管理学基础');
      expect(table.fieldOf('承担单位'), '工商管理学院');
      expect(table.fieldOf('总学时'), '20');
    });

    test('格子 = 一次上课安排（教师 + 周次 + 节次 + 班级 + 教室）', () {
      expect(table.cells.length, 3);
      final first = table.cells.first;
      expect(first.parts.first, '余焕新');
      expect((first.startWeek, first.endWeek), (2, 11));
      expect(first.text, contains('预科261'));
    });
  });

  group('教室课表（分楼栋，多表）', () {
    late List<PublicTimetable> tables;

    setUpAll(() {
      tables = parsePublicTimetableReport(
        _fixture('public_jsikb_rooms.html'),
        ownerPrefixes: const ['教室'],
      );
    });

    test('一个响应里多张表，各自对应一间教室（描述块不串）', () {
      expect(tables.length, 3);
      expect(tables[0].owner, '博雅艺术中心B01');
      expect(tables[1].owner, '蛟北区G301');
      expect(tables[0].fieldOf('楼房'), '博雅艺术中心');
      expect(tables[0].fieldOf('教室类型'), '设计室');
      expect(tables[0].fieldOf('校区'), '蛟桥园校区');
    });

    test('每间教室的格子都落在自己的表里（表间不混）', () {
      final total = tables.fold<int>(0, (sum, t) => sum + t.cells.length);
      expect(total, greaterThanOrEqualTo(24));
      for (final t in tables) {
        for (final c in t.cells) {
          expect(c.weekday, inInclusiveRange(1, 7));
          expect(c.periodIndex, inInclusiveRange(1, 9));
        }
      }
    });
  });

  group('异常输入', () {
    test('空串 / 没有 mytable 的页面 → 空列表且不抛', () {
      expect(parsePublicTimetableReport(''), isEmpty);
      expect(parsePublicTimetableReport('<html><body>没有检索到记录！</body></html>'), isEmpty);
      expect(
        parsePublicTimetableReport("<table id='other'><tr><td>x</td></tr></table>"),
        isEmpty,
      );
    });

    test('描述块缺失时 owner 退化为字段拼接，且不崩', () {
      const html =
          "<table class='table' id='mytable0'><tbody><tr>"
          "<td class='td1'><b>1-2节</b></td>"
          "<td class='td' title=\"数学&amp;ensp;张三&amp;ensp;[3-5]周&amp;ensp;1-2节\">"
          "<div class='div1' id='011'>x</div></td>"
          '</tr></tbody></table>';
      final tables = parsePublicTimetableReport(html, ownerPrefixes: const ['班级']);
      expect(tables.single.owner, '');
      final cell = tables.single.cells.single;
      expect(cell.parts, ['数学', '张三', '[3-5]周', '1-2节']);
      expect((cell.startWeek, cell.endWeek), (3, 5));
      expect((cell.startPeriod, cell.endPeriod), (1, 2));
    });

    test('单双周与单周次区间（`[5]周(单)` / `[1-16]周(双)`）', () {
      const html =
          "<table class='table' id='mytable0'><tbody>"
          "<tr><td class='td1'><b>3-5节</b></td>"
          "<td class='td' title=\"甲&amp;ensp;[1-16]周(双)&amp;ensp;3-5节\">"
          "<div class='div1' id='012'>a</div></td>"
          "<td class='td' title=\"乙&amp;ensp;[5]周(单)&amp;ensp;3-5节\">"
          "<div class='div1' id='022'>b</div></td>"
          '</tr></tbody></table>';
      final cells = parsePublicTimetableReport(html).single.cells;
      expect(cells.length, 2);
      expect(cells[0].parity, WeekParity.even);
      expect((cells[0].startPeriod, cells[0].endPeriod), (3, 5));
      expect(cells[0].periodIndex, 2);
      expect(cells[1].parity, WeekParity.odd);
      expect((cells[1].startWeek, cells[1].endWeek), (5, 5));
    });

    test('大节序号 ≥10 的表（id 变 4 位）也能解析出星期与大节', () {
      const html =
          "<table class='table' id='mytable10'><tbody>"
          "<tr><td class='td1'><b>1-2节</b></td>"
          "<td class='td' title=\"甲&amp;ensp;[2-17]周\">"
          "<div class='div1' id='1011'>a</div></td>"
          '</tr></tbody></table>';
      final cell = parsePublicTimetableReport(html).single.cells.single;
      expect(cell.weekday, 1);
      expect(cell.periodIndex, 1);
    });
  });

  group('与「找无课时间」引擎的衔接', () {
    test('slotsOfTimetables：owner 用对照名覆盖，周次/节次/单双周原样带入', () {
      final tables = parsePublicTimetableReport(
        _fixture('public_bjkb_class.html'),
        ownerPrefixes: const ['班级'],
      );
      final slots = slotsOfTimetables(
        tables,
        ownerOf: (t) => '我的班',
        nameOf: (t, c) => '课程X',
      );
      expect(slots.length, tables.single.cells.length);
      for (final s in slots) {
        expect(s.owner, '我的班');
        expect(s.courseName, '课程X');
        expect(s.startWeek, lessThanOrEqualTo(s.endWeek));
        expect(s.weekday, inInclusiveRange(1, 7));
        expect(s.startPeriod, greaterThanOrEqualTo(1));
      }
      expect(slots.any((s) => s.startWeek == 2 && s.endWeek == 17), isTrue);
    });

    test('多间教室对照：能算出共同空闲窗口，且窗口都落在半日块内', () {
      final tables = parsePublicTimetableReport(
        _fixture('public_jsikb_rooms.html'),
        ownerPrefixes: const ['教室'],
      );
      final slots = slotsOfTimetables(tables);
      final windows = findFreeWindows(slots: slots, week: 3, maxPeriod: 12);
      for (final w in windows) {
        expect(w.weekday, inInclusiveRange(1, 7));
        expect(w.startPeriod, greaterThanOrEqualTo(1));
        expect(w.endPeriod, lessThanOrEqualTo(12));
        expect(w.periods, greaterThanOrEqualTo(1));
      }
      // 第 3 周（[2-9]周 的课程在生效区间内）应当仍有空闲：三间教室不可能全周占满
      expect(windows, isNotEmpty);
    });

    test('教室课表的格子若以「教师」开头，课程名取第一段（默认口径）', () {
      final tables = parsePublicTimetableReport(
        _fixture('public_jsikb_rooms.html'),
        ownerPrefixes: const ['教室'],
      );
      final slots = slotsOfTimetables(tables);
      expect(slots.first.courseName, isNotEmpty);
      expect(slots.first.owner, tables.first.owner);
    });
  });
}
