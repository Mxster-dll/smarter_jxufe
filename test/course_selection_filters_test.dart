/// 选课检索栏的复刻守卫（2026-09-15）。
///
/// 起因：用户指出「选课的搜索功能和原页面不一致」——原页面 `student/wsxk.zx.html`
/// （S2020202）的检索条件有 8 个控件，我们只做了「课程范围 + 课程名称」两个。
///
/// 本文件钉住三件事：
/// 1. **课程类别 / 课程属性是客户端过滤**（原页面 `cTypeFilter`/`cTypeFilter_kcsx`
///    从结果表格 `kclb2_kclb1` / `kcsx` 去重生成选项，`ctyQryData` 只做显隐），
///    绝不能再当成服务端参数发出去；
/// 2. 其余控件（`njzy` 年级专业 / `sel_yxb` 院(系)部 / `xwxmkc` 限未选满 / 检索）
///    必须真的落到请求里；
/// 3. 原页面的隐藏规则（`zxggrx`、`tspyggrx` 无年级专业；只有 `zxknj` 有院系部）
///    与那句 `alert("需选定年级/专业！")` 的文案。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_filters.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';

const String _fixture = 'test/fixtures/course_selection_optional.html';
const String _datasourcePath =
    'lib/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart';
const String _repositoryPath =
    'lib/features/ims/course_selection/data/course_selection_repository.dart';
const String _viewPath =
    'lib/features/ims/course_selection/presentation/selection_online_view.dart';

String _read(String path) => File(path).readAsStringSync();

/// 去掉注释后的源码（注释里允许解释旧写法，只禁**代码里**出现）。
String _code(String path) {
  final source = _read(path);
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final newline = source.indexOf('\n', i);
      i = newline < 0 ? source.length : newline;
    } else if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
    } else {
      buffer.write(source[i]);
      i++;
    }
  }
  return buffer.toString();
}

List<OptionalCourse> _fixtureCourses() {
  final parsed = parseOptionalCourses(_read(_fixture));
  return parsed.courses;
}

OptionalCourse _course({
  String name = '课程',
  String category = '',
  String attribute = '',
  String kclb1 = '',
  String kclb2 = '',
}) => OptionalCourse(
  name: name,
  category: category,
  attribute: attribute,
  kclb1: kclb1,
  kclb2: kclb2,
);

void main() {
  group('课程类别键与选项（原页面 cTypeFilter）', () {
    test('真实列表：键 = kclb2_kclb1，lb 为空时退回键本身', () {
      final courses = _fixtureCourses();
      expect(courses.length, 11);
      expect(optionalCourseCategoryKey(courses.first), '2302_04');
      // 实测这 11 行落在 7 个类别键上，且 `lb` 列**全为空** → 显示一律退回比较键
      //（原页面此时会渲染一个空文本选项，我们不复刻这个坑）。
      final options = optionalCourseCategoryOptions(courses);
      expect(options.length, 7);
      expect(options.first.key, '2302_04');
      expect(options.every((o) => o.label == o.key), isTrue);
      expect(options.map((o) => o.key).toSet(), {
        '2302_04',
        '2104_01',
        '2102_01',
        '2105_01',
        '2101_01',
        '2303_01',
        '2301_01',
      });
    });

    test('lb 非空时用它当显示文本，且按结果顺序去重', () {
      final courses = [
        _course(name: 'A', category: '专业必修', kclb1: '04', kclb2: '2302'),
        _course(name: 'B', category: '专业必修', kclb1: '04', kclb2: '2302'),
        _course(name: 'C', category: '公共任选', kclb1: '07', kclb2: '2302'),
      ];
      expect(optionalCourseCategoryOptions(courses), const [
        SelectionFilterOption(key: '2302_04', label: '专业必修'),
        SelectionFilterOption(key: '2302_07', label: '公共任选'),
      ]);
      expect(optionalCourseCategoryKey(courses.last), '2302_07');
    });

    test('课程属性：kcsx 列去重、跳过空值', () {
      final courses = _fixtureCourses();
      // 实测：10 门「理论课」+ 体育3 的「理论课/体育课」。
      expect(optionalCourseAttributeOptions(courses), const ['理论课', '理论课/体育课']);
      expect(
        optionalCourseAttributeOptions([
          _course(attribute: '理论课'),
          _course(attribute: ''),
          _course(attribute: '实验课'),
          _course(attribute: '理论课'),
        ]),
        const ['理论课', '实验课'],
      );
    });
  });

  group('客户端过滤（filterOptionalCourses）', () {
    test('两个条件都为空时原样返回（不发请求也不复制）', () {
      final courses = _fixtureCourses();
      expect(identical(filterOptionalCourses(courses), courses), isTrue);
    });

    test('真实列表：类别键与属性各自都能筛出子集', () {
      final courses = _fixtureCourses();
      // 2302_04 = 会计学 / 金融学 / 管理学原理；理论课 = 除体育3 外的 10 门。
      expect(filterOptionalCourses(courses, categoryKey: '2302_04').length, 3);
      expect(filterOptionalCourses(courses, attribute: '理论课').length, 10);
      expect(filterOptionalCourses(courses, categoryKey: '2302_99').length, 0);
      expect(filterOptionalCourses(courses, attribute: '实验课').length, 0);
      // 体育3 的类别键是 2105_01、属性是「理论课/体育课」→ 交集为空。
      expect(
        filterOptionalCourses(
          courses,
          categoryKey: '2105_01',
          attribute: '理论课',
        ).length,
        0,
      );
      expect(
        filterOptionalCourses(
          courses,
          categoryKey: '2302_04',
          attribute: '理论课',
        ).map((e) => e.name),
        const ['会计学', '金融学', '管理学原理'],
      );
    });

    test('类别与属性同时生效（取交集，优于原页面「后一次覆盖前一次」）', () {
      final courses = [
        _course(name: 'A', attribute: '理论课', kclb1: '04', kclb2: '2302'),
        _course(name: 'B', attribute: '实验课', kclb1: '04', kclb2: '2302'),
        _course(name: 'C', attribute: '理论课', kclb1: '07', kclb2: '2302'),
      ];
      final both = filterOptionalCourses(
        courses,
        categoryKey: '2302_04',
        attribute: '理论课',
      );
      expect(both.map((e) => e.name), const ['A']);
      expect(
        filterOptionalCourses(courses, attribute: '实验课').map((e) => e.name),
        const ['B'],
      );
    });
  });

  group('结果集变化后的校正（reconcileOptionalCourseFilters）', () {
    test('仍然存在的条件保留，失效的清空', () {
      final courses = [_course(attribute: '理论课', kclb1: '04', kclb2: '2302')];
      expect(
        reconcileOptionalCourseFilters(
          courses,
          categoryKey: '2302_04',
          attribute: '理论课',
        ),
        (categoryKey: '2302_04', attribute: '理论课'),
      );
      expect(
        reconcileOptionalCourseFilters(
          courses,
          categoryKey: '2302_07',
          attribute: '实验课',
        ),
        (categoryKey: '', attribute: ''),
      );
    });

    test('空结果集清掉全部条件（等价原页面每次检索重建下拉）', () {
      expect(
        reconcileOptionalCourseFilters(
          const [],
          categoryKey: '2302_04',
          attribute: '理论课',
        ),
        (categoryKey: '', attribute: ''),
      );
    });
  });

  group('年级/专业下拉 XML（parseDropListXml）', () {
    test('无数据 → 空列表', () {
      expect(
        parseDropListXml('<?xml version="1.0" encoding="UTF-8"?><root></root>'),
        isEmpty,
      );
      expect(parseDropListXml(''), isEmpty);
    });

    test('真实形态 <item><key>/<value>（年级/专业，2026-09-15 活会话实抓）', () {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?><root>'
          '<item><key>2025|4405</key><value>2025|计算机科学与技术</value></item>'
          '</root>';
      final options = parseDropListXml(xml);
      expect(options.length, 1);
      // 提交值是 `key`（`nj|zydm` 形态），显示文本是 `value`。
      expect(options.single.code, '2025|4405');
      expect(options.single.name, '2025|计算机科学与技术');
    });

    test('标准 <info><value>/<name> 形态', () {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?><root>'
          '<info><value>2025-4405</value><name>[2025]计算机科学与技术</name></info>'
          '<info><value>2024-0509</value><name>[2024]会计学&amp;财管</name></info>'
          '</root>';
      final options = parseDropListXml(xml);
      expect(options.length, 2);
      expect(options.first.code, '2025-4405');
      expect(options.first.name, '[2025]计算机科学与技术');
      expect(options.last.name, '[2024]会计学&财管');
    });

    test('属性形态与缺名兜底', () {
      const xml = "<root><row value='0000001440' name=''></row></root>";
      final options = parseDropListXml(xml);
      expect(options.length, 1);
      expect(options.single.code, '0000001440');
      expect(options.single.name, '0000001440');
    });
  });

  group('源码守卫：检索条件必须真的落地', () {
    test('数据源：院系部 / 限未选满真的进请求，类别属性不再当服务端参数', () {
      final code = _code(_datasourcePath);
      expect(code.contains("'sel_yxb': department"), isTrue);
      expect(code.contains("if (onlyWithVacancy) 'xwxmkc': 'on'"), isTrue);
      expect(code.contains('MsDepartmentYXB'), isTrue);
      expect(code.contains('STUD_preElcGradeSpecialty'), isTrue);
      expect(code.contains('DroplistControl.jsp'), isTrue);
      // 类别/属性（kcsx / kclb1 / kclb2）必须是空字面量，不再是 category 参数。
      expect(code.contains("'kcsx': category"), isFalse);
      expect(code.contains("'kclb1': category"), isFalse);
      expect(code.contains("'kclb2': category"), isFalse);
      expect(code.contains('category1'), isFalse);
      expect(code.contains('category2'), isFalse);
    });

    test('查询对象：带 department / onlyWithVacancy，默认勾选限未选满', () {
      final code = _code(_repositoryPath);
      expect(code.contains('department: query.department'), isTrue);
      expect(code.contains('onlyWithVacancy: query.onlyWithVacancy'), isTrue);
      expect(code.contains('this.onlyWithVacancy = true'), isTrue);
      expect(code.contains('fetchDepartments'), isTrue);
      expect(code.contains('fetchGradeMajors'), isTrue);
      // 旧的 category 字段已删除（它曾是服务端过滤）。
      expect(RegExp(r'this\.category\s*=').hasMatch(code), isFalse);
    });

    test('界面：8 个控件与原文文案齐备，且类别/属性走客户端过滤', () {
      final code = _code(_viewPath);
      for (final keyword in [
        '限未选满的课程',
        '检索',
        '院(系)/部',
        '年级/专业',
        '课程类别',
        '课程属性',
        '课程代码（前缀匹配）或课程名称（模糊匹配）',
        '需选定年级/专业！',
        'selectionDepartmentOptionsProvider',
        'selectionGradeMajorOptionsProvider',
        'reconcileOptionalCourseFilters',
        'filterOptionalCourses',
        'department: _department',
        'onlyWithVacancy: _onlyWithVacancy',
      ]) {
        expect(code.contains(keyword), isTrue, reason: '界面缺少「$keyword」');
      }
      expect(
        code.contains(
          "kSelectionScopesWithoutGradeMajor = {'zxggrx', 'tspyggrx'}",
        ),
        isTrue,
      );
      expect(code.contains("kSelectionScopeCrossTerm = 'zxknj'"), isTrue);
    });

    test('课程范围用教务下发的 kcfw/kcfwmc（原页面最终形态），不是只靠 MsKcfw', () {
      final code = _code(_viewPath);
      expect(code.contains('session.scopeCodes'), isTrue);
      expect(code.contains('session.scopeNames'), isTrue);
    });
  });
}
