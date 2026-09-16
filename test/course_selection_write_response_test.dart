/// 退选写入「结果未知却报成功 / 报了网络异常其实已生效」的守卫（2026-09-15 二轮）。
///
/// 用户实测：在 App 里点退选 → 提示「网络异常，请稍后重试」；回教务网页看，
/// **课已经退掉了**；而 App 的列表里还留着那门课 → 用户很可能在同一行再点一次「退选」，
/// 这正是 09-15 那次「点 A 退掉 B」事故的温床。
///
/// 根因（活会话实测）：
/// - `POST /STU_ElectCourseResultAction.do?hidOption=cancel` 返回的是 **iframe 回调页**
///   （HTTP 200 / 109 字节 / `text/html;charset=UTF-8`），不是裸 JSON：
///   `<script language="javascript">parent._callBack("{\"status\":\"200\",\"message\":\"操作成功!\"}")</script>`
///   → 旧代码 `tryJsonMap(整页)` 恒 null → 误判 `networkFailure`（=「网络异常，请稍后重试」）；
/// - 该端点还是 **fire-and-forget**：`items` 为空、以及绝不存在的码
///   `0000000000-999|` **都回「操作成功!」** → 应答零信息量，只能靠重读选课结果页判定；
/// - `cancelAndVerify` 在 `!write.ok` 时早退，跳过了 `_invalidateAfterWrite()` → 列表停在过期状态。
///
/// 本文件钉住：宽容解析 + 写前核对（四态）+ 结局播报 + 三处源码守卫。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';
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

/// **实测原样**（2026-09-15，活会话，109 字节，`text/html;charset=UTF-8`）。
const String _realCancelBody =
    '<script language="javascript">parent._callBack('
    '"{\\"status\\":\\"200\\",\\"message\\":\\"操作成功!\\"}"'
    ')</script>';

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
  group('parseWriteEnvelope：教务写响应是 iframe 回调页', () {
    test('实测 109 字节原样报文能解出 status=200 / 操作成功!', () {
      final envelope = parseWriteEnvelope(_realCancelBody);
      expect(envelope, isNotNull);
      expect(envelope!['status'], '200');
      expect(envelope['message'], '操作成功!');
      // 与数据源的实际用法串起来：不能再是 networkFailure。
      final result = SelectionWriteResult.fromEnvelope(envelope);
      expect(result.ok, isTrue);
      expect(result.message, '操作成功!');
    });

    test('未转义形态（HTML 实体 &quot;）同样解得开', () {
      final body =
          '<script>parent._callBack(&quot;{&quot;status&quot;:&quot;400&quot;,'
          '&quot;message&quot;:&quot;不在选课时间内&quot;}&quot;)</script>';
      final envelope = parseWriteEnvelope(body);
      expect(envelope, isNotNull);
      expect(envelope!['status'], '400');
      expect(envelope['message'], '不在选课时间内');
    });

    test('单引号实参 / 无引号对象 / 裸 JSON 都能解', () {
      expect(
        parseWriteEnvelope(
          "<script>parent._callBack('{\"status\":\"200\",\"message\":\"ok\"}')</script>",
        )!['message'],
        'ok',
      );
      expect(
        parseWriteEnvelope(
          '<script>parent._callBack({"status":"200","message":"ok"})</script>',
        )!['status'],
        '200',
      );
      expect(
        parseWriteEnvelope('{"status":"200","message":"操作成功!"}')!['message'],
        '操作成功!',
      );
    });

    test('回调外面还包着别的 HTML 时，兜底扫第一个配平的对象', () {
      const body =
          '<html><body><div>处理中…</div>'
          '{"status":"200","message":"操作成功!"}'
          '<script>window.close()</script></body></html>';
      expect(parseWriteEnvelope(body)!['message'], '操作成功!');
    });

    test('真正的垃圾 / 空体 / 无 JSON 的错误页 → null（照旧算失败）', () {
      expect(parseWriteEnvelope(''), isNull);
      expect(parseWriteEnvelope('<html><body>404 Not Found</body></html>'), isNull);
      expect(parseWriteEnvelope('操作成功'), isNull);
      expect(
        parseWriteEnvelope(
          "<script>alert('温馨提示：凭证已失效，请重新登录!');</script>",
        ),
        isNull,
      );
    });

    test('消息里带引号/中文也不截断', () {
      const body =
          r'<script>parent._callBack("{\"status\":\"400\",\"message\":\"课程\\\"计算机网络\\\"已选\"}")</script>';
      final envelope = parseWriteEnvelope(body);
      expect(envelope, isNotNull);
      expect(envelope!['status'], '400');
      expect(envelope['message'], '课程"计算机网络"已选');
    });
  });

  group('checkFreshCancelTarget：写前核对四态', () {
    final network = _course('计算机网络', '1014300174', itemCode: '1014300174-008');
    final compose = _course(
      '计算机组成原理',
      '1014300184',
      itemCode: '1014300184-004',
    );

    test('码在、唯一、课名对得上 → ok，并带回最新那一行', () {
      final check = checkFreshCancelTarget(
        fresh: _result([network, compose]),
        itemCode: '1014300184-004',
        courseName: '计算机组成原理',
      );
      expect(check.verdict, SelectionFreshTargetVerdict.ok);
      expect(check.ok, isTrue);
      expect(check.course?.courseCode, '1014300184');
      expect(check.message, isEmpty);
    });

    test('码已不在最新列表（刚才已退掉）→ missing 且拦下', () {
      final check = checkFreshCancelTarget(
        fresh: _result([network]),
        itemCode: '1014300184-004',
        courseName: '计算机组成原理',
      );
      expect(check.verdict, SelectionFreshTargetVerdict.missing);
      expect(check.ok, isFalse);
      expect(check.message, contains('已不在最新选课结果里'));
      expect(check.message, contains('已阻止退选'));
    });

    test('同码多行 → duplicated（提交上去可能命中别门课）', () {
      final check = checkFreshCancelTarget(
        fresh: _result([
          compose,
          _course('计算机组成原理(重修)', '1014300184', itemCode: '1014300184-004'),
        ]),
        itemCode: '1014300184-004',
        courseName: '计算机组成原理',
      );
      expect(check.verdict, SelectionFreshTargetVerdict.duplicated);
      expect(check.message, contains('共用同一个退选码'));
    });

    test('码对应的课名不是用户看到的那门 → nameMismatch（「再点会退错课」的直接防线）', () {
      final check = checkFreshCancelTarget(
        fresh: _result([network, compose]),
        itemCode: '1014300184-004',
        courseName: '计算机网络',
      );
      expect(check.verdict, SelectionFreshTargetVerdict.nameMismatch);
      expect(check.ok, isFalse);
      expect(check.message, contains('计算机组成原理'));
      expect(check.message, contains('列表已经过期'));
      expect(check.message, contains('已阻止本次退选'));
    });

    test('空白差异不算不一致；空 itemCode 一律拦下', () {
      final check = checkFreshCancelTarget(
        fresh: _result([_course('计算机 组成原理', '1014300184', itemCode: 'X-1')]),
        itemCode: 'X-1',
        courseName: '计算机组成原理',
      );
      expect(check.verdict, SelectionFreshTargetVerdict.ok);
      expect(
        checkFreshCancelTarget(
          fresh: _result([network]),
          itemCode: '   ',
          courseName: '计算机网络',
        ).verdict,
        SelectionFreshTargetVerdict.missing,
      );
    });
  });

  group('selectionCancelMessage：绝不谎报成功', () {
    SelectionCancelCheck checkOf(SelectionCancelVerdict verdict) =>
        SelectionCancelCheck(
          verdict: verdict,
          requestedName: '计算机组成原理',
          droppedNames: const ['计算机组成原理'],
          extraDroppedNames: verdict == SelectionCancelVerdict.wrongCourseDropped
              ? const ['计算机网络']
              : const [],
        );

    test('写前读不到列表 → 明确说「已阻止本次退选」', () {
      final message = selectionCancelMessage(
        fresh: null,
        write: null,
        check: null,
        refreshed: false,
        freshReadFailed: true,
        writeAttempted: false,
      );
      expect(message, contains('已阻止本次退选'));
      expect(message, isNot(contains('网络异常')));
    });

    test('对账一致 → 照抄对账文案', () {
      final message = selectionCancelMessage(
        fresh: null,
        write: const SelectionWriteResult(ok: true, message: '操作成功!'),
        check: checkOf(SelectionCancelVerdict.confirmed),
        refreshed: true,
        freshReadFailed: false,
        writeAttempted: true,
      );
      expect(message, contains('已退选《计算机组成原理》'));
      expect(message, contains('核对一致'));
    });

    test('退错了 → 播报里点出被误退的课', () {
      final message = selectionCancelMessage(
        fresh: null,
        write: const SelectionWriteResult(ok: true, message: '操作成功!'),
        check: checkOf(SelectionCancelVerdict.wrongCourseDropped),
        refreshed: true,
        freshReadFailed: false,
        writeAttempted: true,
      );
      expect(message, contains('计算机网络'));
      expect(message, contains('不是你请求的'));
    });

    test('教务回「操作成功!」但没读到结果 → 必须是「无法确认」而不是成功', () {
      final message = selectionCancelMessage(
        fresh: null,
        write: const SelectionWriteResult(ok: true, message: '操作成功!'),
        check: null,
        refreshed: false,
        freshReadFailed: false,
        writeAttempted: true,
      );
      expect(message, contains('无法确认是否真的退掉'));
      expect(message, contains('教务网页版确认'));
      expect(message, contains('界面列表未能刷新'));
      expect(message, isNot(contains('退选成功')));
    });

    test('对账失败但列表已刷新 → 不再附加刷新提示', () {
      final message = selectionCancelMessage(
        fresh: null,
        write: const SelectionWriteResult(ok: true, message: '操作成功!'),
        check: null,
        refreshed: true,
        freshReadFailed: false,
        writeAttempted: true,
      );
      expect(message, isNot(contains('界面列表未能刷新')));
    });
  });

  group('源码守卫', () {
    test('数据源两条写路径都必须用宽容解析（不能再裸 tryJsonMap 整页）', () {
      final code = _code(
        'lib/features/ims/course_selection/data/datasources/course_selection_remote_datasource.dart',
      );
      expect(
        RegExp(r'tryJsonMap\(_decodeEnvelopeText').hasMatch(code),
        isFalse,
        reason: '教务写响应是 iframe 回调页，裸 jsonDecode 会把成功误判成「网络异常」',
      );
      expect(
        'parseWriteEnvelope(_decodeEnvelopeText'.allMatches(code).length,
        2,
        reason: 'cancelSelection 与 submitSelection 都要走 parseWriteEnvelope',
      );
    });

    test('写操作门面：不许在写入失败时早退（那会跳过刷新）', () {
      final code = _code(
        'lib/features/ims/course_selection/data/providers/course_selection_providers.dart',
      );
      expect(
        RegExp(r'if\s*\(!write\.ok\)\s*return').hasMatch(code),
        isFalse,
        reason: '早退会让界面停在过期列表上 —— 用户再点一次就可能退错课',
      );
      expect(code, contains('prepareCancel'));
      expect(code, contains('cancelChecked'));
      expect(code, contains('writeAttempted: true'));
    });

    test('界面：确认弹窗先重读核对再提交，且用新鲜数据渲染', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/selection_result_view.dart',
      );
      expect(code, contains('prepareCancel'));
      expect(code, contains('final target = prep.course ?? course;'));
      expect(code, contains('cancelChecked'));
      expect(
        RegExp(r'cancelAndVerify').hasMatch(code),
        isFalse,
        reason: '旧方法在 !write.ok 时早退，已被 cancelChecked 取代',
      );
      expect(
        code,
        contains('以上信息取自刚刚重新读取的选课结果。'),
        reason: '要让用户知道弹窗里这门课是刚核对过的，不是过期列表里那份',
      );
    });

    test('选课提交同样以对账为准，没对上账不许说成功', () {
      final code = _code(
        'lib/features/ims/course_selection/presentation/course_section_sheet.dart',
      );
      expect(code, contains('check.message'));
      expect(
        code,
        contains('但没能重读选课结果核对'),
        reason: '「教务说成功」不等于选上，必须如实说明无法核对',
      );
      expect(
        RegExp(r"if\s*\(write\.ok\s*&&\s*mounted\)").hasMatch(code),
        isFalse,
        reason: '只有对账确认后才允许关弹窗',
      );
    });
  });
}
