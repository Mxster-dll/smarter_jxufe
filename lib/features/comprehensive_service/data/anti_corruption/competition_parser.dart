/// 第二课堂「学科竞赛」页面的 HTML / JSON 解析（防腐层）。
///
/// 全部按官网真实结构解析（fixture 见 `test/fixtures/_competition_*.html`）：
/// - 列表页（`apply_list.html` / `gs_list.html` / `find_game.do` / `find_student.do`）
///   都是**服务端渲染**的 `table#listTable`，行数 = 该页条数，翻页靠请求参数
///   `pageNumber`（见 [competitionPageRequestParams] 的口径说明）；
/// - 详情页（`detail.html` / `xd_detail.html`）是只读表单：`<label>标题</label>` 后面
///   跟一个 `input[readonly]` / `select[disabled]` / `textarea[readonly]`；
/// - 奖项是 JSON（`getCredit.do?gameId=`）。
///
/// 解析一律**容错**：结构不符时返回空列表 / 空详情，不抛异常（页面结构变化时界面显示
/// 「暂无数据」而不是崩）。
library;

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';

/// 构造列表页请求参数（**官网分页口径，勿改**）。
///
/// 实测（2026-09-16）：
/// - 首次查询 / 换筛选条件 → 必须带 `pageInit=yes`，否则筛选参数被忽略；
/// - **翻页** → 重复带上同一批筛选参数 + `pageNumber=N`，**不能**带 `pageInit`
///   （带 `pageInit=yes` 会被强制重置回第 1 页）；
/// - `pageSize` 默认 20。
Map<String, dynamic> competitionPageRequestParams({
  required int page,
  int pageSize = 20,
  Map<String, String> filters = const {},
}) {
  final params = <String, dynamic>{
    'pageNumber': '$page',
    'pageSize': '$pageSize',
  };
  filters.forEach((key, value) {
    if (value.trim().isNotEmpty) params[key] = value.trim();
  });
  if (page <= 1) params['pageInit'] = 'yes';
  return params;
}

/// 响应体是否为登录页 / 会话失效页（3xx 之外的第二道判据）。
bool competitionLooksLikeLoginRedirect(String body) {
  final trimmed = body.trimLeft();
  if (!trimmed.startsWith('<!DOCTYPE html') && !trimmed.startsWith('<html')) {
    return false;
  }
  return trimmed.contains('authFailure') ||
      trimmed.contains('/sso/login') ||
      RegExp(r'<title>\s*登录').hasMatch(trimmed);
}

/// 分页条里的总页数（最大 `$.pageSkip(N)`）；解析不到按 1 页。
int competitionTotalPages(String html) {
  var max = 1;
  for (final m in RegExp(r'\$\.pageSkip\((\d+)\)').allMatches(html)) {
    final n = int.tryParse(m.group(1) ?? '') ?? 1;
    if (n > max) max = n;
  }
  return max;
}

/// 我的申请列表（`apply_list.html`）。
List<CompetitionApply> parseCompetitionApplyList(String html) {
  final table = _findListTable(html, const ['比赛年份', '审批状态']);
  if (table == null) return const [];
  final out = <CompetitionApply>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 9) continue;
    final texts = cells.map(_cellText).toList();
    if (texts[0] == '序号') continue;
    final id = _rowId(row);
    if (id == null) continue;
    out.add(
      CompetitionApply(
        id: id,
        year: texts[1],
        studentId: texts[2],
        studentName: texts[3],
        gameName: texts[4],
        type: CompetitionType.fromLabel(texts[5]),
        applyTime: texts[6],
        status: texts[8],
      ),
    );
  }
  return out;
}

/// 竞赛公示列表（`gs_list.html`，全校可见）。
List<CompetitionPublicity> parseCompetitionPublicityList(String html) {
  final table = _findListTable(html, const ['申请人姓名', '学院', '班级']);
  if (table == null) return const [];
  final out = <CompetitionPublicity>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 8) continue;
    final texts = cells.map(_cellText).toList();
    if (texts[0] == '序号') continue;
    final id = _rowId(row);
    if (id == null) continue;
    out.add(
      CompetitionPublicity(
        id: id,
        studentId: texts[1],
        studentName: texts[2],
        college: texts[3],
        className: texts[4],
        gameName: texts[5],
        type: CompetitionType.fromLabel(texts[6]),
        time: texts[7],
      ),
    );
  }
  return out;
}

/// 比赛目录（`find_game.do`）。
List<CompetitionGame> parseCompetitionGameList(String html) {
  final table = _findListTable(html, const ['比赛名称', '校内对接单位']);
  if (table == null) return const [];
  final out = <CompetitionGame>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 6) continue;
    final texts = cells.map(_cellText).toList();
    if (texts.contains('比赛名称')) continue;
    final radio = row.querySelector('input[name="ids"]');
    final id = int.tryParse(radio?.attributes['value'] ?? '');
    if (id == null) continue;
    out.add(
      CompetitionGame(
        id: id,
        year: texts[1],
        name: texts[2],
        level: (radio?.attributes['data-level'] ?? '').trim(),
        college: texts[3],
        time: texts[4],
        url: texts[5],
      ),
    );
  }
  return out;
}

/// 学生检索（`find_student.do`，团队申请用）。
///
/// [CompetitionStudent.rowId] 取自行内 radio 的 `value`（= 官网内部 id，`team` 字段要它），
/// [CompetitionStudent.studentId] 取「学号」列（展示 / 搜索用）。
List<CompetitionStudent> parseCompetitionStudentList(String html) {
  final table = _findListTable(html, const ['姓名', '成员排名']);
  if (table == null) return const [];
  final out = <CompetitionStudent>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 5) continue;
    final texts = cells.map(_cellText).toList();
    if (texts.contains('学号')) continue;
    final rowId = int.tryParse(
      row.querySelector('input[name="ids"]')?.attributes['value'] ?? '',
    );
    if (rowId == null) continue;
    out.add(
      CompetitionStudent(
        rowId: rowId,
        studentId: texts[1],
        name: texts[2],
        college: texts[3],
        className: texts[4],
      ),
    );
  }
  return out;
}

/// 详情页（申请 `detail.html` / 公示 `xd_detail.html`）→ 只读字段 + 证书附件。
///
/// **团队记录**（公示里的 `team=团队`）没有「申请人姓名 / 学号」这类字段，改成一个
/// 「团队成员列表」表格（排名 / 学号 / 姓名 / 学院 / 班级 / 得分）→ 每个成员单独出
/// 一行字段（`团队成员 1` …）。
CompetitionDetail parseCompetitionDetail(String html) {
  final doc = html_parser.parse(html);
  final form = doc.querySelector('form#inputForm') ?? doc.querySelector('form');
  final fields = <CompetitionDetailField>[];
  if (form != null) {
    for (final label in form.querySelectorAll('label')) {
      final text = _clean(label.text).replaceAll(RegExp(r'[:：]$'), '').trim();
      if (text.isEmpty) continue;
      final control = label.parent?.querySelector(
        'input:not([type=hidden]), textarea, select',
      );
      if (control == null) continue;
      final value = _controlValue(control);
      if (fields.any((f) => f.label == text && f.value == value)) continue;
      fields.add(CompetitionDetailField(label: text, value: value));
    }
    fields.addAll(_teamMemberFields(form));
  }

  final attachments = <String>[];
  for (final m in RegExp("openImg_lx\\('([^']+)'").allMatches(html)) {
    final url = (m.group(1) ?? '').trim();
    if (url.isNotEmpty && !attachments.contains(url)) attachments.add(url);
  }
  return CompetitionDetail(fields: fields, attachments: attachments);
}

/// 从公示详情里取获奖等级（**列表页没有等级列，只能逐行拉详情**）。
///
/// 两个来源，实测（2026-09-16，公示第 1 页 20 条）：
/// - `学生提交的奖项`（`input[readonly]`）= `【校赛】一等奖` —— **每条都有**，
///   也是唯一带赛别前缀的字段（17 条「参与未获奖」、2 条「【省赛】二等奖」、1 条「【校赛】一等奖」）；
/// - `最终获得奖项`（`select[disabled]`）= 评定后才写入（`特等奖(2)分`），当页 20 条**全为空**。
///
/// 故：最终奖项非空则优先用它（赛别沿用「学生提交的奖项」的前缀），否则用提交的奖项。
CompetitionAwardLevel competitionAwardLevelOf(CompetitionDetail detail) {
  final submitted = CompetitionAwardLevel.parse(detail.valueOf('学生提交的奖项'));
  final granted = CompetitionAwardLevel.parse(detail.valueOf('最终获得奖项'));
  if (granted.isEmpty) return submitted;
  return CompetitionAwardLevel(
    level: granted.level.isNotEmpty ? granted.level : submitted.level,
    award: granted.award,
  );
}

/// 官方分值文案 → 数字：`三等奖(2)分` → 2、`0分` → 0、`无` / 空 → null。
///
/// 官网把分值写在文案里（`特等奖(15)分`、`参与未获奖(0.1)分`），本函数只认第一个数字，
/// 不做任何「未评定 → 0」的推断（`0分` 就是 0，判断是否已评定交给
/// `CompetitionApplyAward.scored`）。
double? competitionScoreValue(String raw) {
  final text = _clean(raw);
  if (text.isEmpty || text == '无' || text == '请设置奖项') return null;
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// 奖项名 → 该赛别分值表里的分值（认不出返回 null）。
double? competitionOptionScoreFor(
  String award,
  List<CompetitionAwardOption> options,
) {
  if (award.trim().isEmpty) return null;
  for (final option in options) {
    if (option.selectable && option.matches(award)) return option.score;
  }
  return null;
}

/// 「最终获得奖项」下拉里的全部选项 = **该赛别的分值表**。
///
/// 官网结构（实测 2026-09-18，两个版本都见过）：
/// ```html
/// <select class="form-control" id="credit_id" name="credit_id" disabled>
///   <option value="" >无</option>                     <!-- 旧版写作「请设置奖项」-->
///   <option value="46265" >三等奖(2)分</option>        <!-- 旧版写作「【国赛】三等奖(5)分」-->
///   <option value="46268" >特等奖(5)分</option>
/// </select>
/// ```
/// 解析容错：结构不符 / 找不到 select → 返回空表（页面只是不显示加分，不报错）。
List<CompetitionAwardOption> parseCompetitionAwardOptions(String html) {
  final doc = html_parser.parse(html);
  Element? select = doc.querySelector('select#credit_id');
  if (select == null) {
    for (final label in doc.querySelectorAll('label')) {
      if (!_clean(label.text).contains('最终获得奖项')) continue;
      select = label.parent?.querySelector('select');
      if (select != null) break;
    }
  }
  if (select == null) return const [];
  final out = <CompetitionAwardOption>[];
  for (final option in select.querySelectorAll('option')) {
    final raw = _clean(option.text);
    final label = competitionAwardKey(raw);
    final score = competitionScoreValue(raw) ?? 0;
    if (label.isEmpty && score <= 0) continue;
    out.add(
      CompetitionAwardOption(
        label: label.isEmpty ? raw : label,
        score: score,
        selected: option.attributes.containsKey('selected'),
      ),
    );
  }
  return out;
}

/// 一条学科竞赛记录的加分信息（`xd_detail.html` 的同一页）。
///
/// 三个来源见 [CompetitionApplyAward] 的文档；[CompetitionApplyAward.score] 的取值顺序
/// = 个人得分（> 0）→ 最终获得奖项分值 → 申报奖项按该赛别标准的分值。
CompetitionApplyAward parseCompetitionApplyAward(String html) {
  final detail = parseCompetitionDetail(html);
  final options = parseCompetitionAwardOptions(html);
  final submitted = CompetitionAwardLevel.parse(detail.valueOf('学生提交的奖项'));
  final grantedRaw = CompetitionAwardLevel.parse(detail.valueOf('最终获得奖项'));
  // 「最终获得奖项」只有奖项名，赛别沿用「学生提交的奖项」的前缀（同
  // [competitionAwardLevelOf] 的口径）。
  final granted = grantedRaw.isEmpty
      ? CompetitionAwardLevel.empty
      : CompetitionAwardLevel(
          level: grantedRaw.level.isNotEmpty ? grantedRaw.level : submitted.level,
          award: grantedRaw.award,
        );
  final selected = options.where((o) => o.selected && o.selectable).toList();
  return CompetitionApplyAward(
    submitted: submitted,
    granted: granted,
    submittedScore: competitionOptionScoreFor(submitted.award, options),
    grantedScore: granted.isEmpty
        ? null
        : competitionOptionScoreFor(granted.award, options) ??
              (selected.isNotEmpty ? selected.first.score : null),
    personalScore: competitionScoreValue(detail.valueOf('个人得分')),
    options: options,
  );
}

/// 奖项 JSON（`getCredit.do?gameId=`）→ 可选奖项列表。
List<CompetitionAward> parseCompetitionAwards(
  String body, {
  required int gameId,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }
  final raw = switch (decoded) {
    List<Object?> list => list,
    Map<Object?, Object?> map when map['data'] is List =>
      map['data']! as List<Object?>,
    _ => const <Object?>[],
  };
  final out = <CompetitionAward>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final score = double.tryParse('${item['score'] ?? ''}') ?? 0;
    final owner = int.tryParse('${item['parentId'] ?? ''}') ?? gameId;
    out.add(CompetitionAward(gameId: owner, name: name, score: score));
  }
  return out;
}

/// 解析官网 `add.do` / `delete.do` / `upload.do` 的统一应答 `{type, content, data}`。
class CompetitionJsonReply {
  final bool ok;
  final String message;
  final List<Map<Object?, Object?>> data;

  const CompetitionJsonReply({
    required this.ok,
    required this.message,
    this.data = const [],
  });

  static const CompetitionJsonReply failure = CompetitionJsonReply(
    ok: false,
    message: '服务器返回异常',
  );

  /// 解析应答；非 JSON 视为失败（例如 400 错误页）。
  static CompetitionJsonReply parse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return failure;
    }
    if (decoded is! Map) return failure;
    final data = <Map<Object?, Object?>>[];
    final rawData = decoded['data'];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map) data.add(item);
      }
    }
    return CompetitionJsonReply(
      ok: '${decoded['type']}'.toLowerCase() == 'success',
      message: (decoded['content'] ?? '').toString().trim(),
      data: data,
    );
  }

  /// 上传接口返回的附件 id 列表（`data[].id`）。
  List<int> get attachmentIds => [
    for (final item in data) ?int.tryParse('${item['id'] ?? ''}'),
  ];
}

// ---- 工具 ----

/// 团队详情页的成员表（排名 / 学号 / 姓名 / 学院 / 班级 / 得分）。
List<CompetitionDetailField> _teamMemberFields(Element form) {
  final table = form.querySelector('table#listTable');
  if (table == null) return const [];
  final header = _clean(table.querySelector('thead')?.text ?? '');
  for (final key in const ['学号', '姓名', '排名']) {
    if (!header.contains(key)) return const [];
  }
  final out = <CompetitionDetailField>[];
  var index = 0;
  for (final row in table.querySelectorAll('tbody tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 3) continue;
    final texts = cells.map(_cellText).toList();
    // 排名 / 学号 / 姓名 / 学院 / 班级 / 得分（缺列时按前几列拼）
    final name = texts.length > 2 ? texts[2] : '';
    if (name.isEmpty) continue;
    index++;
    out.add(
      CompetitionDetailField(
        label: '团队成员 $index',
        value: [
          if (texts.length > 1) texts[1],
          name,
          if (texts.length > 3) texts[3],
          if (texts.length > 4) texts[4],
          if (texts.length > 5 && texts[5].isNotEmpty) texts[5],
        ].join(' · '),
      ),
    );
  }
  return out;
}

/// 定位列表表格：优先按表头关键字找，退回 `#listTable`。
Element? _findListTable(String html, List<String> headers) {
  final doc = html_parser.parse(html);
  for (final table in doc.querySelectorAll('table')) {
    final text = table.text;
    if (headers.every(text.contains)) return table;
  }
  return doc.querySelector('table#listTable');
}

/// 行内 id：删除按钮 / 查看按钮的 JS 调用参数。
int? _rowId(Element row) {
  final html = row.outerHtml;
  for (final pattern in const [r'showDelete\((\d+)\)', r'showDetail\((\d+)']) {
    final m = RegExp(pattern).firstMatch(html);
    final id = int.tryParse(m?.group(1) ?? '');
    if (id != null) return id;
  }
  return null;
}

String _cellText(Element cell) => _clean(cell.text);

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _controlValue(Element control) {
  switch (control.localName) {
    case 'select':
      // 只有带 selected 的选项才是当前值；「尚未设置」时首选项 value 为空 → 返回空串。
      final selected = control.querySelector('option[selected]');
      if (selected != null) return _clean(selected.text);
      final first = control.querySelector('option');
      if (first == null) return '';
      return (first.attributes['value'] ?? '').isEmpty
          ? ''
          : _clean(first.text);
    case 'textarea':
      return _clean(control.text);
    default:
      return _clean(control.attributes['value'] ?? '');
  }
}
