import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/read_credit/data/anti_corruption/read_credit_parser.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

/// 读取脱敏后的真实抓取 fixture。
String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('阅读学分类目口径', () {
    test('五项的标签 / 明细路径 / 是否有明细', () {
      expect(ReadCreditKind.values.length, 5);
      expect(ReadCreditKind.ordinary.label, '普通阅读');
      expect(ReadCreditKind.ordinary.detailPath, '/Web/Read/Index/pt');
      expect(ReadCreditKind.classic.detailPath, '/Web/Read/Index/jd');
      expect(ReadCreditKind.libraryEdu.detailPath, '/Web/Read/Index/rg');
      expect(ReadCreditKind.infoLiteracy.detailPath, '/Web/Read/Index/xx');
      expect(ReadCreditKind.culture.hasDetail, isFalse);
      expect(ReadCreditKind.ordinary.hasDetail, isTrue);
    });

    test('fromLabel 按中文名回查', () {
      expect(ReadCreditKind.fromLabel('普通阅读'), ReadCreditKind.ordinary);
      expect(ReadCreditKind.fromLabel('蛟湖文化活动'), ReadCreditKind.culture);
      expect(ReadCreditKind.fromLabel('不存在'), isNull);
    });
  });

  group('学分查询页解析', () {
    test('五项状态 + 学分状态 + 计数摘要', () {
      final score = parseReadCreditScore(_fixture('jhread_score.html'));
      expect(score.items.length, 5);
      expect(score.creditText, '未获得学分');
      expect(score.creditGranted, isFalse);
      expect(score.passedCount, 1);

      final ordinary = score.itemOf(ReadCreditKind.ordinary)!;
      expect(ordinary.passed, isFalse);
      expect(ordinary.statusText, '未通过');
      expect(ordinary.updatedAt, '2026年09月03日');
      expect(ordinary.infoRaw, '电子阅读[2] 纸质阅读[0]');
      expect(ordinary.counts.length, 2);
      expect(ordinary.counts[0].label, '电子阅读');
      expect(ordinary.counts[0].value, 2);
      expect(ordinary.counts[1].label, '纸质阅读');
      expect(ordinary.counts[1].value, 0);

      final culture = score.itemOf(ReadCreditKind.culture)!;
      expect(culture.passed, isTrue);
      expect(culture.updatedAt, '2026年04月01日');
      expect(culture.hasInfo, isFalse, reason: '蛟湖文化活动没有 info 行');

      final classic = score.itemOf(ReadCreditKind.classic)!;
      expect(classic.infoRaw, isNull, reason: '平台返回「无信息」时应为 null');
      expect(classic.counts, isEmpty);
    });

    test('学分已获得分支（内联 HTML）', () {
      const html = '''
<div class="title">学分状态：<span class="titleTrue">获得学分</span></div>
''';
      final score = parseReadCreditScore(html);
      expect(score.creditGranted, isTrue);
      expect(score.creditText, '获得学分');
      expect(score.items, isEmpty);
    });

    test('解析计数摘要的容错', () {
      expect(parseReadCreditCounts(null), isEmpty);
      expect(parseReadCreditCounts(''), isEmpty);
      final counts = parseReadCreditCounts('电子阅读【3】纸质阅读[12]');
      expect(counts.length, 2);
      expect(counts[0].value, 3);
      expect(counts[1].label, '纸质阅读');
      expect(counts[1].value, 12);
    });
  });

  group('明细表解析', () {
    test('普通阅读明细：9 列 3 行', () {
      final detail = parseReadCreditDetail(
        _fixture('jhread_detail_pt.html'),
        ReadCreditKind.ordinary,
      );
      expect(detail.headers.length, 9);
      expect(detail.headers.first, '一卡通号');
      expect(detail.headers.contains('已读完图书书名'), isTrue);
      expect(detail.headers.contains('总阅读时长(秒)'), isTrue);
      expect(detail.rows.length, 3);
      expect(detail.rows.every((r) => r.length == 9), isTrue);
      expect(detail.isEmpty, isFalse);
    });

    test('按列名取值与求和', () {
      final detail = parseReadCreditDetail(
        _fixture('jhread_detail_pt.html'),
        ReadCreditKind.ordinary,
      );
      final books = detail.columnValues('书名').where((v) => v.isNotEmpty);
      expect(books.length, 2, reason: '纸质借阅行没有书名');
      expect(detail.sumColumn('时长'), 14402, reason: '7201 + 7201 + 0');
      expect(detail.indexOfHeader('所属厂商'), 8);
      expect(detail.columnValues('不存在的列'), isEmpty);
    });

    test('空明细页：表头在但无数据行', () {
      final rg = parseReadCreditDetail(
        _fixture('jhread_detail_rg_empty.html'),
        ReadCreditKind.libraryEdu,
      );
      expect(rg.headers.contains('闯关结束时间'), isTrue);
      expect(rg.headers.contains('是否通过'), isTrue);
      expect(rg.isEmpty, isTrue);

      final xx = parseReadCreditDetail(
        _fixture('jhread_detail_xx_empty.html'),
        ReadCreditKind.infoLiteracy,
      );
      expect(xx.headers.contains('学习视频数量'), isTrue);
      expect(xx.isEmpty, isTrue);
    });
  });

  group('单元格展示换算', () {
    test('时长列秒 → 小时', () {
      expect(
        readCreditCellText('总阅读时长(秒)', '7201'),
        '7201 秒（2.0 小时）',
      );
      expect(readCreditCellText('时长(秒)', '36000'), '36000 秒（10 小时）');
      expect(readCreditCellText('总阅读时长(秒)', '0'), '0 秒');
    });

    test('非时长列原样、空值破折号', () {
      expect(readCreditCellText('完成时间', '2026-08-31 23:59:58'), '2026-08-31 23:59:58');
      expect(readCreditCellText('已读完图书书名', '学习通电子阅读20260802-3201'), '学习通电子阅读20260802-3201');
      expect(readCreditCellText('所属厂商', ''), '—');
      expect(readCreditCellText('是否通过', '是'), '是');
    });
  });

  group('学分说明常量', () {
    test('四部分规则与提示齐备', () {
      expect(readCreditRules.length, 4);
      expect(readCreditRules.first.title, contains('经典阅读'));
      expect(readCreditRules.first.body, contains('20 小时'));
      expect(readCreditRules[1].body, contains('10 册'));
      expect(readCreditRules[3].body, contains('20 个'));
      expect(readCreditNotice, contains('1 分'));
      expect(readCreditUpdateHint, contains('11 月份'));
    });
  });
}
