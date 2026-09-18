/// 规章制度「资料库」文档的结构化取用工具（纯函数：输入 md 文本，不触碰 IO）。
///
/// 背景（2026-09-17）：新功能「推免成绩」「竞赛奖励」要求**运行时自动**从资料库
/// （`assets/rules/`）读取加分项与竞赛信息，不把表格手工抄成静态数据
/// （用户原话：「自动从资料库里获取加分项」「参考《学科竞赛管理办法》/ 自动资料库里
/// 获取竞赛信息」）。因此这里提供不依赖 Flutter、不做 IO 的纯函数：md 文本进，
/// 分段与「物理化」表格出。
///
/// 要处理的三个现实坑（都来自 pdf2md 产物）：
/// 1. **词内空格**：`中国国际大学生创新创 业大赛`、`排名第 1 者` ——
///    [ruleCleanText] 折叠 CJK/CJK、CJK/数字之间的空格（与 `MdParser.clean` 同口径）；
/// 2. **合并单元格**：`<td rowspan="3">` 只在首行有文本、其余槽位为空 ——
///    [ruleTableOf] 把锚格文本复制到它覆盖的**每一个**槽位（rowspan 向下、colspan 向右），
///    取值方不必再查 spans（Ⅰ类奖励表的「获奖等级」正是靠这个才能逐行读到）；
/// 3. **多层表头**：一张表可能有三行表头（`Ⅰ类竞赛` / `奖励对象` / `获奖等级`）——
///    全部物理行都保留，由调用方按列向上回溯（见 `award_standard_parser.dart`）。
///
/// 设计取舍：这里**只做「结构」不做「语义」**。哪张表是奖励标准、哪一列是「赛项名称」，
/// 一律由各 feature 自己的 parser 按表头文字判断（表头文字是学校文档里最稳定的锚），
/// 绝不按固定行列下标取值 —— 学校改版换列序时只会解析失败（有兜底），不会静默算错。
library;

import 'dart:math' as math;

import '../domain/doc_blocks.dart';
import 'md_parser.dart';

/// CJK / 全角 / 数字字符类 —— 用来判定「中文字里的空格」。
///
/// ⚠ 不能直接复用 `MdParser.clean`：它只把连续空白**压成一个空格**（`分值/次` 这类
/// 词被 pdf 提取拆开后仍带空格）。资料库文档里的 `级 别`、`中国国际大学生创新创 业大赛`、
/// `省优 秀共产党员` 都必须**去掉**空格才能与别处的同一概念比对，否则
/// 「按表头取列」会静默取不到列（实测：专利类整类解析成 0 项）。
const String _cjkish =
    r'[\u3400-\u9fff\u2160-\u217f\u3000-\u303f\uff00-\uffef0-9]';

final RegExp _cjkInnerSpace = RegExp('(?<=$_cjkish)[ \t]+(?=$_cjkish)');
final RegExp _spaceRun = RegExp(r'[ \t\u3000]+');

/// 折叠/移除提取噪声空格并 trim：
/// 1. NBSP、全角空格 → 半角空格；
/// 2. **两侧都是 CJK/数字的空格直接删掉**（`分 值` → `分值`）；
/// 3. 其余连续空白压成一个空格（保留 `ACM-ICPC 国际…` 这类拉丁/中文之间的空格）。
String ruleCleanText(String s) {
  var out = s.replaceAll('\u00a0', ' ').replaceAll('\u3000', ' ');
  out = out.replaceAll(_cjkInnerSpace, '');
  out = out.replaceAll(_spaceRun, ' ');
  return out.trim();
}

/// 一张「物理化」的表：[grid] 第一行 = 物理表头行（pdf2md 的表头可能不止一行，
/// 这里全部按行保留）；合并单元格的文本已复制到其覆盖的每个槽位。
class RuleTable {
  final List<List<String>> grid;

  const RuleTable(this.grid);

  int get rowCount => grid.length;
  int get columnCount => grid.isEmpty ? 0 : grid.first.length;
  List<String> get header => grid.isEmpty ? const [] : grid.first;

  String cell(int row, int col) {
    if (row < 0 || row >= rowCount) return '';
    if (col < 0 || col >= columnCount) return '';
    return grid[row][col];
  }

  /// 某行的全部单元格（已 trim）。
  List<String> rowAt(int row) =>
      row < 0 || row >= rowCount ? const [] : grid[row];

  /// 第一个满足 [test] 的行下标（按行内任一单元格匹配，单元格已 [ruleCleanText]）。
  int indexOfRow(bool Function(String cell) test) {
    for (var r = 0; r < rowCount; r++) {
      if (grid[r].any((c) => test(ruleCleanText(c)))) return r;
    }
    return -1;
  }

  /// 单元格文本里含 [needle] 的列下标（取第一个）。比较前两侧都 [ruleCleanText]。
  int indexOfColumn(String needle, {int row = 0}) {
    for (var c = 0; c < columnCount; c++) {
      if (ruleCleanText(cell(row, c)).contains(needle)) return c;
    }
    return -1;
  }
}

/// 一段（一个标题下的）文档内容：保留**原顺序**的块序列。
///
/// 顺序很关键：奖励标准表的「这是给学生的还是给教师的」要靠它**前面**那段
/// `2.本科生奖励标准` 判断，表下的「注：…」又紧跟在它后面。
class RuleSection {
  final String title; // 标题文本（已去掉 # 与首尾空白）；文件头前言为 ''
  final int level; // 标题层级（1..6）；前言为 0
  final List<DocBlock> blocks;

  const RuleSection({
    required this.title,
    required this.level,
    required this.blocks,
  });

  bool get isPreamble => title.isEmpty;

  List<DocBlock> get tables => [
    for (final b in blocks)
      if (b.kind == BlockKind.table && b.table != null) b,
  ];

  List<RuleTable> get ruleTables => [
    for (final b in blocks)
      if (b.kind == BlockKind.table && b.table != null)
        ruleTableOf(b.table!),
  ];

  /// 该节内的段落文本（不含表格）。
  List<String> get paragraphs => [
    for (final b in blocks)
      if (b.kind == BlockKind.para && b.text.trim().isNotEmpty) b.text.trim(),
  ];

  String get text => paragraphs.join('\n');

  bool titleHas(String needle) => title.contains(needle);
}

/// md → 标题分段（**任何**层级的标题都开一节，因此 `## 二、专利类` 与
/// `### （一）发明专利` 各自成节，便于「先找大类、再找小类」）。
List<RuleSection> ruleSectionsOf(String md) {
  final blocks = MdParser().parse(md).blocks;
  final out = <RuleSection>[];
  var title = '';
  var level = 0;
  var current = <DocBlock>[];

  void flush() {
    if (title.isEmpty && current.isEmpty) return;
    out.add(
      RuleSection(
        title: title,
        level: level,
        blocks: List<DocBlock>.unmodifiable(current),
      ),
    );
  }

  for (final b in blocks) {
    if (b.kind == BlockKind.heading) {
      flush();
      title = b.text.trim();
      level = b.level;
      current = <DocBlock>[];
      continue;
    }
    current.add(b);
  }
  flush();
  return out;
}

/// 取第一个标题含 [needle] 的节；[level] 限定标题层级（null = 不限）。
RuleSection? ruleSectionOf(
  Iterable<RuleSection> sections,
  String needle, {
  int? level,
}) {
  for (final s in sections) {
    if (level != null && s.level != level) continue;
    if (s.title.contains(needle)) return s;
  }
  return null;
}

/// 取标题匹配 [test] 的第一个节。
RuleSection? ruleSectionWhere(
  Iterable<RuleSection> sections,
  bool Function(RuleSection s) test,
) {
  for (final s in sections) {
    if (test(s)) return s;
  }
  return null;
}

final RegExp _numberRe = RegExp(r'\d+(?:\.\d+)?');
final RegExp _intRe = RegExp(r'\d+');

/// 文本里第一个数字（支持小数）。
double? ruleFirstNumber(String s) {
  final m = _numberRe.firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// 文本里全部数字。
List<double> ruleNumbersIn(String s) => [
  for (final m in _numberRe.allMatches(s))
    if (double.tryParse(m.group(0)!) != null) double.parse(m.group(0)!),
];

/// 文本里第一个整数。
int? ruleFirstInt(String s) {
  final m = _intRe.firstMatch(s);
  return m == null ? null : int.tryParse(m.group(0)!);
}

/// 金额文本 → 元。`'10 万元'`→100000、`'3.2 万元'`→32000、`'8000 元'`→8000；
/// `'/'`/`'—'`/空 → null（表里用 `/` 表示「该项不奖励」）。
double? ruleAmountInYuan(String raw) {
  final s = ruleCleanText(raw);
  if (s.isEmpty) return null;
  if (s.replaceAll(RegExp(r'[/／—\-－\s]'), '').isEmpty) return null;
  final value = ruleFirstNumber(s);
  if (value == null) return null;
  if (s.contains('万')) return value * 10000;
  if (s.contains('千')) return value * 1000;
  return value;
}

/// [TableData] → [RuleTable]：把 rowspan/colspan 锚格文本复制到覆盖的每个槽位。
RuleTable ruleTableOf(TableData table) {
  final n = table.columnCount;
  final grid = <List<String>>[List<String>.of(table.headers)];
  for (final row in table.rows) {
    grid.add(List<String>.of(row));
  }
  if (n <= 0 || grid.isEmpty) return RuleTable(grid);

  for (final e in table.spans.entries) {
    final anchorRow = e.key ~/ n;
    final anchorCol = e.key % n;
    if (anchorRow < 0 ||
        anchorRow >= grid.length ||
        anchorCol < 0 ||
        anchorCol >= n) {
      continue;
    }
    final text = grid[anchorRow][anchorCol];
    if (text.isEmpty) continue;
    final rowEnd = math.min(anchorRow + math.max(1, e.value.rowSpan), grid.length);
    final colEnd = math.min(anchorCol + math.max(1, e.value.colSpan), n);
    for (var r = anchorRow; r < rowEnd; r++) {
      for (var c = anchorCol; c < colEnd; c++) {
        grid[r][c] = text;
      }
    }
  }
  return RuleTable(grid);
}

/// 规整括号与引号（提取产物里 `（金 奖）`、`“挑战杯”` 混用全半角），
/// 供「标签相等」这类比较使用。
String ruleNormalizeLabel(String raw) {
  var s = ruleCleanText(raw);
  s = s.replaceAll(RegExp(r'[（(]\s*'), '（').replaceAll(RegExp(r'\s*[）)]'), '）');
  s = s.replaceAll('“', '"').replaceAll('”', '"').replaceAll('‘', "'").replaceAll('’', "'");
  s = s.replaceAll(RegExp(r'[\s\u3000]+'), '');
  return s;
}
