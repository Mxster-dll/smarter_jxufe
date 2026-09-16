/// 写操作（选课 / 退选）之后的**对账口径** —— 2026-09-15 退选事故后新增。
///
/// **事故经过**：用户在「选课结果」里点某一行的小「退选」按钮，教务实际退掉的是
/// **另一门课**（计算机组成原理，4 学分），而 App 只回了一句「退选成功」——
/// 提交之后**没有任何核对**，用户直到事后才发现，已错过当场改选的时机。
///
/// 取证结论（2026-09-15，实时抓页面）：
/// - 教务页面自己的退选实现是 `CancelData()`：`items += rows[ind].cells[l-1].innerHTML + "|"`
///   （**末格**），我们提交的 `itemCode` 与它**逐行一致** → 「发错码」不是成因；
/// - 每行那个小按钮上下紧贴、长相一致，误触相邻行 + 顺手确认弹窗是现实成因；
/// - 但真正让事故**无法挽回**的是：写入之后没有任何对账。
///
/// 所以本文件提供两件事（纯函数，可单测）：
/// 1. [verifyCancellation]：刷新后的选课结果 vs 请求退的课 → 正常 / 没执行 / **退错了**；
/// 2. [verifySubmission]：刷新后的选课结果里到底有没有那门课（抓「教务说成功但没选上」）。
library;

import 'package:smarter_jxufe/features/ims/course_selection/domain/selection_models.dart';

/// 退选对账结论。
enum SelectionCancelVerdict {
  /// 请求退的那门课消失了，且没有别的课跟着消失 —— 正常。
  confirmed,

  /// 请求的课**仍在**选课结果里（教务没执行这次退选）。
  requestedStillPresent,

  /// 退掉了别的课（含「请求的课 + 别的课一起消失」）。
  wrongCourseDropped,

  /// 拿不到「请求的那门课」或刷新失败，判不出来。
  unverifiable,
}

/// 退选对账结果。
class SelectionCancelCheck {
  const SelectionCancelCheck({
    required this.verdict,
    this.requestedName = '',
    this.droppedNames = const [],
    this.extraDroppedNames = const [],
  });

  final SelectionCancelVerdict verdict;

  /// 请求退的那门课的名字（判得出时）。
  final String requestedName;

  /// 本次实际消失的课（按选课结果里的顺序）。
  final List<String> droppedNames;

  /// 除请求那门之外**还**消失的课 —— 非空即「退错了」。
  final List<String> extraDroppedNames;

  /// 一切正常。
  bool get ok => verdict == SelectionCancelVerdict.confirmed;

  /// 需要立刻让用户知道（红字弹窗级）。
  bool get alarming => verdict == SelectionCancelVerdict.wrongCourseDropped;

  /// 给用户看的一句话（SnackBar / 弹窗正文）。
  String get message => switch (verdict) {
    SelectionCancelVerdict.confirmed => '已退选《$requestedName》，教务结果已核对一致',
    SelectionCancelVerdict.requestedStillPresent =>
      '教务没有执行这次退选：《$requestedName》仍在选课结果里',
    SelectionCancelVerdict.wrongCourseDropped =>
      extraDroppedNames.isEmpty
          ? '退选结果与请求不一致：你要退的是《$requestedName》，'
                '教务实际退掉的是《${droppedNames.join('》《')}》'
          : '退选结果与请求不一致：你要退的是《$requestedName》，'
                '教务这次共退掉 ${droppedNames.length} 门'
                '（《${droppedNames.join('》《')}》），'
                '其中《${extraDroppedNames.join('》《')}》不是你请求的',
    SelectionCancelVerdict.unverifiable => '退选请求已提交，但无法核对结果',
  };

  /// 对账用的短标签（写进日志 / 后续核对）。
  @override
  String toString() =>
      'SelectionCancelCheck(${verdict.name}, requested=$requestedName, '
      'dropped=$droppedNames, extra=$extraDroppedNames)';
}

/// 退选对账：把「请求退的课」与「刷新后实际消失的课」比一次。
///
/// 传 [before] 必须是**发出退选请求之前那一份**选课结果（界面手上的那份），
/// [after] 必须是请求成功之后**重新拉取**的结果；两者都按 `itemCode` 比对
/// （`itemCode` = 教务页末格，也是提交给教务的 `items` 值）。
SelectionCancelCheck verifyCancellation({
  required SelectionResult before,
  required SelectionResult after,
  required String requestedItemCode,
}) {
  if (requestedItemCode.isEmpty) {
    return const SelectionCancelCheck(
      verdict: SelectionCancelVerdict.unverifiable,
    );
  }
  final requested = before.courses
      .where((c) => c.itemCode == requestedItemCode)
      .toList();
  if (requested.isEmpty) {
    return const SelectionCancelCheck(
      verdict: SelectionCancelVerdict.unverifiable,
    );
  }
  final requestedName = requested.first.name;
  final afterCodes = after.courses.map((c) => c.itemCode).toSet();
  final dropped = before.courses
      .where((c) => !afterCodes.contains(c.itemCode))
      .toList();
  final extra = dropped.where((c) => c.itemCode != requestedItemCode).toList();

  // ⚠ 顺序要紧：**只要消失了「不是你请求的课」，就是最严重的结论**——
  // 哪怕请求的那门也一起消失了（「点 A 退掉 A 和 B」同样必须报警），
  // 甚至请求的那门还在、却顺手退掉了别的课（那更是退错）。
  if (extra.isNotEmpty) {
    return SelectionCancelCheck(
      verdict: SelectionCancelVerdict.wrongCourseDropped,
      requestedName: requestedName,
      droppedNames: dropped.map((c) => c.name).toList(),
      extraDroppedNames: extra.map((c) => c.name).toList(),
    );
  }
  if (afterCodes.contains(requestedItemCode)) {
    return SelectionCancelCheck(
      verdict: SelectionCancelVerdict.requestedStillPresent,
      requestedName: requestedName,
    );
  }
  return SelectionCancelCheck(
    verdict: SelectionCancelVerdict.confirmed,
    requestedName: requestedName,
    droppedNames: dropped.map((c) => c.name).toList(),
  );
}

/// 选课（提交）对账结论。
enum SelectionSubmitVerdict {
  /// 刷新后的选课结果里确实有这门课。
  confirmed,

  /// 教务回了成功，但选课结果里**没有**这门课。
  missing,

  /// 课程代码为空 / 刷新失败，判不出来。
  unverifiable,
}

/// 选课对账结果。
class SelectionSubmitCheck {
  const SelectionSubmitCheck({required this.verdict, this.courseName = ''});

  final SelectionSubmitVerdict verdict;
  final String courseName;

  bool get ok => verdict == SelectionSubmitVerdict.confirmed;

  /// 报成功了却没选上 —— 需要提醒用户去教务确认。
  bool get alarming => verdict == SelectionSubmitVerdict.missing;

  String get message => switch (verdict) {
    SelectionSubmitVerdict.confirmed => '已选上《$courseName》，教务结果已核对一致',
    SelectionSubmitVerdict.missing =>
      '教务回了成功，但选课结果里没有《$courseName》——请到教务确认是否真的选上',
    SelectionSubmitVerdict.unverifiable => '选课请求已提交，但无法核对结果',
  };
}

// ============================================================ 写响应解析（2026-09-15 二轮）

/// 解析写操作的响应信封 —— **教务的写端点不返回裸 JSON**。
///
/// 实测 `POST /STU_ElectCourseResultAction.do?hidOption=cancel`（2026-09-15，活会话）：
/// HTTP 200 / **109 字节** / `content-type: text/html;charset=UTF-8`，正文是 iframe 回调页：
///
/// ```html
/// <script language="javascript">parent._callBack("{\"status\":\"200\",\"message\":\"操作成功!\"}")</script>
/// ```
///
/// 旧实现把整页丢给 `jsonDecode` → 恒为 null → 报「网络异常，请稍后重试」，
/// **而教务其实已经执行了退选**（用户实测：App 说网络异常、教务里课已经没了、
/// 界面还列着那门课 → 用户很可能在同一行再点一次「退选」，这正是上次事故的温床）。
///
/// ⚠ 该端点是 **fire-and-forget**：`items=` 为空、以及绝不存在的码
/// `0000000000-999|` 都回「操作成功!」⇒ **响应零信息量**，写入是否生效只能靠
/// 重新读选课结果页（[verifyCancellation]）判断。
///
/// 解析顺序：① 整串当 JSON；② 取 `_callBack(...)` 的第一个实参、反转义；③ 兜底扫第一个配平的 `{}`。
Map<String, dynamic>? parseWriteEnvelope(String body) {
  final direct = tryJsonMap(body);
  if (direct != null) return direct;
  final argument = _firstCallbackArgument(body);
  if (argument != null) {
    for (final candidate in [_unescapeJsString(argument), argument]) {
      final parsed = _tryLooseJson(candidate);
      if (parsed != null) return parsed;
    }
  }
  final object = _firstJsonObject(body);
  return object == null ? null : _tryLooseJson(object);
}

/// 先按原样解；解不出再剥掉**包裹在外层的引号**
/// （`&quot;{&quot;status&quot;:&quot;200&quot;}&quot;` 反转义后 = `"{"status":"200"}"`）。
Map<String, dynamic>? _tryLooseJson(String candidate) {
  final direct = tryJsonMap(candidate);
  if (direct != null) return direct;
  final trimmed = candidate.trim();
  if (trimmed.length < 2) return null;
  final first = trimmed[0];
  final last = trimmed[trimmed.length - 1];
  if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
    return tryJsonMap(trimmed.substring(1, trimmed.length - 1));
  }
  return null;
}

/// 取 `_callBack(` / `_callBack (` 的第一个实参原文（去掉外层引号），找不到返回 null。
String? _firstCallbackArgument(String body) {
  final marker = RegExp('_call[Bb]ack\\s*\\(').firstMatch(body);
  if (marker == null) return null;
  var i = marker.end;
  while (i < body.length && _isSpace(body.codeUnitAt(i))) {
    i++;
  }
  if (i >= body.length) return null;
  final quote = body[i];
  if (quote == '"' || quote == "'") {
    final buffer = StringBuffer();
    i++;
    while (i < body.length) {
      final ch = body[i];
      if (ch == r'\' && i + 1 < body.length) {
        buffer.write(ch);
        buffer.write(body[i + 1]);
        i += 2;
        continue;
      }
      if (ch == quote) break;
      buffer.write(ch);
      i++;
    }
    return buffer.toString();
  }
  // 无引号形态：扫到配平的右括号。
  final start = i;
  var depth = 0;
  while (i < body.length) {
    final ch = body[i];
    if (ch == '(' || ch == '{' || ch == '[') {
      depth++;
    } else if (ch == ')' || ch == '}' || ch == ']') {
      if (depth == 0) break;
      depth--;
    }
    i++;
  }
  return body.substring(start, i);
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x0A || codeUnit == 0x0D;

/// JS/JSON 字符串字面量反转义 + HTML 实体还原（`\"` → `"`）。
String _unescapeJsString(String raw) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch == r'\' && i + 1 < raw.length) {
      final next = raw[i + 1];
      if (next == 'u' && i + 5 < raw.length) {
        final code = int.tryParse(raw.substring(i + 2, i + 6), radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          i += 6;
          continue;
        }
      }
      const mapped = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f'};
      buffer.write(mapped[next] ?? next);
      i += 2;
      continue;
    }
    buffer.write(ch);
    i++;
  }
  return _unescapeEntities(buffer.toString());
}

String _unescapeEntities(String text) {
  if (!text.contains('&')) return text;
  return text
      .replaceAll('&quot;', '"')
      .replaceAll('&#34;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// 兜底：扫出正文里第一个花括号配平的 JSON 对象。
String? _firstJsonObject(String body) {
  final start = body.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < body.length; i++) {
    final ch = body[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return body.substring(start, i + 1);
    }
  }
  return null;
}

// ================================================== 写前核对（防在过期列表上操作）

/// 写前核对的结论。
enum SelectionFreshTargetVerdict {
  /// 目标码在**最新**列表里存在、唯一，且课程名对得上。
  ok,

  /// 最新列表里已经没有这个码（多半刚才已经退掉了 / 列表过期）。
  missing,

  /// 最新列表里有多行共用同一个码 —— 提交上去可能命中别门课，必须拦。
  duplicated,

  /// 最新列表里该码对应的是**另一门课** —— 这就是「再点一次会退错课」的直接形态。
  nameMismatch,
}

/// 写前核对结果。
class SelectionFreshTargetCheck {
  const SelectionFreshTargetCheck({
    required this.verdict,
    this.course,
    this.message = '',
  });

  final SelectionFreshTargetVerdict verdict;

  /// 最新列表里那一行（`ok` 时非空）—— 确认弹窗应当展示**这一份**数据。
  final SelectedCourse? course;

  final String message;

  bool get ok => verdict == SelectionFreshTargetVerdict.ok;
}

/// 写前核对：拿**刚刚重读**的选课结果，确认这次退选要提交的码仍然唯一对应那一门课。
///
/// 为什么必须有这一步：教务退选端点是 fire-and-forget（响应永远是「操作成功!」），
/// 在**过期列表**上提交一个已经退掉的码，界面既不知道会不会命中别的课、也无从回滚。
/// 传进来的 [courseName] 是用户在界面上看到的那一行，与最新结果比对不上就拦下。
SelectionFreshTargetCheck checkFreshCancelTarget({
  required SelectionResult fresh,
  required String itemCode,
  required String courseName,
}) {
  final code = itemCode.trim();
  if (code.isEmpty) {
    return const SelectionFreshTargetCheck(
      verdict: SelectionFreshTargetVerdict.missing,
      message: '这一行没有可用的退选码，已阻止退选并刷新列表（请到教务网页版处理）',
    );
  }
  final matches = fresh.courses.where((c) => c.itemCode == code).toList();
  if (matches.isEmpty) {
    return SelectionFreshTargetCheck(
      verdict: SelectionFreshTargetVerdict.missing,
      message:
          '《$courseName》已不在最新选课结果里（可能刚才已经退掉了），'
          '已阻止退选并为你刷新列表',
    );
  }
  if (matches.length > 1) {
    return SelectionFreshTargetCheck(
      verdict: SelectionFreshTargetVerdict.duplicated,
      message: '最新选课结果里有 ${matches.length} 行共用同一个退选码（$code），'
          '无法确定要退哪一门，已阻止退选，请到教务网页版处理',
    );
  }
  final target = matches.single;
  if (courseName.trim().isNotEmpty && !_sameCourseName(target.name, courseName)) {
    return SelectionFreshTargetCheck(
      verdict: SelectionFreshTargetVerdict.nameMismatch,
      course: target,
      message: '最新选课结果里退选码 $code 对应的是《${target.name}》，'
          '不是你在界面上看到的《$courseName》——列表已经过期，'
          '已阻止本次退选并刷新列表，请重新确认后再操作',
    );
  }
  return SelectionFreshTargetCheck(
    verdict: SelectionFreshTargetVerdict.ok,
    course: target,
  );
}

bool _sameCourseName(String a, String b) =>
    a.replaceAll(RegExp(r'\s+'), '') == b.replaceAll(RegExp(r'\s+'), '');

// ============================================ 退选结局（写前核对 → 写入 → 写后对账）

/// 退选①的准备结果（**只读**，不写入）：给确认弹窗提供新鲜数据。
class SelectionCancelPreparation {
  const SelectionCancelPreparation({
    required this.fresh,
    required this.message,
    this.readFailed = false,
  });

  /// 写前核对（[readFailed] 时为 null）。
  final SelectionFreshTargetCheck? fresh;
  final String message;
  final bool readFailed;

  bool get ok => fresh?.ok ?? false;

  /// 最新列表里那一行 —— 确认弹窗用它，而不是界面手上那份可能过期的数据。
  SelectedCourse? get course => fresh?.course;
}

/// 退选②的完整结局。
///
/// 关键语义：**`write` 只是「教务收下了没有」，不是「退掉了没有」**。
/// 唯一可信的是 [check]（重读选课结果页后的对账）。
class SelectionCancelOutcome {
  const SelectionCancelOutcome({
    required this.message,
    this.fresh,
    this.write,
    this.check,
    this.refreshed = false,
    this.freshReadFailed = false,
    this.writeAttempted = false,
  });

  /// 界面直接播报的一句话（口径集中在 [selectionCancelMessage]）。
  final String message;

  /// 写前核对（null = 读不到最新列表）。
  final SelectionFreshTargetCheck? fresh;

  /// 教务对写入请求的应答（null = 没提交或提交时抛错）。
  final SelectionWriteResult? write;

  /// 写后对账（null = 没能重读结果页）。
  final SelectionCancelCheck? check;

  /// 写后是否成功重读了选课结果页（界面库存是否已刷新）。
  final bool refreshed;

  /// 写前重读失败 → 根本没提交。
  final bool freshReadFailed;

  /// 是否真的发出了退选请求。
  final bool writeAttempted;

  /// 被写前核对拦下，**没有提交任何写入**。
  bool get blocked => !writeAttempted && !freshReadFailed;

  /// 提交了但核对不了 —— 「结果未知」，必须让用户去教务确认。
  bool get unknown => writeAttempted && check == null;

  /// 已确认生效（对账一致）。
  bool get confirmed => check?.ok ?? false;

  /// 退错了（需要红字弹窗级告警）。
  bool get alarming => check?.alarming ?? false;
}

/// 退选结局 → 给用户看的一句话。
///
/// **绝不出现裸的「退选成功」**：教务该端点对空 `items` 与不存在的码都回「操作成功!」，
/// 只有「重读选课结果页并对上账」才算数。
String selectionCancelMessage({
  required SelectionFreshTargetCheck? fresh,
  required SelectionWriteResult? write,
  required SelectionCancelCheck? check,
  required bool refreshed,
  required bool freshReadFailed,
  required bool writeAttempted,
}) {
  const refreshHint = '（界面列表未能刷新，请下拉刷新或重进本页）';
  if (freshReadFailed) {
    return '无法读取最新选课结果（网络或教务会话异常），**已阻止本次退选**，'
        '请刷新后重试';
  }
  if (!writeAttempted) {
    return fresh?.message.isNotEmpty == true
        ? fresh!.message
        : '已阻止本次退选，请刷新后重试';
  }
  if (check != null) {
    return refreshed ? check.message : '${check.message}$refreshHint';
  }
  final reply = write?.message ?? '';
  final suffix = refreshed ? '' : refreshHint;
  if (write != null && write.ok) {
    return '退选请求已提交（教务回「$reply」），但没能重读选课结果核对 —— '
        '**无法确认是否真的退掉**，请到教务网页版确认$suffix';
  }
  return '退选请求未获教务接受（${reply.isEmpty ? '无返回' : reply}），'
      '但也没能重读结果核对，请到教务网页版确认$suffix';
}

/// 选课对账：刷新后的选课结果里有没有这门课（按 `courseCode` 比）。
///
/// 刻意**不判「新增」**：改选（退旧班 + 选新班）时同一门课可能本来就在结果里，
/// 此时只看「在不在」；真正要抓的是「教务说成功、结果里却没有」这一侧。
SelectionSubmitCheck verifySubmission({
  required SelectionResult after,
  required String courseCode,
  required String courseName,
}) {
  final code = courseCode.trim();
  if (code.isEmpty) {
    return SelectionSubmitCheck(
      verdict: SelectionSubmitVerdict.unverifiable,
      courseName: courseName,
    );
  }
  final present = after.courses.any((c) => c.courseCode.trim() == code);
  return SelectionSubmitCheck(
    verdict: present
        ? SelectionSubmitVerdict.confirmed
        : SelectionSubmitVerdict.missing,
    courseName: courseName,
  );
}
