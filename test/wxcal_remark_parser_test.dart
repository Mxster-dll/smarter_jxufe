import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/wxcal_remark_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('table 版（2026 秋 term261）', () {
    final a = parseWxRemark(
      id: 19,
      term: '261',
      startDate: '2026-09-07',
      endDate: '2027-01-16',
      remark: _fixture('wxcal_rem_261.html'),
    );

    test('样式为 table 且事件数正确', () {
      expect(a.style, WxArrangementStyle.table);
      expect(a.events, hasLength(30));
    });

    test('分节类别正确', () {
      final cats = a.events.map((e) => e.category).toSet();
      expect(cats, contains('教职员工'));
      expect(cats, contains('本科生'));
      expect(cats, contains('研究生'));
    });

    test('教职工首事件 = 9月2日 教职工上班', () {
      final first = a.events.firstWhere((e) => e.category == '教职员工');
      expect(first.from, DateTime(2026, 9, 2));
      expect(first.text, contains('上班'));
    });

    test('本科生活动日期与区间正确', () {
      final events = a.events.where((e) => e.category == '本科生');
      final hasMidAutumn = events.any((e) =>
          e.from == DateTime(2026, 9, 25) &&
          e.to == DateTime(2026, 9, 27) &&
          e.text.contains('中秋'));
      final hasMilitary = events.any((e) =>
          e.from == DateTime(2026, 9, 7) &&
          e.to == DateTime(2026, 9, 21) &&
          e.text.contains('军训'));
      final hasSports = events.any((e) =>
          e.from == DateTime(2026, 10, 29) &&
          e.to == DateTime(2026, 10, 31) &&
          e.text.contains('运动会'));
      final hasExam = events.any((e) =>
          e.from == DateTime(2026, 11, 7) &&
          e.to == DateTime(2026, 11, 8) &&
          e.text.contains('期中'));
      expect(hasMidAutumn, isTrue);
      expect(hasMilitary, isTrue);
      expect(hasSports, isTrue);
      expect(hasExam, isTrue);
    });

    test('跨年事件落在次年', () {
      final holiday = a.events
          .firstWhere((e) => e.category == '本科生' && e.text.contains('寒假开始'));
      expect(holiday.from, DateTime(2027, 1, 16));
    });

    test('rangeText 展示格式', () {
      final e = a.events.firstWhere((e) => e.text.contains('中秋节放假'));
      expect(e.rangeText, '9月25日-27日');
      final single = a.events.firstWhere((e) => e.text.contains('教职工上班'));
      expect(single.rangeText, '9月2日');
    });
  });

  group('行式版（2026 春 term252）', () {
    final a = parseWxRemark(
      id: 18,
      term: '252',
      startDate: '2026-03-02',
      endDate: '2026-07-05',
      remark: _fixture('wxcal_rem_252.html'),
    );

    test('样式为 lines 且 16 条事件', () {
      expect(a.style, WxArrangementStyle.lines);
      expect(a.events, hasLength(16));
    });

    test('清明节放假 4月4日-6日', () {
      final e = a.events.firstWhere((x) => x.text.contains('清明节'));
      expect(e.from, DateTime(2026, 4, 4));
      expect(e.to, DateTime(2026, 4, 6));
    });

    test('跨月区间 6月29日-7月5日 期末考试', () {
      final e = a.events.firstWhere((x) => x.text.contains('期末校考'));
      expect(e.from, DateTime(2026, 6, 29));
      expect(e.to, DateTime(2026, 7, 5));
    });

    test('暑假开始 7月6日', () {
      final e = a.events.firstWhere((x) => x.text.contains('暑假开始'));
      expect(e.from, DateTime(2026, 7, 6));
    });
  });

  group('段落式（2025 秋 term251）', () {
    final a = parseWxRemark(
      id: 17,
      term: '251',
      startDate: '2025-09-01',
      endDate: '2026-01-14',
      remark: _fixture('wxcal_rem_251.html'),
    );

    test('保留原文 notes，不拆事件', () {
      expect(a.style, WxArrangementStyle.paragraph);
      expect(a.events, isEmpty);
      expect(a.notes, isNotEmpty);
      expect(a.notes.join(''), contains('教职工'));
    });
  });

  group('term 映射', () {
    test('wxTermCode 与反向', () {
      expect(wxTermCode(2026, 0), '261');
      expect(wxTermCode(2025, 1), '252');
      expect(wxTermCode(2017, 0), '171');
    });
    test('xn/xq getter', () {
      final t = WxSemesterArrangement(
          id: 19,
          term: '261',
          start: DateTime(2026, 9, 7),
          end: DateTime(2027, 1, 16),
          style: WxArrangementStyle.empty);
      expect(t.xn, 2026);
      expect(t.xq, 0);
    });
  });
}
