import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/datasources/public_query_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';

/// 公共查询纯逻辑守卫（字段名一律来自实测，见 `reverse_engineering/公共查询接口.md`）。
void main() {
  const term = PublicQueryTerm(xn: 2026, xqM: 0, name: '2026-2027学年第一学期');

  group('parseTermCode', () {
    test('逗号码（公共查询真实格式）与连字符号都吃', () {
      expect(parseTermCode('2026,0'), (xn: 2026, xqM: 0));
      expect(parseTermCode('2025-2'), (xn: 2025, xqM: 2));
      expect(parseTermCode(' 2024-1 '), (xn: 2024, xqM: 1));
    });

    test('非法输入返回 null', () {
      expect(parseTermCode(''), isNull);
      expect(parseTermCode('2026'), isNull);
      expect(parseTermCode('2026-'), isNull);
      expect(parseTermCode('abcd-0'), isNull);
      expect(parseTermCode('1999-0'), isNull);
      expect(parseTermCode('2026-99'), isNull);
      expect(parseTermCode('2026-0-1'), isNull);
    });
  });

  group('parseDropListOptions', () {
    test('解析真实响应（校区下拉）', () {
      const body =
          '[{"code":"1","name":"蛟桥园校区"},{"code":"3","name":"麦庐园校区"},'
          '{"code":"4","name":"枫林园校区"},{"code":"05","name":"深圳校区"}]';
      final options = parseDropListOptions(body);
      expect(options.length, 4);
      expect(options.first.code, '1');
      expect(options.first.name, '蛟桥园校区');
      expect(options.last.code, '05');
    });

    test('剥掉名称里的 [007] 前缀码，并保留方括号里的代码', () {
      final options = parseDropListOptions(
        '[{"code":"0032","name":"[007]产业经济研究院（规制与竞争研究中心）"},'
        '{"code":"0000001440","name":"[2612020C11]会计学261"}]',
      );
      expect(options.first.displayName, '产业经济研究院（规制与竞争研究中心）');
      expect(options.first.bracketCode, '007');
      expect(options.last.displayName, '会计学261');
      expect(options.last.bracketCode, '2612020C11');
    });

    test('容错：空串 / HTML 错误页 / 非法 JSON / 非数组 → 空列表且不抛', () {
      expect(parseDropListOptions(''), isEmpty);
      expect(parseDropListOptions('<html>凭证已失效</html>'), isEmpty);
      expect(parseDropListOptions('[{"code":"1",'), isEmpty);
      expect(parseDropListOptions('{"code":"1"}'), isEmpty);
    });

    test('容错：数组里混入非法项时跳过', () {
      final options = parseDropListOptions(
        '[{"code":"1","name":"A"},{"code":"","name":"B"},{"name":"C"},'
        '{"code":"2","name":"D"},null,"x"]',
      );
      expect(options.map((o) => o.code), ['1', '2']);
    });
  });

  group('parseTermOptions（Ms_KBBP_FBXQLLJXAP，逗号码）', () {
    test('解析真实响应并归一为逗号 code', () {
      const body =
          '[{"code":"2026,0","name":"2026-2027学年第一学期"},'
          '{"code":"2025,2","name":"2025-2026学年第二阶段"},'
          '{"code":"2025,0","name":"2025-2026学年第一学期"}]';
      final terms = parseTermOptions(body);
      expect(terms.length, 3);
      expect(terms.first.code, '2026,0');
      expect(terms.first.xn, 2026);
      expect(terms.first.xqM, 0);
      expect(terms.first.name, '2026-2027学年第一学期');
      expect(terms.first.matches(2026, 0), isTrue);
      expect(terms.first.matches(2026, 1), isFalse);
    });

    test('连字符形式的 code 也接受（老分支 StMsXnxqDxDesc）', () {
      final terms = parseTermOptions('[{"code":"2026-0","name":"x"}]');
      expect(terms.single.code, '2026,0');
    });

    test('跳过 code 非法的项', () {
      final terms = parseTermOptions(
        '[{"code":"bfy","name":"不放假"},{"code":"2026,0","name":"x"}]',
      );
      expect(terms.single.code, '2026,0');
    });
  });

  group('parseComboBoxXml（/taglib/CombBoxServlet.jsp，UTF-8）', () {
    test('解析真实教师选择器响应', () {
      const body =
          '<data>'
          '<info><filtrateCount>2</filtrateCount><value>101599</value>'
          '<filtrateInfo0>陈润平</filtrateInfo0>'
          '<name>陈润平(外国语学院)</name><fillName>陈润平(外国语学院)</fillName></info>'
          '<info><filtrateCount>2</filtrateCount><value>102465</value>'
          '<name>韩加林(信息管理与数学学院)</name></info>'
          '</data>';
      final options = parseComboBoxXml(body);
      expect(options.length, 2);
      expect(options.first.code, '101599');
      expect(options.first.name, '陈润平(外国语学院)');
      expect(options.last.code, '102465');
    });

    test('解析班级选择器（带 [代码] 前缀）', () {
      const body =
          '<data><info><value>0000001459</value>'
          '<name>[2602010B21]经济统计学(拔尖实验班)261</name></info></data>';
      final options = parseComboBoxXml(body);
      expect(options.single.bracketCode, '2602010B21');
      expect(options.single.displayName, '经济统计学(拔尖实验班)261');
    });

    test('还原 XML 实体；空响应 / 无 info 返回空表', () {
      final options = parseComboBoxXml(
        '<data><info><value>a&amp;b</value><name>甲&amp;乙</name></info></data>',
      );
      expect(options.single.code, 'a&b');
      expect(options.single.name, '甲&乙');
      expect(parseComboBoxXml(''), isEmpty);
      expect(parseComboBoxXml('<data></data>'), isEmpty);
    });
  });

  group('parsePkts / 结果判定', () {
    test('pkts 是纯文本数字', () {
      expect(parsePkts('7'), '7');
      expect(parsePkts(' 6\n'), '6');
      expect(parsePkts(''), '');
      expect(parsePkts('<html>凭证已失效</html>'), '');
    });

    test('空结果两种文案都要认（GS1 与 GS4 用词不同）', () {
      expect(isEmptyReport('<div>没有检索到记录！</div>'), isTrue);
      expect(isEmptyReport("<p>没有符合检索条件的记录！</p>"), isTrue);
      expect(isEmptyReport('<table><tr><td>课程</td></tr></table>'), isFalse);
    });

    test('会话失效判定', () {
      expect(
        isExpiredSession("<script>alert('温馨提示：凭证已失效，请重新登录!')</script>"),
        isTrue,
      );
      expect(isExpiredSession('<table>课程</table>'), isFalse);
    });
  });

  group('decodeGbkBytes / encodeForm', () {
    test('GBK 字节 → 中文', () {
      // "课程课表" 的 GBK 编码
      const bytes = [191, 206, 179, 204, 191, 206, 177, 237];
      expect(decodeGbkBytes(bytes), '课程课表');
    });

    test('空字节返回空串', () {
      expect(decodeGbkBytes(const []), '');
    });

    test('失效页是 UTF-8：解码后必须认得出（否则静默变「没有检索到记录」）', () {
      const alertBody =
          "<script>alert('温馨提示：凭证已失效，请重新登录!');"
          "if (window.frmbody){ window.top.location.href='/'; }</script>";
      final decoded = decodeGbkBytes(utf8.encode(alertBody));
      expect(isExpiredSession(decoded), isTrue);
      // 反例：先按 GBK 解 = 乱码，判据全灭。
      expect(isExpiredSession(gbk.decode(utf8.encode(alertBody))), isFalse);
    });

    test('表单体是 x-www-form-urlencoded（不能是 multipart）', () {
      final body = PublicQueryRemoteDataSource.encodeForm({
        'xn': '2026',
        'xq_m': '0',
        'xnxq': '2026,0',
        'selBJMC': '会计 学',
      });
      expect(
        body,
        'xn=2026&xq_m=0&xnxq=2026%2C0&selBJMC=%E4%BC%9A%E8%AE%A1+%E5%AD%A6',
      );
      expect(body.contains('--'), isFalse);
    });
  });

  group('buildReportFields（实测字段契约）', () {
    test('公共字段：xnxq 逗号 / xn1 空 / menucode 截成 S / sfxsym=xsym / pkts 透传', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          pkts: '7',
          campusCode: '1',
          classCode: '0000001459',
        ),
      );
      expect(f['xnxq'], '2026,0');
      expect(f['xn'], '2026');
      expect(f['xn1'], '');
      expect(f['_xq'], '');
      expect(f['xq_m'], '0');
      expect(f['menucode'], 'S');
      expect(f['sfxsym'], 'xsym');
      expect(f['pkts'], '7');
      expect(f['selGS'], '1');
      expect(f['radiob'], 'A4');
      expect(f['radiofx'], 'hx');
      expect(f['orientation'], 'L');
      expect(f['userType'], 'STU');
      expect(f['nj'], '2026');
      expect(f['isNjQuery'], 'on');
      expect(f.containsKey('hidFlag'), isFalse);
    });

    test('班级课表 · 分班级：hidCXLX=fbj + radioa=5，且 sel/hid 成对同步', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
          departmentCode: '05',
          majorCode: '0509',
          classCode: '0000001459',
          trainLevel: '05',
        ),
      );
      expect(f['hidCXLX'], 'fbj');
      expect(f['radioa'], '5');
      expect(f['selXQ'], '1');
      expect(f['hidXQ'], '1');
      expect(f['selYXB'], '05');
      expect(f['hidYXB'], '05');
      expect(f['selZY'], '0509');
      expect(f['hidZYDM'], '0509');
      expect(f['selBJ'], '0000001459');
      expect(f['hidBJDM'], '0000001459');
      expect(f['selPYCC'], '05');
      expect(f['hidPYCC'], '05');
    });

    test('班级课表 · 分学院：hidCXLX=fyxb + radioa=3（实测 会计学院 05 → 2 张表）', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
          departmentCode: '05',
        ),
      );
      expect(f['hidCXLX'], 'fyxb');
      expect(f['radioa'], '3');
      expect(f['selYXB'], '05');
      expect(f['selZY'], '');
      expect(f['hidZYDM'], '');
      expect(f['selBJ'], '');
    });

    test('班级课表 · 分专业：hidCXLX=fzy + radioa=4（实测 05+0518 → 2 张表）', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
          departmentCode: '05',
          majorCode: '0518',
        ),
      );
      expect(f['hidCXLX'], 'fzy');
      expect(f['radioa'], '4');
      expect(f['selYXB'], '05');
      expect(f['selZY'], '0518');
      expect(f['hidZYDM'], '0518');
      expect(f['selBJ'], '');
    });

    test('班级课表 · 分学院可不要校区（实测 校区空 + 学院 05 也出数）', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          departmentCode: '05',
        ),
      );
      expect(f['hidCXLX'], 'fyxb');
      expect(f['radioa'], '3');
      expect(f['selXQ'], '');
      expect(f['hidXQ'], '');
    });

    test('培养层次原样提交（实测 05 命中 / 02 查空 / 空=不限，别写死 05）', () {
      Map<String, String> fields(String level) => buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
          classCode: '0000001457',
          trainLevel: level,
        ),
      );
      expect(fields('05')['selPYCC'], '05');
      expect(fields('05')['hidPYCC'], '05');
      expect(fields('02')['selPYCC'], '02');
      expect(fields('')['selPYCC'], '');
      expect(fields('')['hidPYCC'], '');
    });

    test('班级课表 · 只有校区 → 分校区（实测唯一「无过滤也出数」的形态）', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
        ),
      );
      expect(f['hidCXLX'], 'fxq');
      expect(f['radioa'], '2');
      expect(f['hidBJDM'], '');
    });

    test('班级课表 · 什么都不选 → 全校区', () {
      final f = buildReportFields(
        PublicQueryRequest(kind: PublicQueryKind.klass, term: term),
      );
      expect(f['hidCXLX'], '');
      expect(f['radioa'], '1');
    });

    test('教师课表：hidFlag=ggcxjskb + radio=2 + hidCXLX=fjs', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.teacher,
          term: term,
          teacherCode: '101599',
          campusCode: '3',
        ),
      );
      expect(f['hidFlag'], 'ggcxjskb');
      expect(f['hidCXLX'], 'fjs');
      expect(f['radio'], '2');
      expect(f['selJS'], '101599');
      expect(f['hidJSDM'], '101599');
      expect(f['hid_kc'], '');
    });

    test('教室课表：radioa=on，按楼房/按教室切换 hidCXLX', () {
      final byFloor = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.classroom,
          term: term,
          campusCode: '1',
          buildingCode: '35',
        ),
      );
      expect(byFloor['radioa'], 'on');
      expect(byFloor['hidCXLX'], 'flf');
      expect(byFloor['selLF'], '35');
      expect(byFloor['hidLF'], '35');
      expect(byFloor['xkyjs'], '1');

      final byRoom = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.classroom,
          term: term,
          campusCode: '1',
          roomCode: '0000231',
        ),
      );
      expect(byRoom['hidCXLX'], 'fjsi');
      expect(byRoom['hidFJBH'], '0000231');
    });

    test('课程课表：hidKCDM 用的是内部 id（不是课程代码）', () {
      final f = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.course,
          term: term,
          courseCode: '2020613',
        ),
      );
      expect(f['hidKCDM'], '2020613');
      expect(f['selectkc'], '');
    });

    test('年级默认取学年，可显式覆盖', () {
      final f1 = buildReportFields(
        PublicQueryRequest(kind: PublicQueryKind.klass, term: term),
      );
      expect(f1['nj'], '2026');
      final f2 = buildReportFields(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          grade: '2025',
        ),
      );
      expect(f2['nj'], '2025');
      expect(f2['hidNJ'], '2025');
    });
  });

  group('PublicQueryKind', () {
    test('菜单码 / kblx / 页面路径 / 选择器节点名', () {
      expect(PublicQueryKind.course.reportType, 'kckb');
      expect(PublicQueryKind.teacher.reportType, 'jskb');
      expect(PublicQueryKind.klass.reportType, 'bjkb');
      expect(PublicQueryKind.classroom.reportType, 'jsikb');
      expect(PublicQueryKind.klass.menuCode, 'SB03');
      expect(
        PublicQueryKind.teacher.pagePath,
        '/kbbp/dykb.jskb.html?menucode=SB02',
      );
      expect(PublicQueryKind.kindOfMenu('SB04'), PublicQueryKind.classroom);
    });

    test('hidFlag 只有教师课表非空（smx* 是三门峡专属，别照抄）', () {
      expect(PublicQueryKind.teacher.hidFlag, 'ggcxjskb');
      expect(PublicQueryKind.klass.hidFlag, '');
      expect(PublicQueryKind.classroom.hidFlag, '');
      expect(PublicQueryKind.course.hidFlag, '');
    });

    test('选择器节点名（CombBoxServlet 的 className）', () {
      expect(
        PublicQueryKind.klass.comboClassName,
        'kbbp_dykb_SpecialClassComb',
      );
      expect(PublicQueryKind.teacher.comboClassName, 'jbxx_EmployeeAndTeacher');
      expect(PublicQueryKind.course.comboClassName, 'jw_comb_coursename');
      expect(PublicQueryKind.classroom.comboClassName, 'jxap_combbox_js');
    });
  });

  group('PublicQueryRequest', () {
    test('comboParams 与页面 setCombBoxOtherParameter 对齐', () {
      final klass = PublicQueryRequest(
        kind: PublicQueryKind.klass,
        term: term,
        campusCode: '1',
        departmentCode: '05',
        majorCode: '0509',
      );
      expect(klass.comboParams(), {
        'xn': '2026',
        'xq_m': '0',
        'nj': '2026',
        'yxb': '05',
        'zy': '0509',
        'flag': '',
        'xqdm': '1',
      });
      final teacher = PublicQueryRequest(
        kind: PublicQueryKind.teacher,
        term: term,
        departmentCode: '00',
      );
      expect(teacher.comboParams()['jsbm'], '00');
      expect(teacher.comboParams()['flag'], 'ggcxjskb');
      final classroom = PublicQueryRequest(
        kind: PublicQueryKind.classroom,
        term: term,
        campusCode: '1',
        buildingCode: '02',
      );
      expect(classroom.comboParams()['flag'], 'xkyjs');
      expect(classroom.comboParams()['lf_m'], '02');
    });

    test('ready：各类别的最小可查条件', () {
      expect(
        PublicQueryRequest(kind: PublicQueryKind.course, term: term).ready,
        isFalse,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.course,
          term: term,
          courseCode: '2020613',
        ).ready,
        isTrue,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.teacher,
          term: term,
          teacherCode: '101599',
        ).ready,
        isTrue,
      );
      expect(
        PublicQueryRequest(kind: PublicQueryKind.klass, term: term).ready,
        isFalse,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          campusCode: '1',
        ).ready,
        isTrue,
      );
      // 学院 / 专业单独也能查（实测三档都出数），不必先选校区
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          departmentCode: '05',
        ).ready,
        isTrue,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          majorCode: '0518',
        ).ready,
        isTrue,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.klass,
          term: term,
          classCode: '0000001457',
        ).ready,
        isTrue,
      );
      expect(
        PublicQueryRequest(
          kind: PublicQueryKind.classroom,
          term: term,
          campusCode: '1',
        ).ready,
        isTrue,
      );
    });

    test('值语义相等（provider family 的缓存键）', () {
      final a = PublicQueryRequest(
        kind: PublicQueryKind.klass,
        term: term,
        campusCode: '1',
        classCode: '0000001459',
      );
      final b = PublicQueryRequest(
        kind: PublicQueryKind.klass,
        term: term,
        campusCode: '1',
        classCode: '0000001459',
      );
      final c = b.copyWith(classCode: '0000001460');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.cacheKey, contains('0000001459'));

      // 学院 / 专业 / 培养层次都参与缓存键：换任一项都必须重新请求
      final byDept = PublicQueryRequest(
        kind: PublicQueryKind.klass,
        term: term,
        departmentCode: '05',
      );
      expect(byDept == byDept.copyWith(majorCode: '0518'), isFalse);
      expect(byDept == byDept.copyWith(trainLevel: '02'), isFalse);
    });
  });
}
