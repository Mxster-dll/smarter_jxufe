/// 教务「选课」各类响应的解析（纯函数，可单测）。
///
/// 真实响应样本见 `test/fixtures/course_selection_*.html`，抓取时间 2026-09-14。
library;

import 'package:html/parser.dart' as html_parser;

import 'data_table_page.dart';
import 'selection_models.dart';

/// 可选课程列表（`taglib/DataTable.jsp?tableId=2568&fre=1`）。
({List<OptionalCourse> courses, int? total}) parseOptionalCourses(String html) {
  final page = parseDataTablePage(html);
  final courses = page.rows
      .map(OptionalCourse.fromRow)
      .where((e) => e.name.isNotEmpty || e.internalCode.isNotEmpty)
      .toList(growable: false);
  return (courses: courses, total: page.total ?? courses.length);
}

/// 课程范围下拉（`frame/droplist/getDropLists.action`，UTF-8 JSON）。
List<CourseScope> parseCourseScopes(String json) {
  final decoded = tryJsonList(json);
  if (decoded == null) return const [];
  final out = <CourseScope>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final code = '${item['code'] ?? ''}'.trim();
    final name = '${item['name'] ?? ''}'.trim();
    if (code.isEmpty) continue;
    out.add(CourseScope(code: code, name: name.isEmpty ? code : name));
  }
  return out;
}

/// 同上，但直接吃教务返回的 JSON 数组文本。
List<dynamic>? tryJsonList(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start < 0 || end <= start) return null;
  final map = tryJsonMap('{"list":${text.substring(start, end + 1)}}');
  final list = map?['list'];
  return list is List ? list : null;
}

/// 级联下拉的数据响应（`taglib/DroplistControl.jsp?...&flag=list`，UTF-8 XML）。
///
/// 实测两种形态（2026-09-15，活会话抓取）：
/// * `<root><item><key>2025|4405</key><value>2025|计算机科学与技术</value></item></root>`
///   —— 年级/专业（`STUD_preElcGradeSpecialty`）：`key` = **提交值**、`value` = **显示文本**；
/// * `<root><info><value>码</value><name>名</name></info></root>` —— CombBox 家族的形态。
///
/// 无数据时是 `<root></root>`（如「跨学期」范围下未选院系）→ 返回空列表。
List<CourseScope> parseDropListXml(String xml) {
  final text = xml.trim();
  if (text.isEmpty) return const [];
  final out = <CourseScope>[];
  final blocks = RegExp(
    r'<(?:item|info|row)\b([^>]*)>(.*?)</(?:item|info|row)>',
    dotAll: true,
  ).allMatches(text);
  for (final block in blocks) {
    final attrs = block.group(1) ?? '';
    final inner = block.group(2) ?? '';
    final key = _xmlField(inner, attrs, 'key');
    if (key.isNotEmpty) {
      // `<item><key>值</key><value>文本</value></item>`
      final label = _xmlField(inner, attrs, 'value');
      out.add(CourseScope(code: key, name: label.isEmpty ? key : label));
      continue;
    }
    final code = _xmlField(inner, attrs, 'value');
    if (code.isEmpty) continue;
    final name = _xmlField(inner, attrs, 'name');
    out.add(CourseScope(code: code, name: name.isEmpty ? code : name));
  }
  return out;
}

/// 取 `<tag>值</tag>`，取不到再退回属性形态 `<item tag='值'>`。
String _xmlField(String inner, String attrs, String tag) {
  final child = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(inner);
  if (child != null) return _unescapeXml(child.group(1) ?? '');
  final attr = RegExp("$tag\\s*=\\s*['\"]([^'\"]*)['\"]").firstMatch(attrs);
  return attr == null ? '' : _unescapeXml(attr.group(1) ?? '');
}

String _unescapeXml(String raw) => (html_parser.parseFragment(raw).text ?? '')
    .replaceAll('\u2002', ' ')
    .trim();

/// 选课结果整页（`student/wsxk.zxjg.jsp`）。
SelectionResult parseSelectionResult(String html, {bool fromCache = false}) {
  final text = _plainText(html);
  // 「学年学期：2026-2027学年第一学期 学分上限：26 …」（本学期页）
  // 与「学年学期：2025-2026学年第一学期 学号：… 姓名：…」（入学以来页）都要吃住。
  final termLabel = _firstGroup(text, RegExp(r'学年学期：(\S+)')) ?? '';
  final creditLimit = _firstDouble(text, RegExp(r'学分上限：([\d.]+)'));
  final totalCredits = _firstDouble(text, RegExp(r'选课总学分数：([\d.]+)'));
  final totalCount = _firstDouble(text, RegExp(r'选课总门数：([\d.]+)'));

  final document = html_parser.parse(html);
  final courses = <SelectedCourse>[];
  final credits = <String, double>{};

  for (final table in document.querySelectorAll('table')) {
    final id = table.attributes['id'] ?? '';
    if (id == 'reportArea') {
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.children
            .where((e) => e.localName == 'td')
            .map((e) => normalizeTableCell(e.text))
            .toList();
        if (cells.isEmpty) continue;
        final course = selectedCourseFromCells(cells);
        // 表头行 / 次级表头行都不是课程行。
        if (course == null) continue;
        courses.add(course);
      }
      continue;
    }
    // 分类统计表（限选 / 已选 / 可选 × 学分、门数）
    //
    // ⚠ 只取**学分**列（`cells[1]`）：实测该行是 `['已选','25.5','0.0','0.0','1.0',…]`，
    // 学分列与页头「选课总学分数 / 学分上限 / 可选」完全对得上；
    // 而后面的「门数」列是**按专业限选 / 专业任选 / 公共任选分列**的，已选行给出 `1/0/0`，
    // 与页头的「选课总门数：10」不是一个口径 → **不解析**，避免界面出现「限选 26 学分 · 0 门」这种假数字
    //（总门数一律取页头的 `选课总门数：`）。
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children
          .where((e) => e.localName == 'td')
          .map((e) => normalizeTableCell(e.text))
          .toList();
      if (cells.length < 2) continue;
      final label = cells.first;
      if (!_statLabels.containsKey(label)) continue;
      final key = _statLabels[label]!;
      if (credits[key] == null) {
        final value = double.tryParse(cells[1]);
        if (value != null) credits[key] = value;
      }
    }
  }

  return SelectionResult(
    termLabel: termLabel,
    creditLimit: creditLimit,
    totalCredits: totalCredits,
    totalCount: totalCount?.round(),
    categoryCredits: credits,
    courses: courses,
    fromCache: fromCache,
  );
}

const Map<String, String> _statLabels = {
  '限选': '限选',
  '已选': '已选',
  '可选': '可选',
  '已选/免听': '已选',
};

/// 把选课结果表的一行判成一门课（判不出来 → null，即表头/说明行）。
SelectedCourse? selectedCourseFromCells(List<String> rawCells) {
  final cells = rawCells.map(normalizeTableCell).toList();
  // 课程格：`[1004606732]英语视听说`
  final courseIndex = cells.indexWhere(
    (e) => RegExp(r'^\[[^\]]+\]\s*\S').hasMatch(e),
  );
  if (courseIndex < 0) return null;
  final coded = splitCodedName(cells[courseIndex]);

  double? creditsValue;
  var category = '';
  var teacher = '';
  var classCode = '';
  var className = '';
  var method = '';
  var crossGrade = '';
  var status = '';
  var enrolled = '';
  var campus = '';
  var timePlace = '';

  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (cell.isEmpty || i == courseIndex) continue;
    if (RegExp(r'^\d+/\d+$').hasMatch(cell)) {
      enrolled = enrolled.isEmpty ? cell : enrolled;
      continue;
    }
    if (_statusWords.any(cell.contains)) {
      status = status.isEmpty ? cell : status;
      continue;
    }
    if (_methodWords.any(cell.contains)) {
      method = method.isEmpty ? cell : method;
      continue;
    }
    if (cell == '是' || cell == '否') {
      crossGrade = crossGrade.isEmpty ? cell : crossGrade;
      continue;
    }
    if (cell.contains('校区') || _campusWords.contains(cell)) {
      campus = campus.isEmpty ? cell : campus;
      continue;
    }
    if (RegExp(r'[周]|\[\d+-\d+\]|教\d*|\d+-\d+周').hasMatch(cell)) {
      timePlace = timePlace.isEmpty ? cell : timePlace;
      continue;
    }
    if (RegExp(r'^[A-Za-z0-9]+-\d+$').hasMatch(cell)) {
      // ⚠ 只有第一处匹配才是「上课班级」；**不要再往后取第二处当退选码**
      //（见下方 itemCode 的口径：退选码只认表格末格）。
      classCode = classCode.isEmpty ? cell : classCode;
      continue;
    }
    if (RegExp(r'^[\d.]+$').hasMatch(cell)) {
      creditsValue ??= double.tryParse(cell);
      continue;
    }
    if (cell.contains('课') || cell.contains('/')) {
      category = category.isEmpty ? cell : category;
      continue;
    }
    teacher = teacher.isEmpty ? cell : teacher;
  }

  // 退选码（提交给教务的 `items`）**只认表格末格**：
  // 教务页面自己的退选实现（`CancelData()`）就是
  // `items += rows[ind].cells[l-1].innerHTML + "|"`，末格 = 上课班组代码。
  //
  // ⚠ 2026-09-15 事故后立的规矩：**绝不允许回退到 `classCode`**。那一格是「上课班级」，
  // 与退选码语义不同（合班 / 换班时可能是**别门课**的班号），一旦取错就会退掉别的课；
  // 取不到（末格不是码、行结构变了）就留空 → 界面禁用该行退选，宁可不让退，也不能退错。
  final itemCode = _itemCodeFromLastCell(cells);
  return SelectedCourse(
    name: coded.name,
    courseCode: coded.code,
    credits: creditsValue,
    category: category,
    teacher: teacher,
    classCode: classCode,
    className: className,
    selectionMethod: method,
    crossGrade: crossGrade,
    status: status,
    enrolled: enrolled,
    campus: campus,
    timePlace: timePlace,
    itemCode: itemCode,
    cells: cells,
  );
}

/// 退选码（`items`）= 表格**末格**且形如 `1004606732-066`；否则返回空串。
///
/// 空串是**故意**的失败姿态：界面据此禁用该行退选（宁可不让退，也不能退错课）。
String _itemCodeFromLastCell(List<String> cells) {
  if (cells.isEmpty) return '';
  final last = cells.last.trim();
  return RegExp(r'^[A-Za-z0-9]+-\d+$').hasMatch(last) ? last : '';
}

const List<String> _statusWords = ['选中', '免听', '未选中', '已退选', '已取消'];
const List<String> _methodWords = ['管理人员选', '学生网上选', '学生选课', '系统推荐'];
const List<String> _campusWords = [
  '蛟桥园',
  '麦庐园',
  '枫林园',
  '青山园',
  '深圳',
  '北京',
  '上海',
];

/// 教学班列表（`tableId=6142`）。
List<CourseSection> parseSections(String html) {
  final page = parseDataTablePage(html);
  return page.rows
      .map(CourseSection.fromRow)
      .whereType<CourseSection>()
      .toList(growable: false);
}

/// 通用数据列表（查询课表 5327042 / 申请扩容 5929098 等，界面按列名取用）。
DataTablePage parseDataTableRows(String html) => parseDataTablePage(html);

/// 被取消的选课（`student/wsxk.qxbxkc.jsp`）。
({List<CancelledCourse> courses, bool empty}) parseCancelledCourses(
  String html,
) {
  final text = _plainText(html);
  if (text.contains('没有相关数据')) {
    return (courses: const <CancelledCourse>[], empty: true);
  }
  final document = html_parser.parse(html);
  final out = <CancelledCourse>[];
  for (final row in document.querySelectorAll('tr')) {
    final cells = row.children
        .where((e) => e.localName == 'td')
        .map((e) => normalizeTableCell(e.text))
        .toList();
    if (cells.isEmpty) continue;
    if (cells.any((e) => RegExp(r'^\[[^\]]+\]\s*\S').hasMatch(e))) {
      out.add(CancelledCourse.fromCells(cells));
    }
  }
  return (courses: out, empty: out.isEmpty);
}

/// 教学班（`taglib/DataTable.jsp?tableId=6142`，字段名带 `electiveCourseForm.` 前缀）：
/// 选定教学班才能提交选课。
///
/// 实测列（`td name`）：`curent_skbjdm` / `skbjmc` / `xzbj`(查看) / `skbzmc` / `xqmc` /
/// `rkjs` / `skfs_mc` / `xkrssx`(限选人数) / `xkrs`(`已选/待定`) / `kxrs` / `sksj` /
/// `skdd` / `ischk`(radio) / `skbzdm` / `skbjdm` / `xqdm` / `skfs_m` / `outnumber` /
/// `yxsyxkb` / `zfx_m`。
class CourseSection {
  const CourseSection({
    required this.cells,
    this.classCode = '',
    this.classGroupCode = '',
    this.className = '',
    this.teacher = '',
    this.time = '',
    this.place = '',
    this.campus = '',
    this.campusCode = '',
    this.enrolled = '',
    this.limit = '',
    this.available = '',
    this.teachMode = '',
    this.outnumber = '0',
    this.timeConflictFlag = '0',
  });

  /// 上课班号（形如 `000160-016`）—— 提交时作为 `skbjdm`。
  final String classCode;

  /// 上课班组代码 —— 提交时作为 `skbzdm`。
  final String classGroupCode;

  /// 上课班级名称（如「辅修+」）。
  final String className;
  final String teacher;

  /// 上课时间（如「2-17周 四(3-5节)」）与地点（如「麦三教3213」）。
  final String time;
  final String place;

  final String campus;
  final String campusCode;

  /// 已选/待定人数原文（如 `48/0`）。
  final String enrolled;

  /// 限选人数（`xkrssx`）与可选人数（`kxrs`）。
  final String limit;
  final String available;

  /// 授课方式（`skfs_mc`，如「理论」）。
  final String teachMode;

  /// 提交时需要回传的教务开关。
  final String outnumber;
  final String timeConflictFlag;

  final Map<String, String> cells;

  /// 组合出的时间地点文案。
  String get timePlace => [time, place].where((e) => e.isNotEmpty).join(' ');

  static CourseSection? fromRow(Map<String, String> row) {
    final values = row.map((k, v) => MapEntry(k, normalizeTableCell(v)));
    final classCode = _firstNonEmpty([
      values['skbjdm'],
      values['curent_skbjdm'],
    ]);
    if (values.values.every((e) => e.isEmpty)) return null;
    if (classCode.isEmpty && (values['skbjmc'] ?? '').isEmpty) return null;
    return CourseSection(
      cells: values,
      classCode: classCode,
      classGroupCode: _firstNonEmpty([values['skbzdm'], values['skbz']]),
      className: _firstNonEmpty([values['skbjmc'], values['skbzmc']]),
      teacher: _firstNonEmpty([values['rkjs'], values['jsmc']]),
      time: values['sksj'] ?? '',
      place: values['skdd'] ?? '',
      campus: values['xqmc'] ?? '',
      campusCode: values['xqdm'] ?? '',
      enrolled: values['xkrs'] ?? '',
      limit: values['xkrssx'] ?? '',
      available: values['kxrs'] ?? '',
      teachMode: values['skfs_mc'] ?? '',
      outnumber: _firstNonEmpty([values['outnumber']]).isEmpty
          ? '0'
          : values['outnumber']!,
      timeConflictFlag: _firstNonEmpty([values['zfx_m']]).isEmpty
          ? '0'
          : values['zfx_m']!,
    );
  }
}

String _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final text = (value ?? '').trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _plainText(String html) {
  final document = html_parser.parse(html);
  for (final node in document.querySelectorAll('script,style')) {
    node.remove();
  }
  return document.body?.text
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'\s+'), ' ') ??
      '';
}

String? _firstGroup(String text, RegExp pattern) =>
    pattern.firstMatch(text)?.group(1)?.trim();

double? _firstDouble(String text, RegExp pattern) {
  final raw = _firstGroup(text, pattern);
  return raw == null ? null : double.tryParse(raw);
}
