/// 「点 A 行退掉 B 课」事故（2026-09-15）之后的安全守卫。
///
/// 事故现场（实测）：教务上从 10 门 / 25.5 学分变成 **9 门 / 21.5 学分**，
/// 消失的是**计算机组成原理**（用户点的是别的行），而 App 只回了一句「退选成功」。
/// 取证结论：我们提交的 `itemCode` 与教务页面自己的 `CancelData()`
///（`items += rows[ind].cells[l-1].innerHTML`，末格）**逐行一致**，所以「发错码」不是成因；
/// 成因是行内小按钮被误触 + 弹窗被顺手确认，而**写入之后没有任何对账**。
///
/// 本文件钉住三件事：
/// 1. 退选码**只认表格末格**，绝不再回退成 `classCode`（那是「上课班级」，语义不同）；
/// 2. 提交后**必须对账**：请求的课是否消失、有没有别的课跟着消失（`verifyCancellation`）；
/// 3. 界面层：行内不再有「退选」按钮（改菜单）、弹窗必须勾选核对才能确认。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_parsers.dart';
import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_write_check.dart';

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

SelectedCourse _course(
  String name,
  String code, {
  String itemCode = '',
  String classCode = '',
}) => SelectedCourse(
  name: name,
  cells: const [],
  courseCode: code,
  itemCode: itemCode,
  classCode: classCode,
);

SelectionResult _result(List<SelectedCourse> courses) =>
    SelectionResult(termLabel: '2026-2027学年第一学期', courses: courses);

void main() {
  group('退选对账（verifyCancellation）', () {
    final a = _course('计算机网络', '1014300174', itemCode: '1014300174-008');
    final b = _course('计算机组成原理', '1014300184', itemCode: '1014300184-004');
    final c = _course('数据结构与算法', '1014300314', itemCode: '1014300314-002');

    test('正常：请求的那门消失、别的没动 → 一致', () {
      final check = verifyCancellation(
        before: _result([a, b, c]),
        after: _result([b, c]),
        requestedItemCode: a.itemCode,
      );
      expect(check.verdict, SelectionCancelVerdict.confirmed);
      expect(check.ok, isTrue);
      expect(check.alarming, isFalse);
      expect(check.message, contains('已退选《计算机网络》'));
    });

    test('退错了：请求的课还在，却退掉了别的课 → 报警（最严重优先）', () {
      final check = verifyCancellation(
        before: _result([a, b, c]),
        after: _result([a, c]),
        requestedItemCode: a.itemCode,
      );
      expect(check.verdict, SelectionCancelVerdict.wrongCourseDropped);
      expect(check.alarming, isTrue);
      expect(check.extraDroppedNames, ['计算机组成原理']);
      expect(check.message, contains('不是你请求的'));
    });

    test('退错了：请求的那门和别的课一起消失 → 也要报警', () {
      final check = verifyCancellation(
        before: _result([a, b, c]),
        after: _result([c]),
        requestedItemCode: a.itemCode,
      );
      expect(check.verdict, SelectionCancelVerdict.wrongCourseDropped);
      expect(check.droppedNames, ['计算机网络', '计算机组成原理']);
      expect(check.extraDroppedNames, ['计算机组成原理']);
      expect(check.message, contains('共退掉 2 门'));
    });

    test('教务没执行：请求的课仍在、别的也没动', () {
      final check = verifyCancellation(
        before: _result([a, b, c]),
        after: _result([a, b, c]),
        requestedItemCode: a.itemCode,
      );
      expect(check.verdict, SelectionCancelVerdict.requestedStillPresent);
      expect(check.message, contains('没有执行'));
    });

    test('空码 / 该码不在退选前的列表里 → 判不出来（不谎报成功）', () {
      expect(
        verifyCancellation(
          before: _result([a]),
          after: _result(const []),
          requestedItemCode: '',
        ).verdict,
        SelectionCancelVerdict.unverifiable,
      );
      expect(
        verifyCancellation(
          before: _result([a]),
          after: _result(const []),
          requestedItemCode: '9999999-001',
        ).verdict,
        SelectionCancelVerdict.unverifiable,
      );
    });
  });

  group('选课对账（verifySubmission）', () {
    final a = _course('会计学', '0509011', itemCode: '0509011-001');

    test('结果里有这门课 → 一致', () {
      final check = verifySubmission(
        after: _result([a]),
        courseCode: '0509011',
        courseName: '会计学',
      );
      expect(check.verdict, SelectionSubmitVerdict.confirmed);
      expect(check.ok, isTrue);
      expect(check.message, contains('已选上《会计学》'));
    });

    test('教务回成功但结果里没有 → 报警（假成功）', () {
      final check = verifySubmission(
        after: _result(const []),
        courseCode: '0509011',
        courseName: '会计学',
      );
      expect(check.verdict, SelectionSubmitVerdict.missing);
      expect(check.alarming, isTrue);
      expect(check.message, contains('请到教务确认'));
    });

    test('空课程代码 → 判不出来', () {
      expect(
        verifySubmission(
          after: _result([a]),
          courseCode: '',
          courseName: '会计学',
        ).verdict,
        SelectionSubmitVerdict.unverifiable,
      );
    });
  });

  group('退选码解析加固', () {
    test('真实选课结果页：每行退选码 = 表格末格，且唯一', () {
      final html = _read('test/fixtures/course_selection_result.html');
      final result = parseSelectionResult(html);
      expect(result.courses, hasLength(10));
      for (final course in result.courses) {
        expect(
          course.itemCode,
          course.cells.last,
          reason: '${course.name} 的退选码必须取末格（教务 CancelData 同款）',
        );
        expect(course.itemCode, isNotEmpty);
      }
      expect(
        result.courses.map((c) => c.itemCode).toSet(),
        hasLength(10),
        reason: '退选码必须两两不同，否则退选会命中别门课',
      );
    });

    test('末格不是码（多出一列）→ 退选码留空，**绝不回退成 classCode**', () {
      final course = selectedCourseFromCells(const [
        '/>',
        '[1004606732]英语视听说',
        '2.0',
        '理论课 必修课',
        '陈润平',
        '1004606732-066',
        '管理人员选',
        '否',
        '选中',
        '45/0',
        '麦庐园校区',
        '2-17周 四[3-4] 麦三教3111(70)',
        '操作',
      ]);
      expect(course, isNotNull);
      expect(course!.classCode, '1004606732-066', reason: '上课班级照常解析出来供展示');
      expect(course.itemCode, isEmpty, reason: '取不到退选码就必须留空（界面禁用退选），不能拿上课班级顶替');
    });

    test('退选码只认末格：中间格里的码不会被当成退选码', () {
      final course = selectedCourseFromCells(const [
        '[1004606732]英语视听说',
        '2.0',
        '理论课 必修课',
        '陈润平',
        '1004606732-066',
        '管理人员选',
        '否',
        '选中',
        '45/0',
        '麦庐园校区',
        '2-17周 四[3-4] 麦三教3111(70)',
      ]);
      // 末格是上课时间地点 → 不是码 → 留空（旧实现会把 classCode 顶上来当退选码）。
      expect(course!.itemCode, isEmpty);
    });
  });

  group('源码守卫', () {
    test('行内不再有「退选」按钮，改为「更多」菜单', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
      );
      expect(code, contains('PopupMenuButton<_CourseAction>'));
      expect(code, contains("'退选本门课'"));
      expect(
        RegExp(r"Text\(\s*'退选'\s*\)").hasMatch(code),
        isFalse,
        reason: '每行一个小「退选」按钮就是这次误触的现场，别再回去',
      );
    });

    test('确认弹窗必须勾选核对才能确认，且确认按钮是危险色', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
      );
      expect(code, contains('Checkbox('));
      expect(code, contains('acknowledged'));
      expect(code, contains('FilledButton.styleFrom'));
      // 2026-09-16：深色下「红」分两个角色 —— 实心件用深红档，不再直接吃亮红
      // colorScheme.error（亮红压在 #121212 上只能偏浅，见 AGENTS.md §22）。
      expect(code, contains('backgroundColor: AppColors.errorFill(context)'));
      expect(code, contains('foregroundColor: AppColors.onErrorFill(context)'));
      expect(code.contains('backgroundColor: scheme.error'), isFalse);
      expect(code, contains('退选码（提交给教务）'));
      expect(code, contains('_reportCancelOutcome'));
      // 2026-09-15 二轮：确认弹窗改为「先重读核对（prepareCancel）→ 再提交（cancelChecked）」。
      expect(code, contains('prepareCancel'));
      expect(code, contains('cancelChecked'));
    });

    test('退选码必须在本页唯一指向这一行，否则直接阻止提交', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
      );
      expect(code, contains('final sameCode = result.courses'));
      expect(code, contains('sameCode != 1'));
      expect(code, contains('已阻止退选'));
    });

    test('退错了必须弹红字告警，不能只 SnackBar 一句「退选成功」', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
      );
      expect(code, contains('outcome.alarming'));
      expect(code, contains('退选结果与请求不一致'));
      expect(
        RegExp(r"'退选成功'").hasMatch(code),
        isFalse,
        reason: '无条件报「退选成功」正是这次事故让用户毫无察觉的原因',
      );
    });

    test('解析器里不许再出现 itemCode = classCode 兜底', () {
      final code = _code(
        'lib/features/ims/course_selection/domain/selection_parsers.dart',
      );
      expect(
        RegExp(r'itemCode\s*=\s*classCode').hasMatch(code),
        isFalse,
        reason: '上课班级 ≠ 退选码；取错就会退掉别门课',
      );
      expect(code, contains('_itemCodeFromLastCell'));
    });

    test('写操作门面：两条写入路径都必须对账', () {
      final code = _code(
        'lib/features/ims/course_selection/data/providers/course_selection_providers.dart',
      );
      expect(code, contains('cancelChecked'));
      expect(code, contains('verifyCancellation('));
      expect(code, contains('submitAndVerify'));
      expect(code, contains('verifySubmission('));
      expect(
        code,
        contains('final after = await repository.fetchResult();'),
        reason: '对账必须基于**重新拉取**的结果，不能拿旧列表自己比自己',
      );
      expect(
        code,
        contains('_readFreshResult'),
        reason: '写前也要重读一次（防在过期列表上操作）',
      );
    });

    test('选课确认弹窗同样有核对闸门', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/course_section_sheet.dart',
      );
      expect(code, contains('Checkbox('));
      expect(code, contains('acknowledged'));
      expect(code, contains('submitAndVerify'));
      expect(code, contains('我已核对'));
    });
  });
}
