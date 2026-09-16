/// 守卫：选课模块的解析必须能吃住教务的真实响应。
///
/// fixture 全部是 2026-09-14 从教务抓下来的**原样**响应（GBK 已解成 UTF-8 文本）
/// 放在 `test/fixtures/course_selection_*.html`；换解析口径前先让本文件全绿。
library;

import 'dart:convert';
import 'dart:io';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/data_table_page.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';

String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('通用 DataTable 解析', () {
    test('按 td 的 name 取格，并读 showTotalRecord 的总条数', () {
      final page = parseDataTablePage(
        fixture('course_selection_optional.html'),
      );
      expect(page.total, 11);
      expect(page.rows.length, 11);
      expect(page.rows.first['kc'], '[1004001943]会计学');
      expect(page.rows.first['kcdm'], '000160');
    });

    test('空响应与无总条数时不炸', () {
      expect(parseDataTablePage('').rows, isEmpty);
      expect(parseDataTablePage('<html></html>').total, isNull);
      expect(dataTableIsEmptyResult('没有检索到记录！'), isTrue);
      expect(dataTableIsEmptyResult('<html></html>'), isFalse);
    });

    test('单元格清洗与 [代码]名称 拆分', () {
      expect(normalizeTableCell('  2-17周&ensp; 四[3-4]  '), '2-17周&ensp; 四[3-4]');
      expect(normalizeTableCell('a\u00a0\u3000b'), 'a b');
      final coded = splitCodedName('[1004001943]会计学');
      expect(coded.code, '1004001943');
      expect(coded.name, '会计学');
      expect(splitCodedName('会计学').code, '');
      expect(splitCodedName('会计学').name, '会计学');
    });
  });

  group('可选课程列表（tableId=2568）', () {
    test('11 条课程，字段齐', () {
      final result = parseOptionalCourses(
        fixture('course_selection_optional.html'),
      );
      expect(result.total, 11);
      expect(result.courses.length, 11);
      final first = result.courses.first;
      expect(first.name, '会计学');
      expect(first.courseCode, '1004001943');
      expect(first.internalCode, '000160');
      expect(first.credits, 3.0);
      expect(first.totalHours, 48);
      expect(first.attribute, '理论课');
      expect(first.kclb1, '04');
      expect(first.kclb2, '2302');
      expect(first.examMode, '02');
      // 课程级列表里教师/班号是空的，选了教学班才有。
      expect(first.teacher, isEmpty);
      expect(first.classCode, isEmpty);
      expect(first.alreadySelected, isFalse);
    });

    test('课程名里带括号与空格的都能解析', () {
      final result = parseOptionalCourses(
        fixture('course_selection_optional.html'),
      );
      expect(
        result.courses.map((e) => e.name),
        containsAll(<String>['会计学', '金融学', '管理学原理']),
      );
      expect(result.courses.every((e) => e.name.isNotEmpty), isTrue);
    });
  });

  group('教学班列表（tableId=6142）', () {
    test('9 个教学班，时间/地点/人数/班号齐', () {
      final sections = parseSections(fixture('course_selection_sections.html'));
      expect(sections.length, 9);
      final first = sections.first;
      expect(first.classCode, '000160-016');
      expect(first.className, '辅修+');
      expect(first.teacher, '杨明');
      expect(first.time, '2-17周 四(3-5节)');
      expect(first.place, '麦三教3213');
      expect(first.timePlace, '2-17周 四(3-5节) 麦三教3213');
      expect(first.campus, '麦庐园校区');
      expect(first.enrolled, '48/0');
      expect(first.limit, '48');
      expect(first.teachMode, '理论');
      expect(first.outnumber, '0');
      expect(first.timeConflictFlag, '0');
    });

    test('每个教学班都有可提交的班号', () {
      final sections = parseSections(fixture('course_selection_sections.html'));
      expect(sections.every((e) => e.classCode.contains('-')), isTrue);
    });
  });

  group('选课结果（wsxk.zxjg.jsp）', () {
    test('统计与课程列表', () {
      final result = parseSelectionResult(
        fixture('course_selection_result.html'),
      );
      expect(result.termLabel, '2026-2027学年第一学期');
      expect(result.creditLimit, 26);
      expect(result.totalCredits, 25.5);
      expect(result.totalCount, 10);
      expect(result.courses.length, 10);
      expect(result.remainingCredits, closeTo(0.5, 0.001));
    });

    test('课程字段：课程/学分/教师/时间地点/退选码', () {
      final result = parseSelectionResult(
        fixture('course_selection_result.html'),
      );
      final english = result.courses.firstWhere(
        (e) => e.name == '英语视听说',
      );
      expect(english.courseCode, '1004606732');
      expect(english.credits, 2.0);
      expect(english.teacher, '陈润平');
      expect(english.classCode, '1004606732-066');
      expect(english.status, '选中');
      expect(english.enrolled, '45/0');
      expect(english.campus, '麦庐园校区');
      expect(english.timePlace, '2-17周 四[3-4] 麦三教3111(70)');
      // 退选要用的就是这串（教务表格末格 = 上课班组代码）。
      expect(english.itemCode, '1004606732-066');
      expect(result.courses.every((e) => e.itemCode.isNotEmpty), isTrue);
      expect(result.courses.every((e) => e.name.isNotEmpty), isTrue);
    });

    test('入学以来正选结果（wsxk.zxjg_all.jsp）也能解析', () {
      final result = parseSelectionResult(
        fixture('course_selection_result_all.html'),
      );
      expect(result.termLabel, '2025-2026学年第一学期');
      expect(result.courses.length, greaterThanOrEqualTo(10));
      expect(
        result.courses.map((e) => e.name),
        contains('大学英语I'),
      );
      expect(result.courses.every((e) => e.itemCode.isNotEmpty), isTrue);
    });
  });

  group('被取消课程（wsxk.qxbxkc.jsp）', () {
    test('「没有相关数据！」= 空且不当作解析失败', () {
      final parsed = parseCancelledCourses(
        fixture('course_selection_cancelled.html'),
      );
      expect(parsed.empty, isTrue);
      expect(parsed.courses, isEmpty);
    });
  });

  group('申请扩容（tableId=5929098）', () {
    test('按列名取到限选/已选与审核状态', () {
      final page = parseDataTableRows(
        fixture('course_selection_expand.html'),
      );
      expect(page.total, 2);
      expect(page.rows.length, 2);
      final first = page.rows.first;
      expect(splitCodedName(first['kc'] ?? '').name, '管理学原理');
      expect(first['xkrssx'], '50');
      expect(first['skbjdm'], '001282-012');
    });
  });

  group('课程范围下拉与元信息', () {
    test('MsKcfw 的 JSON 解析', () {
      final scopes = parseCourseScopes(
        '[{"code":"zxbnj","name":"主修(本专业本学期)"},'
        '{"code":"zxggrx","name":"主修(公共任选)"},'
        '{"code":"fx","name":"辅修"}]',
      );
      expect(scopes.length, 3);
      expect(scopes.first.code, 'zxbnj');
      expect(scopes.first.name, '主修(本专业本学期)');
      expect(parseCourseScopes('not json'), isEmpty);
    });

    test('getWsxkTimeRange 的信封（result 是字符串化 JSON）', () {
      const raw =
          '{"status":"200","message":"操作成功!","result":"{\\"xn\\":\\"2026\\",'
          '\\"xqM\\":\\"0\\",\\"xqName\\":\\"第一学期\\",\\"xnxqDesc\\":'
          '\\"2026-2027学年第一学期\\",\\"qssj\\":\\"2026-09-14 09:00\\",'
          '\\"jssj\\":\\"2026-09-16 17:00\\",\\"rxksjqs\\":\\"09:00\\",'
          '\\"rxksjjs\\":\\"17:00\\",\\"isValidTimerange\\":\\"1\\",'
          '\\"lcmc\\":\\"第一轮退改选\\",\\"lcid\\":\\"81827178928142681880626\\",'
          '\\"xh\\":\\"201600035929\\",'
          '\\"nj\\":\\"2025\\",\\"zydm\\":\\"4405\\",\\"yxbdm\\":\\"44\\",'
          '\\"kcfw\\":\\"zxbnj,zxggrx,fx,zxknj\\",'
          '\\"kcfwmc\\":\\"主修(本年级/专业),主修(公共任选),辅修,主修(可跨年级/专业)\\"}"}';
      final session = SelectionSession.fromEnvelope(
        tryJsonMap(raw)!,
        xktype: 2,
      );
      expect(session.ok, isTrue);
      expect(session.open, isTrue);
      expect(session.xn, '2026');
      expect(session.xqM, '0');
      expect(session.xnxqDesc, '2026-2027学年第一学期');
      expect(session.lcmc, '第一轮退改选');
      // 教务选课模块自己给的学生号 —— 选课请求必须回传它，否则提交会被判「不是本人」。
      expect(session.xh, '201600035929');
      expect(session.windowLabel, '2026-09-14 09:00 → 2026-09-16 17:00');
      expect(session.dailyLabel, '09:00 → 17:00');
      expect(session.scopeCodes, ['zxbnj', 'zxggrx', 'fx', 'zxknj']);
      expect(session.scopeNames.length, 4);
    });

    test('未开放时 open 为 false', () {
      final session = SelectionSession.fromEnvelope(
        tryJsonMap(
          '{"status":"400","message":"非选课时间","result":"{'
          '\\"isValidTimerange\\":\\"0\\",\\"xn\\":\\"2026\\",\\"xqM\\":\\"0\\"}"}',
        )!,
        xktype: 2,
      );
      expect(session.ok, isFalse);
      expect(session.open, isFalse);
      // 响应里没有 `xh` 时留空 —— 调用方（selectionStudentIdProvider）据此回退学籍。
      expect(session.xh, '');
    });

    test('已选学分/门数', () {
      final quota = SelectionQuota.fromEnvelope(
        tryJsonMap(
          '{"status":"200","result":"{\\"zdxf\\":21.5,\\"zdms\\":7.0,'
          '\\"yxxf\\":25.5,\\"yxms\\":10.0,\\"zxf\\":25.5,\\"zms\\":10.0,'
          '\\"feetotal\\":\\"课程学分费用预算总额：1530.0元\\"}"}',
        )!,
      );
      expect(quota.usedCredits, 25.5);
      expect(quota.usedCount, 10);
      expect(quota.specifiedCredits, 21.5);
      expect(quota.feeText, contains('1530.0元'));
    });

    test('学籍年级专业', () {
      final gm = StudentGradeMajor.fromEnvelope(
        tryJsonMap(
          '{"status":"200","result":"{\\"nj\\":\\"2025\\",\\"pycc\\":\\"05\\",'
          '\\"dwh\\":\\"44\\",\\"zydm\\":\\"4405\\",\\"zymc\\":\\"计算机科学与技术\\"}"}',
        )!,
      );
      expect(gm.nj, '2025');
      expect(gm.zydm, '4405');
      expect(gm.zymc, '计算机科学与技术');
    });
  });

  group('表单编码', () {
    test('中文按 GBK 百分号编码（教务按 GBK 解参数）', () {
      expect(
        encodeGbkForm({'kcmc': '会计学'}),
        'kcmc=%BB%E1%BC%C6%D1%A7',
      );
      expect(
        encodeGbkForm({'xn': '2026', 'q': 'a b'}),
        'xn=2026&q=a%20b',
      );
    });

    test('会话失效文本的判据', () {
      expect(
        CourseSelectionRemoteDataSource.isExpiredSession(
          "<script>alert('温馨提示：凭证已失效，请重新登录!');</script>",
        ),
        isTrue,
      );
      expect(
        CourseSelectionRemoteDataSource.isExpiredSession('<html>选课</html>'),
        isFalse,
      );
    });

    test('失效页是 UTF-8：解码后必须认得出（否则静默变空数据）', () {
      // 实测原文（523 字符）：教务正文页是 GBK，但这一页是 UTF-8。
      const alertBody =
          "<script>alert('温馨提示：凭证已失效，请重新登录!');"
          "if (window.frmbody){ window.top.location.href='/'; }</script>";
      final decoded = decodeJwPage(utf8.encode(alertBody));
      expect(decoded, contains('凭证已失效'));
      expect(CourseSelectionRemoteDataSource.isExpiredSession(decoded), isTrue);
      // 反例：先按 GBK 解会得到乱码，判据全灭 —— 这正是 2026-09-14 的 bug。
      expect(
        CourseSelectionRemoteDataSource.isExpiredSession(
          gbk.decode(utf8.encode(alertBody)),
        ),
        isFalse,
      );
    });

    test('正文页仍是 GBK：中文正常还原', () {
      expect(decodeJwPage(gbk.encode('学年学期：2026-2027学年第一学期')), '学年学期：2026-2027学年第一学期');
      expect(decodeJwPage(const []), '');
    });
  });
}
