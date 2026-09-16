/// 教务 `xh`（学号参数）口径守卫 —— **2026-09-15 二次核实后的结论**。
///
/// 学籍 XML 三条标识（`POST /STU_BaseInfoAction.do`，1357 B，单条 `<info>`）：
/// - `<yhxh>2000000000</yhxh>` = `StudentInfo.userId` = **用户号 / 统一身份认证号**（CAS 登录名）；
/// - `<xh>201600035929</xh>`   = `StudentInfo.serialNo` = **教务请求里的 `xh` 就用它**；
/// - `<bz>0000000</bz>`        = `StudentInfo.studentId` = 体测 `stuNum`。
///
/// 为什么是 `<xh>` 而不是 `<yhxh>`（都是教务自己的产物）：
/// ① 课表页 `/student/xkjg.wdkb.jsp` 的隐藏框是**服务端渲染**的
///    `<input type="hidden" id="xh" name="xh" value="201600035929"/>`；
/// ② 选课页的 `xh` 由 `getWsxkTimeRange.action` 响应的 `xh` 字段填充（实测同值），
///    选课结果页 `wsxk.zxjg.jsp` 里服务端渲染的也是它；
/// ③ **选课写操作会校验**：把 `xh` 传成 `<yhxh>` 提交 → 教务回
///    「当前选课操作的用户不是选课学生本人！」（2026-09-15 用户亲历）。
///
/// 2026-09-14 曾据「入学以来页顶部印『学号：2000000000』」把口径改成 `<yhxh>`（并加了
/// `StudentInfo.jwStudentId` getter）—— **那是错的**，只读端点对 `xh` 不敏感所以没当场暴露，
/// 直到用户点「确认选课」才炸。本文件把那次的结论连同 getter 一起钉死，别再复活。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';

String _read(String path) => File(path).readAsStringSync();

/// 去掉注释后的源码（注释里允许提到被废弃的旧名字，只禁**代码里**出现）。
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

/// `lib/` 下的全部 dart 源码（递归）。
List<File> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('SelectionSession.xh（教务给的值）', () {
    test('真实响应里带 xh → 解出来', () {
      final session = SelectionSession.fromEnvelope(
        tryJsonMap(
          '{"status":"200","message":"操作成功!","result":"{\\"xn\\":\\"2026\\",'
          '\\"xqM\\":\\"0\\",\\"xh\\":\\"201600035929\\"}"}',
        )!,
        xktype: 2,
      );
      expect(session.xh, '201600035929');
    });

    test('undefined / 缺失 → 空串（调用方回退学籍 serialNo）', () {
      for (final raw in <String>[
        '{"status":"200","result":"{\\"xn\\":\\"2026\\"}"}',
        '{"status":"200","result":"{\\"xh\\":\\"undefined\\"}"}',
      ]) {
        final session = SelectionSession.fromEnvelope(
          tryJsonMap(raw)!,
          xktype: 2,
        );
        expect(session.xh, '');
      }
    });
  });

  group('源码口径守卫', () {
    const providerPath =
        'lib/features/ims/course_selection/data/providers/course_selection_providers.dart';

    test('选课模块的 studentId：优先教务 xh，回退学籍 serialNo', () {
      final source = _code(providerPath);
      expect(source.contains('session.xh.isNotEmpty'), isTrue);
      expect(source.contains('info?.serialNo'), isTrue);
      // 绝不能再用「用户号」当教务 xh。
      expect(source.contains('jwStudentId'), isFalse);
    });

    test('课表页 / 实时课堂页的 xh 用 serialNo', () {
      for (final path in <String>[
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
        'lib/features/ims/schedule/presentation/live_class_screen.dart',
      ]) {
        final source = _code(path);
        expect(source.contains('serialNo'), isTrue, reason: '$path 应传 serialNo');
        expect(source.contains('jwStudentId'), isFalse, reason: '$path 不该出现 jwStudentId');
      }
    });

    test('错误口径的 jwStudentId getter 不许复活', () {
      final offenders = <String>[];
      for (final file in _libSources()) {
        if (_code(file.path).contains('jwStudentId')) offenders.add(file.path);
      }
      expect(offenders, isEmpty);
    });
  });
}
