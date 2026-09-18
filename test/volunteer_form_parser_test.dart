import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/docx_text.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/volunteer_form_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';

/// 真实《江西财经大学青年志愿者志愿服务时长认定登记表》Word 原件
/// （`GET /admin/tzz/StuVolWork/downloadInfo.do`），已脱敏（姓名/学号/学院/专业）。
///
/// 它是**唯一还能拿到活动日期的地方**：详情页 `apply_one_detail.html`
/// 自 2026-09-18 起对该账号的 5 条记录一律返回「出错了」错误页。
Uint8List _fixtureBytes() =>
    File('test/fixtures/volunteer_form_2026.docx').readAsBytesSync();

VolunteerActivity _activity({
  required int index,
  required String name,
  String start = '',
  String end = '',
  String hours = '4',
  String detailId = '847517',
}) {
  return VolunteerActivity(
    index: index,
    activityName: name,
    initiator: '发起人',
    responsiblePerson: '负责人',
    department: '社会与人文学院',
    activityCategory: '短期校内活动',
    recognizedHours: hours,
    applicationStatus: '申请通过',
    recognitionStatus: '已认定',
    detailId: detailId,
    detailType: '0',
    startDate: start,
    endDate: end,
  );
}

// ── 自建最小 ZIP（只用于测「容器读取」本身：CRC 不校验故写 0） ──────────────

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];

List<int> _u32(int v) =>
    [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

Uint8List _zip({
  required String entryName,
  required String content,
  required int method,
}) {
  final name = utf8.encode(entryName);
  final plain = utf8.encode(content);
  final stored = method == 8
      ? Uint8List.fromList(ZLibEncoder(raw: true).convert(plain))
      : Uint8List.fromList(plain);

  final local = BytesBuilder()
    ..add(_u32(0x04034b50))
    ..add(_u16(20))
    ..add(_u16(0))
    ..add(_u16(method))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u32(0)) // CRC（读取器不校验）
    ..add(_u32(stored.length))
    ..add(_u32(plain.length))
    ..add(_u16(name.length))
    ..add(_u16(0))
    ..add(name)
    ..add(stored);
  final localBytes = local.toBytes();

  final central = BytesBuilder()
    ..add(_u32(0x02014b50))
    ..add(_u16(20))
    ..add(_u16(20))
    ..add(_u16(0))
    ..add(_u16(method))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u32(0))
    ..add(_u32(stored.length))
    ..add(_u32(plain.length))
    ..add(_u16(name.length))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u32(0))
    ..add(_u32(0)) // 本地头偏移
    ..add(name);
  final centralBytes = central.toBytes();

  final eocd = BytesBuilder()
    ..add(_u32(0x06054b50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(1))
    ..add(_u16(1))
    ..add(_u32(centralBytes.length))
    ..add(_u32(localBytes.length))
    ..add(_u16(0));

  return Uint8List.fromList([
    ...localBytes,
    ...centralBytes,
    ...eocd.toBytes(),
  ]);
}

void main() {
  group('认定登记表解析（真实 Word 原件）', () {
    test('解析出 5 条记录：序号 / 名称 / 认定日期 / 类别 / 时长', () {
      final rows = parseVolunteerForm(_fixtureBytes());
      expect(rows, hasLength(5));
      expect(rows.map((r) => r.index).toList(), [1, 2, 3, 4, 5]);
      expect(
        rows.map((r) => r.date).toSet(),
        {
          '2025-10-27',
          '2025-12-15',
          '2025-12-12',
          '2026-03-01',
          '2026-05-28',
        },
        reason: '日期是学年归集的唯一依据，逐值锁定',
      );
      expect(rows.every((r) => r.category == 'A类'), isTrue);
      expect(rows.map((r) => r.hours).toList(), [
        '4.0',
        '4.0',
        '4.0',
        '4.0',
        '8.0',
      ]);
      expect(rows.fold<double>(0, (sum, r) => sum + r.hoursValue), 24.0);
    });

    test('表头行与「志愿服务总时长」合计行不算记录', () {
      final rows = parseVolunteerForm(_fixtureBytes());
      expect(rows.any((r) => r.name == '活动名称'), isFalse);
      expect(rows.any((r) => r.name.contains('总时长')), isFalse);
      expect(rows.every((r) => r.name.isNotEmpty && r.date.isNotEmpty), isTrue);
    });

    test('名称里的空白在两份数据间不一致 → 归一化后可比对', () {
      // 列表页：`Ea  574  迎新晚会志愿时长`（多空格）／登记表：`Ea 574 迎新晚会志愿时长`
      expect(
        volunteerActivityKey('Ea  574  迎新晚会志愿时长'),
        volunteerActivityKey('Ea 574 迎新晚会志愿时长'),
      );
      expect(volunteerActivityKey(' 某 活动\u3000A '), '某活动A');
    });
  });

  group('DOCX / ZIP 读取（dart:io ZLibDecoder，无第三方依赖）', () {
    test('真实 fixture 能取出 word/document.xml', () {
      final xml = docxDocumentXml(_fixtureBytes());
      expect(xml, isNotNull);
      expect(xml, contains('Ad1149草地迎新音乐节'));
      expect(xml, contains('2025年10月27日'));
    });

    test('自建 ZIP：deflate(8) 与 store(0) 都能取到', () {
      const xml = '<w:document><w:tr><w:tc><w:t>甲</w:t></w:tc></w:tr>'
          '</w:document>';
      for (final method in [8, 0]) {
        final bytes = _zip(
          entryName: 'word/document.xml',
          content: xml,
          method: method,
        );
        expect(docxDocumentXml(bytes), xml, reason: 'method=$method');
        expect(docxTableRowsOfBytes(bytes), [
          ['甲'],
        ]);
      }
    });

    test('不是 ZIP / 缺 word/document.xml → null 与空行', () {
      expect(docxDocumentXml(utf8.encode('<html>出错了</html>')), isNull);
      expect(docxTableRowsOfBytes(utf8.encode('nope')), isEmpty);
      final other = _zip(entryName: 'word/other.xml', content: 'x', method: 0);
      expect(docxDocumentXml(other), isNull);
    });

    test('单元格文本按 <w:t> 逐段拼接，并还原实体', () {
      const xml = '<w:document><w:tr>'
          '<w:tc><w:t>序号</w:t></w:tc>'
          '<w:tc><w:t xml:space="preserve">A &amp; B</w:t></w:tc>'
          '<w:tc><w:t>拆</w:t><w:t>开的</w:t><w:t>文本</w:t></w:tc>'
          '</w:tr></w:document>';
      expect(docxTableRows(xml), [
        ['序号', 'A & B', '拆开的文本'],
      ]);
    });
  });

  group('日期规范化', () {
    test('认 年月日 / - / . / ，并补零', () {
      expect(volunteerFormDateText('2025年10月27日'), '2025-10-27');
      expect(volunteerFormDateText('2025-1-2'), '2025-01-02');
      expect(volunteerFormDateText('2025/01/02'), '2025-01-02');
      expect(volunteerFormDateText('2026.3.1'), '2026-03-01');
      expect(volunteerFormDateText(' 2026年5月28日 '), '2026-05-28');
    });

    test('不存在的日期与垃圾输入 → null（不做静默滚动）', () {
      expect(volunteerFormDateText('2025-02-30'), isNull);
      expect(volunteerFormDateText('2025年13月1日'), isNull);
      expect(volunteerFormDateText('A类'), isNull);
      expect(volunteerFormDateText(''), isNull);
      expect(volunteerFormDateText('4.0小时'), isNull);
    });
  });

  group('用认定登记表补齐活动日期', () {
    final rows = parseVolunteerForm(_fixtureBytes());

    test('没有日期的行被补上（起止同日）；已有日期的行保持原值', () {
      final activities = [
        _activity(index: 1, name: 'Ad1149草地迎新音乐节·'),
        _activity(index: 2, name: 'ob374文艺晚会志愿活动', start: '2026-05-26', end: '2026-05-26'),
      ];
      final filled = volunteerApplyFormDates(activities, rows);
      expect(filled[0].startDate, '2025-10-27');
      expect(filled[0].endDate, '2025-10-27');
      expect(filled[0].activityDate, DateTime(2025, 10, 27));
      expect(filled[1].startDate, '2026-05-26', reason: '详情页取到的值优先');
    });

    test('名称只差空白也能补上', () {
      final filled = volunteerApplyFormDates([
        _activity(index: 1, name: 'Ea  574  迎新晚会志愿时长'),
      ], rows);
      expect(filled.single.startDate, '2025-12-15');
    });

    test('未命中的行原样保留（交给详情页兜底链路）', () {
      final activities = [_activity(index: 1, name: '登记表里没有的活动')];
      final filled = volunteerApplyFormDates(activities, rows);
      expect(identical(filled, activities), isTrue);
      expect(filled.single.activityDate, isNull);
    });

    test('空输入原样返回', () {
      expect(volunteerApplyFormDates(const [], rows), isEmpty);
      final activities = [_activity(index: 1, name: 'Ad1149草地迎新音乐节·')];
      expect(identical(volunteerApplyFormDates(activities, const []), activities), isTrue);
    });
  });

  group('学年归集（综测「学年志愿时长」口径）', () {
    test('5 条认定日期全部落在 2025-2026 学年 → 该学年 24h，下一学年 0h', () {
      final activities = volunteerApplyFormDates([
        _activity(index: 1, name: 'Ad1149草地迎新音乐节·'),
        _activity(index: 2, name: 'Ea  574  迎新晚会志愿时长'),
        _activity(index: 3, name: 'Pa0532 迎新晚会本科生演职人员'),
        _activity(index: 4, name: 'Sa0076数院元旦晚会表演人员'),
        _activity(index: 5, name: 'ob374文艺晚会志愿活动', hours: '8'),
      ], parseVolunteerForm(_fixtureBytes()));

      // 综测的 yearEnd=2026 → 学年窗口 2025-09-01 ~ 2026-08-31。
      final zc2026 = volunteerHoursStats(activities, xn: 2025);
      expect(zc2026.yearKnown, isTrue, reason: '有日期才敢报数，否则界面显示「—」');
      expect(zc2026.currentYear, 24.0);
      expect(zc2026.previousYear, 0.0);

      // yearEnd=2027 → 2026-2027 学年：一分都不该算进来。
      final zc2027 = volunteerHoursStats(activities, xn: 2026);
      expect(zc2027.currentYear, 0.0, reason: '跨学年的时长不许串门');
      expect(zc2027.previousYear, 24.0);
      expect(zc2027.total, 24.0);
    });
  });

  group('数据链路守卫', () {
    test('仓库先取认定登记表，再对缺日期的行回落详情页', () {
      final code = File(
        'lib/features/comprehensive_service/data/volunteer_hours_repository.dart',
      ).readAsStringSync();
      expect(code, contains('parseVolunteerForm('));
      expect(code, contains('fetchRecognitionForm('));
      expect(
        code.indexOf('_applyRecognitionForm(sessionId, rows)'),
        lessThan(code.indexOf('fetchActivityTime(')),
        reason: '登记表是一次请求、详情页是逐行 N 次；顺序颠倒会白跑 N 个必失败的请求',
      );
    });
  });
}
