/// 答题页 HTML / JSON 解析(无副作用,便于单测)。
library;

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

final _inputTagRe = RegExp(r'<input[^>]*>', caseSensitive: false);
final _idRe = RegExp(r'id\s*=\s*"([^"]*)"', caseSensitive: false);
final _valueRe = RegExp(r'value\s*=\s*"([^"]*)"', caseSensitive: false);
final _guidRe = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _nextChapterRe = RegExp(
  r'/Web/(?:Chapter|Exam)/Index(?:/|\?id=|\?cid=)(' + _guidRe.pattern + r')',
  caseSensitive: false,
);
final _tagRe = RegExp(r'<[^>]+>');
final _scriptRe = RegExp(
  r'<script.*?</script>',
  caseSensitive: false,
  dotAll: true,
);
final _wsRe = RegExp(r'\s+');

/// 登录页「选择版式」里被勾选的 radio(两种属性顺序都覆盖)。
final _themeCheckedRe = RegExp(
  r'''name=["']tid["'][^>]*value=["']([^"']+)["'][^>]*checked'''
  r'''|checked[^>]*name=["']tid["'][^>]*value=["']([^"']+)["']''',
  caseSensitive: false,
);

/// 页面里任意 `tid=<值>`(章节链接等),候选值须是 GUID 才算数。
final _tidAnyRe = RegExp(r'tid=([^"&\s>]+)', caseSensitive: false);

bool isGuid(String s) {
  if (s.length != 36) return false;
  final m = _guidRe.firstMatch(s);
  return m != null && m.group(0) == s;
}

/// 3xx 的 `Location` 是否表示「**本章已通过**」。
///
/// 实测(2026-09-15,已通关账号):前 4 章 `/Web/Exam?cid=` 返回 200 +
/// 「已通过本章节考试」,但**最后一章**通过后没有「下一章」可去,平台改为
/// `302 → /Web/Center/MyGrades`(结算 `JumpWhich == 2` 时也会去
/// `/Web/Center/Lottery`)。对照:答题尚未开放是 `302 → /html/401.html`。
///
/// 二者语义相反,必须区分 —— 早前把任意 3xx 都当成会话失效,导致最后一章
/// 恒被计为未通过,「入馆教育」进度卡一直显示未完成(4/5 章)。
bool tsgxsRedirectIsChapterPassed(String location) {
  final lower = location.toLowerCase();
  return lower.contains('/web/center/mygrades') ||
      lower.contains('/web/center/lottery');
}

/// 从 cblogin 的跳转地址里取**待激活 uid**。
///
/// 首次登录(还没选皮肤)时,tsgxs 会 302 到
/// `/Web/User?success=-2&uid=<uid>`:**uid 只在查询串里,不下发 uid cookie**,
/// 必须再 `POST /Web/User/SelectTheme {uid,tid}` 才算登录完成(见
/// `TsgxsAuthRemoteDataSource._verifyTsgxsLogin`)。无 uid 时返回 null。
String? parseTsgxsPendingUid(String url) {
  final uri = Uri.tryParse(url);
  final uid = uri?.queryParameters['uid'];
  if (uid == null || uid.isEmpty) return null;
  // 模板占位(未解析的变量)不算。
  return isGuid(uid) ? uid : null;
}

/// 从登录页 HTML 解析皮肤(角色)id:优先被勾选的 `input[name=tid]`,
/// 其次页面里任一 `tid=<guid>`;都没有返回 null。
String? parseTsgxsThemeId(String html) {
  final checked = _themeCheckedRe.firstMatch(html);
  final radio = checked?.group(1) ?? checked?.group(2);
  if (radio != null && isGuid(radio)) return radio;
  for (final m in _tidAnyRe.allMatches(html)) {
    final value = m.group(1);
    if (value != null && isGuid(value)) return value;
  }
  return null;
}

/// 提取页面隐藏字段(id → value,同一 id 取首次出现 = 真实值,模板占位在后)。
Map<String, String> tsgxsHiddenFields(String html) {
  final out = <String, String>{};
  for (final m in _inputTagRe.allMatches(html)) {
    final tag = m.group(0)!;
    final id = _idRe.firstMatch(tag)?.group(1);
    if (id == null || id.isEmpty) continue;
    final value = _valueRe.firstMatch(tag)?.group(1) ?? '';
    out.putIfAbsent(id, () => value);
  }
  return out;
}

String _plainText(String html) {
  final t = html
      .replaceAll(_scriptRe, ' ')
      .replaceAll(_tagRe, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(_wsRe, ' ')
      .trim();
  return t;
}

/// 解析 `GET /Web/Exam?cid=<章节id>` 的页面。
TsgxsExamPage parseTsgxsExamPage(String html) {
  final nextChapterId = _nextChapterRe.firstMatch(html)?.group(1);
  if (html.contains('已通过本章节考试')) {
    return TsgxsExamPage(
      passed: true,
      message: '已通过本章节考试',
      nextChapterId: nextChapterId,
    );
  }
  final fields = tsgxsHiddenFields(html);
  final recordId = (fields['examRecordDetailsId'] ?? '').trim();
  final chapterId = (fields['zid'] ?? '').trim();
  final questionIds = (fields['stIds'] ?? '')
      .split(',')
      .map((e) => e.trim())
      .where(isGuid)
      .toList();
  if (!isGuid(recordId) || !isGuid(chapterId) || questionIds.isEmpty) {
    return TsgxsExamPage(passed: false, message: _plainText(html));
  }
  final length =
      int.tryParse((fields['eqLength'] ?? '').trim()) ?? questionIds.length;
  return TsgxsExamPage(
    session: TsgxsExamSession(
      examRecordDetailsId: recordId,
      chapterId: chapterId,
      questionIds: questionIds,
      examinations: int.tryParse((fields['examinations'] ?? '').trim()) ?? 0,
      length: length,
    ),
  );
}

/// 解析 `GET /web/Exam/GetQueOpt` 的 JSON。
TsgxsQuestion parseTsgxsQuestion(Map<String, dynamic> json) {
  final q = _asMap(json['examQuestion']);
  final t = _asMap(json['examQuestionType']);
  final options = _asList(json['examQuestionOptions'])
      .map((e) => TsgxsExamOption.fromJson(_asMap(e)))
      .where((o) => o.id.isNotEmpty)
      .toList();
  return TsgxsQuestion(
    id: q['id']?.toString() ?? '',
    chapterId: q['cid']?.toString() ?? '',
    kind: TsgxsQuestionKind.fromId(q['tid']?.toString()),
    kindName: t['name']?.toString() ?? '',
    content: q['content']?.toString() ?? '',
    options: options,
    answerTip: q['answertip']?.toString() ?? '',
  );
}

/// 解析 `POST /web/Exam/GetAnswer` 的 JSON。
TsgxsAnswerResult parseTsgxsAnswerResult(Map<String, dynamic> json) {
  final q = _asMap(json['examQuestion']);
  return TsgxsAnswerResult(
    success: _asInt(json['Success']),
    isCorrect: json['isCorrect'] == true,
    isRestart: json['isRestart'] == true,
    correctRaw: q['answer']?.toString() ?? '',
    analysis: q['answeranalysis']?.toString() ?? '',
    myProps: _asList(json['myPropsInfos'])
        .map((e) => TsgxsExamProp.fromJson(_asMap(e)))
        .where((p) => p.id.isNotEmpty)
        .toList(),
    nextChapterId: _guidOrNull(json['NCid']?.toString()),
    message: json['Msg']?.toString() ?? '',
    jumpWhich: _asInt(json['JumpWhich']),
  );
}

/// 解析 `POST /web/exam/GetGameRole` 的 JSON。
TsgxsExamFinishResult parseTsgxsFinishResult(Map<String, dynamic> json) {
  return TsgxsExamFinishResult(
    success: _asInt(json['Success']),
    nextChapterId: _guidOrNull(json['NCid']?.toString()),
    examinations: _asInt(json['Examinations']),
    props: _asList(json['PropsInfos'])
        .map((e) => TsgxsExamProp.fromJson(_asMap(e)))
        .where((p) => p.id.isNotEmpty)
        .toList(),
    message: json['Msg']?.toString() ?? '',
    jumpWhich: _asInt(json['JumpWhich']),
    chapterId: _guidOrNull(json['zid']?.toString()),
  );
}

Map<String, dynamic> _asMap(Object? v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

List<dynamic> _asList(Object? v) => v is List ? v : const [];

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

String? _guidOrNull(String? s) {
  final v = (s ?? '').trim();
  if (v.isEmpty || v == tsgxsNilGuid) return null;
  return isGuid(v) ? v : null;
}
