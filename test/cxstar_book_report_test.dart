/// 畅想之星逐书阅读报告解析守卫（用户 2026-09-15 提问：「阅读记录里面能不能看到
/// 每本书的完成时间和总阅读时长（秒）」）。
///
/// 实测口径（个人会话，`GET /api/books/{bookId}/readreport`，2026-09-15）：
/// - 字段全部是**字符串数字**（`readMinutes:"53"`、`readDays:"2"`、`readNo:"14"`）；
/// - `finishReadTime` 仅**已读完**的书有值（`"2026年09月09日"`），未读完为 `null`；
/// - **平台只有分钟精度**（`/api/books/{id}/readtime` / `/api/user/readtime/{id}` 均 404），
///   所以「时长（秒）」只能给到分钟。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_book_report.dart';

void main() {
  group('CxstarBookReport.fromJson', () {
    test('已读完的真实响应（字符串数字 + 完成时间）', () {
      final report = CxstarBookReport.fromJson(const {
        'userId': 'AUUs3UHeJeAwzEu8i9AD',
        'userName': '某同学',
        'pinstRuid': '1cdceffd0000020bce',
        'bookRuid': '211de93d000001XXXX',
        'title': '互联网供应链金融',
        'startReadTime': '2026年09月14日',
        'endReadTime': '2026年09月15日',
        'readMinutes': '53',
        'readDays': '2',
        'readNo': '14',
        'finishReadTime': '2026年09月09日',
        'finishReadNo': '10',
        'longestTime': '52',
        'longestDate': '2026年09月14日',
        'noteCount': '0',
        'isFinish': true,
      });

      expect(report.bookId, '211de93d000001XXXX');
      expect(report.title, '互联网供应链金融');
      expect(report.readMinutes, 53);
      expect(report.readDays, 2);
      expect(report.readNo, 14);
      expect(report.finishReadNo, 10);
      expect(report.longestMinutes, 52);
      expect(report.finished, isTrue);
      expect(report.finishText, '完成于 2026年09月09日');
      expect(report.activityText, '阅读 2 天 · 14 次');
    });

    test('未读完：finishReadTime 为 null → finished 假、finishText 空', () {
      final report = CxstarBookReport.fromJson(const {
        'bookRuid': '211de93d000001XXXX',
        'title': '互联网供应链金融',
        'readMinutes': '53',
        'readDays': '2',
        'readNo': '14',
        'finishReadTime': null,
        'finishReadNo': null,
        'isFinish': false,
      });

      expect(report.finished, isFalse);
      expect(report.finishText, isNull);
      expect(report.readMinutes, 53);
    });

    test('finishReadTime 有值但 isFinish 缺失时，仍按已完成处理', () {
      final report = CxstarBookReport.fromJson(const {
        'finishReadTime': '2026年07月02日',
        'readMinutes': '46',
      });

      expect(report.finished, isTrue);
      expect(report.finishText, '完成于 2026年07月02日');
      expect(report.readDays, 0);
      expect(report.activityText, '', reason: '天数/次数为 0 时不给空词条');
    });

    test('脏值容错：数字给字符串/浮点/空都退化成 0，不抛', () {
      final report = CxstarBookReport.fromJson(const {
        'readMinutes': 'abc',
        'readDays': 1.0,
        'readNo': '',
        'longestTime': null,
        'bookId': 'fallback-key',
      });

      expect(report.readMinutes, 0);
      expect(report.readDays, 1);
      expect(report.readNo, 0);
      expect(report.longestMinutes, 0);
      expect(report.bookId, 'fallback-key', reason: 'bookRuid 缺失时回退 bookId');
    });
  });

  test('activityText 只列非零项', () {
    expect(const CxstarBookReport(readDays: 3, readNo: 9).activityText, '阅读 3 天 · 9 次');
    expect(const CxstarBookReport(readNo: 9).activityText, '9 次');
    expect(const CxstarBookReport(readDays: 3).activityText, '阅读 3 天');
    expect(const CxstarBookReport().activityText, '');
  });
}
