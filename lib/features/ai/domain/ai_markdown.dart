/// 对话回答用的 Markdown 解析（**纯 Dart，零 Flutter 依赖**，因此可单测）。
///
/// 为什么不复用 `lib/features/rules/data/md_parser.dart`：那套是给 pdf2md 产出的
/// **法务长文档**用的，只保留「标题 / 段落 / 表格」三种块 —— 内联格式（粗体、行内码、
/// 链接）、列表、代码块**全部丢弃**；它的 `clean()` 还会折叠 CJK 之间的空格，对代码
/// 内容是破坏性的。而这些东西在对话回答里恰恰是高频内容，所以另写一套（互不影响：
/// 阅读器仍走它自己那套）。
///
/// 支持范围（够对话用，不追求完整 CommonMark）：
/// - 块级：`#` 标题 1–6、段落、``` 围栏代码块、`-`/`*`/`+` 与 `1.` 列表（含缩进嵌套、
///   `- [ ]` 任务项）、`>` 引用、GFM 管道表格（含对齐）、`---` 分隔线；
/// - 内联：`**粗**`、`*斜*`、`` `码` ``、`~~删除~~`、`[文字](链接)`、`<http://…>`、
///   反斜杠转义。
///
/// ⚠ 两条**刻意的取舍**（都是为对话场景）：
/// 1. **单换行保留成换行**（标准 markdown 会折叠成空格）。模型经常用单换行分点，
///    折叠后挤成一坨，读起来更差。
/// 2. **`_` 强调只在词边界生效**：`snake_case` / `get_my_schedule` 这类标识符在回答里
///    很常见，若按「任意 `_` 都开斜体」处理会被撕成碎片。`*` 不受此限。
library;

// ────────────────────────────── 内联模型 ──────────────────────────────

/// 一段内联内容。[AiMdSpan] 是密封类，渲染层用 switch 穷尽匹配。
sealed class AiMdSpan {
  const AiMdSpan();
}

class AiMdText extends AiMdSpan {
  final String text;
  const AiMdText(this.text);
}

class AiMdStrong extends AiMdSpan {
  final List<AiMdSpan> children;
  const AiMdStrong(this.children);
}

class AiMdEm extends AiMdSpan {
  final List<AiMdSpan> children;
  const AiMdEm(this.children);
}

class AiMdStrike extends AiMdSpan {
  final List<AiMdSpan> children;
  const AiMdStrike(this.children);
}

/// 行内代码（内容已去掉首尾包裹空格）。
class AiMdCode extends AiMdSpan {
  final String text;
  const AiMdCode(this.text);
}

class AiMdLink extends AiMdSpan {
  final String label;
  final String url;
  const AiMdLink({required this.label, required this.url});
}

/// 表格列对齐。
enum AiMdAlign { left, center, right }

// ────────────────────────────── 块级模型 ──────────────────────────────

sealed class AiMdBlock {
  const AiMdBlock();
}

class AiMdHeading extends AiMdBlock {
  /// 1..6（`#` 的个数）。
  final int level;
  final List<AiMdSpan> spans;
  const AiMdHeading(this.level, this.spans);
}

class AiMdPara extends AiMdBlock {
  final List<AiMdSpan> spans;
  const AiMdPara(this.spans);
}

class AiMdCodeBlock extends AiMdBlock {
  /// 原始代码（**不做任何清洗** —— 缩进、空行都要原样保留）。
  final String code;
  final String language;
  const AiMdCodeBlock(this.code, {this.language = ''});
}

class AiMdListItem {
  final bool ordered;

  /// ordered 时的序号；无序项为 0。
  final int number;

  /// 0 起的嵌套深度（按缩进宽度推导）。
  final int depth;

  /// 任务列表的勾选态；`null` = 普通列表项。
  final bool? checked;

  final List<AiMdSpan> spans;

  const AiMdListItem({
    required this.ordered,
    required this.spans,
    this.number = 0,
    this.depth = 0,
    this.checked,
  });
}

class AiMdList extends AiMdBlock {
  final List<AiMdListItem> items;
  const AiMdList(this.items);
}

/// 引用块（内含自己的一套块级结构，故递归）。
class AiMdQuote extends AiMdBlock {
  final List<AiMdBlock> blocks;
  const AiMdQuote(this.blocks);
}

class AiMdTable extends AiMdBlock {
  /// `rows[0]` = 表头；每格都已做过内联解析；所有行长都已被补齐到 [columnCount]。
  final List<List<List<AiMdSpan>>> rows;
  final List<AiMdAlign> align;

  const AiMdTable({required this.rows, required this.align});

  int get columnCount => align.length;
  List<List<AiMdSpan>> get header => rows.isEmpty ? const [] : rows.first;
  Iterable<List<List<AiMdSpan>>> get body => rows.skip(1);
}

class AiMdRule extends AiMdBlock {
  const AiMdRule();
}

// ────────────────────────────── 解析 ──────────────────────────────

final _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*(.*)$');
final _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$');
final _rule = RegExp(r'^ {0,3}(?:(?:\*\s*){3,}|(?:-\s*){3,}|(?:_\s*){3,})$');
final _quoteLine = RegExp(r'^ {0,3}>\s?(.*)$');
final _bulletItem = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _orderedItem = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');
final _task = RegExp(r'^\[([ xX])\]\s+(.*)$');
final _tableDelim = RegExp(r'^ {0,3}\|?[\s:|-]+\|?$');

/// 把一段 markdown 解析成块级结构。
///
/// 容错优先：认不出的行一律当普通段落，**绝不抛异常**（流式过程中随时可能是半截
/// 语法，抛异常会让整个气泡挂掉）。
List<AiMdBlock> parseAiMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <AiMdBlock>[];
  final para = <String>[];

  void flushPara() {
    if (para.isEmpty) return;
    final joined = para.join('\n').trim();
    para.clear();
    if (joined.isEmpty) return;
    blocks.add(AiMdPara(parseAiInline(joined)));
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trimRight();
    final t = line.trim();

    if (t.isEmpty) {
      flushPara();
      i++;
      continue;
    }

    // 围栏代码块
    final fence = _fenceOpen.firstMatch(line);
    if (fence != null && !_isTableDelim(line)) {
      flushPara();
      final marker = fence.group(1)!;
      final info = (fence.group(2) ?? '').trim();
      final language = info.isEmpty ? '' : info.split(RegExp(r'\s+')).first;
      final close = RegExp('^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}\\s*\$');
      final body = <String>[];
      i++;
      while (i < lines.length && !close.hasMatch(lines[i].trimRight())) {
        body.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // 吃掉收尾围栏
      blocks.add(AiMdCodeBlock(body.join('\n'), language: language));
      continue;
    }

    // 标题
    final h = _heading.firstMatch(line);
    if (h != null) {
      final title = _stripTrailingHashes(h.group(2)!);
      if (title.isNotEmpty) {
        flushPara();
        blocks.add(AiMdHeading(h.group(1)!.length, parseAiInline(title)));
        i++;
        continue;
      }
    }

    // 分隔线（必须排在列表之前：`- - -` 同时能匹配无序项）
    if (_rule.hasMatch(line)) {
      flushPara();
      blocks.add(const AiMdRule());
      i++;
      continue;
    }

    // 引用块（只吃连续的 `>` 行；懒续行不支持，宁可少认也不错认）
    final quote = _quoteLine.firstMatch(line);
    if (quote != null) {
      flushPara();
      final inner = <String>[];
      while (i < lines.length) {
        final m = _quoteLine.firstMatch(lines[i].trimRight());
        if (m == null) break;
        inner.add(m.group(1)!);
        i++;
      }
      blocks.add(AiMdQuote(parseAiMarkdown(inner.join('\n'))));
      continue;
    }

    // 管道表格
    if (_looksLikeTable(lines, i)) {
      final parsed = _parseTable(lines, i);
      if (parsed != null) {
        flushPara();
        blocks.add(parsed.table);
        i = parsed.next;
        continue;
      }
    }

    // 列表
    if (_matchItem(line) != null) {
      flushPara();
      final list = _parseList(lines, i);
      blocks.add(AiMdList(list.items));
      i = list.next;
      continue;
    }

    para.add(t);
    i++;
  }
  flushPara();
  return blocks;
}

/// 去掉标题尾部的 `#`（`## 标题 ##` → `标题`）。
String _stripTrailingHashes(String s) {
  var out = s.trim();
  while (out.endsWith('#')) {
    out = out.substring(0, out.length - 1).trimRight();
  }
  return out.trim();
}

bool _isTableDelim(String line) {
  if (!line.contains('-')) return false;
  return _tableDelim.hasMatch(line.trim());
}

bool _looksLikeTable(List<String> lines, int i) {
  if (i + 1 >= lines.length) return false;
  if (!lines[i].contains('|')) return false;
  return _isTableDelim(lines[i + 1]);
}

({AiMdTable table, int next})? _parseTable(List<String> lines, int start) {
  final head = _splitRow(lines[start]);
  final aligns = [
    for (final cell in _splitRow(lines[start + 1])) _alignOf(cell),
  ];
  if (aligns.isEmpty) return null;

  final rows = <List<List<AiMdSpan>>>[_normRow(head, aligns.length)];
  var i = start + 2;
  while (i < lines.length) {
    final t = lines[i].trim();
    if (t.isEmpty || !t.contains('|')) break;
    rows.add(_normRow(_splitRow(lines[i]), aligns.length));
    i++;
  }
  return (table: AiMdTable(rows: rows, align: aligns), next: i);
}

AiMdAlign _alignOf(String cell) {
  final s = cell.trim();
  final left = s.startsWith(':');
  final right = s.endsWith(':');
  if (left && right) return AiMdAlign.center;
  if (right) return AiMdAlign.right;
  return AiMdAlign.left;
}

/// 按未转义的 `|` 切列，并剥掉首尾包裹竖线。
List<String> _splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith('\\|')) {
    s = s.substring(0, s.length - 1);
  }
  final out = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length && s[i + 1] == '|') {
      buf.write('|');
      i++;
      continue;
    }
    if (c == '|') {
      out.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  out.add(buf.toString().trim());
  return out;
}

List<List<AiMdSpan>> _normRow(List<String> cells, int n) => [
  for (var i = 0; i < n; i++)
    (i < cells.length && cells[i].isNotEmpty)
        ? parseAiInline(cells[i])
        : const <AiMdSpan>[],
];

({int indent, bool ordered, int number, String content})? _matchItem(
  String line,
) {
  final o = _orderedItem.firstMatch(line);
  if (o != null) {
    return (
      indent: o.group(1)!.length,
      ordered: true,
      number: int.tryParse(o.group(2)!) ?? 1,
      content: o.group(3)!,
    );
  }
  final b = _bulletItem.firstMatch(line);
  if (b != null) {
    return (
      indent: b.group(1)!.length,
      ordered: false,
      number: 0,
      content: b.group(2)!,
    );
  }
  return null;
}

/// 收集一段连续列表。
///
/// 嵌套深度用**缩进栈**推导（而不是 `indent ~/ 2`）：模型有的用 2 空格、有的用 4 空格、
/// 有的混着用，按固定除数算会把同层项算成不同深度。
({List<AiMdListItem> items, int next}) _parseList(List<String> lines, int start) {
  final items = <AiMdListItem>[];
  final stack = <int>[0];
  var i = start;

  while (i < lines.length) {
    final line = lines[i].trimRight();
    if (line.trim().isEmpty) {
      // 松散列表：空行之后仍是列表项就继续（跳掉空行）
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isEmpty) {
        j++;
      }
      if (j < lines.length && _matchItem(lines[j]) != null) {
        i = j;
        continue;
      }
      break;
    }
    final item = _matchItem(line);
    if (item == null) break;

    while (stack.length > 1 && item.indent < stack.last) {
      stack.removeLast();
    }
    if (item.indent > stack.last) stack.add(item.indent);

    var content = item.content;
    bool? checked;
    final task = _task.firstMatch(content.trim());
    if (task != null) {
      checked = task.group(1)!.toLowerCase() == 'x';
      content = task.group(2)!;
    }

    items.add(
      AiMdListItem(
        ordered: item.ordered,
        number: item.number,
        depth: stack.length - 1,
        checked: checked,
        spans: parseAiInline(content.trim()),
      ),
    );
    i++;
  }
  return (items: items, next: i);
}

// ────────────────────────────── 内联解析 ──────────────────────────────

/// 可被反斜杠转义的字符。
const String _escapable = '\\`*_{}[]()#+-.!|~>';

const int _maxInlineDepth = 8;

/// 解析一行/一段里的内联标记。
List<AiMdSpan> parseAiInline(String text) => _inline(text, 0);

List<AiMdSpan> _inline(String s, int depth) {
  if (s.isEmpty) return const [];
  if (depth > _maxInlineDepth) return [AiMdText(s)];

  final out = <AiMdSpan>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isEmpty) return;
    out.add(AiMdText(buf.toString()));
    buf.clear();
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];

    if (c == '\\' && i + 1 < s.length && _escapable.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    // 行内代码
    if (c == '`') {
      final run = _countRun(s, i, '`');
      final close = _findBackticks(s, i + run, run);
      if (close >= 0) {
        var code = s.substring(i + run, close);
        // CommonMark：首尾各一个空格且内容非全空白时，剥掉这一对空格
        if (code.length >= 2 &&
            code.startsWith(' ') &&
            code.endsWith(' ') &&
            code.trim().isNotEmpty) {
          code = code.substring(1, code.length - 1);
        }
        flush();
        out.add(AiMdCode(code.replaceAll('\n', ' ')));
        i = close + run;
        continue;
      }
      buf.write(s.substring(i, i + run));
      i += run;
      continue;
    }

    // 删除线
    if (c == '~' && i + 1 < s.length && s[i + 1] == '~') {
      final close = s.indexOf('~~', i + 2);
      if (close > i + 2) {
        final inner = s.substring(i + 2, close);
        if (inner.trim().isNotEmpty) {
          flush();
          out.add(AiMdStrike(_inline(inner, depth + 1)));
          i = close + 2;
          continue;
        }
      }
      buf.write('~~');
      i += 2;
      continue;
    }

    // 强调
    if (c == '*' || c == '_') {
      final doubled = i + 1 < s.length && s[i + 1] == c;
      final len = doubled ? 2 : 1;
      if (_canOpen(s, i, len, c)) {
        final close = _findClose(s, i + len, c, len);
        if (close >= 0) {
          flush();
          final kids = _inline(s.substring(i + len, close), depth + 1);
          out.add(doubled ? AiMdStrong(kids) : AiMdEm(kids));
          i = close + len;
          continue;
        }
      }
      buf.write(s.substring(i, i + len));
      i += len;
      continue;
    }

    // 链接
    if (c == '[') {
      final link = _parseLink(s, i);
      if (link != null) {
        flush();
        out.add(AiMdLink(label: link.label, url: link.url));
        i = link.end;
        continue;
      }
    }

    // 自动链接
    if (c == '<') {
      final close = s.indexOf('>', i + 1);
      if (close > i + 1) {
        final inner = s.substring(i + 1, close);
        if (_isHttpUrl(inner)) {
          flush();
          out.add(AiMdLink(label: inner, url: inner));
          i = close + 1;
          continue;
        }
      }
    }

    buf.write(c);
    i++;
  }
  flush();
  return out;
}

int _countRun(String s, int start, String ch) {
  var n = 0;
  while (start + n < s.length && s[start + n] == ch) {
    n++;
  }
  return n;
}

/// 找长度**恰好**为 `len` 的反引号串（紧邻还有反引号说明 run 更长，不算闭合）。
int _findBackticks(String s, int from, int len) {
  final marker = '`' * len;
  var idx = s.indexOf(marker, from);
  while (idx >= 0) {
    final afterOk = idx + len >= s.length || s[idx + len] != '`';
    final beforeOk = idx == 0 || s[idx - 1] != '`';
    if (afterOk && beforeOk) return idx;
    idx = s.indexOf(marker, idx + 1);
  }
  return -1;
}

bool _isWordChar(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.codeUnitAt(0);
  return (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);
}

/// 起始标记是否成立：后面必须有内容（不能是空白/行尾）。
/// `_` 额外要求前面不是词字符 —— 否则 `get_my_schedule` 会被当成斜体撕开。
bool _canOpen(String s, int i, int len, String ch) {
  final after = i + len < s.length ? s[i + len] : '';
  if (after.isEmpty || after.trim().isEmpty) return false;
  if (ch == '_' && i > 0 && _isWordChar(s[i - 1])) return false;
  return true;
}

/// 找闭合标记：前面必须有内容（不能是空白）。
/// `_` 额外要求后面不是词字符（同理保护 `snake_case`）。
int _findClose(String s, int from, String ch, int len) {
  final marker = ch * len;
  var idx = s.indexOf(marker, from);
  while (idx >= 0) {
    final before = idx > 0 ? s[idx - 1] : '';
    if (before.isNotEmpty && before.trim().isNotEmpty) {
      final after = idx + len < s.length ? s[idx + len] : '';
      if (ch != '_' || !_isWordChar(after)) return idx;
    }
    idx = s.indexOf(marker, idx + 1);
  }
  return -1;
}

({String label, String url, int end})? _parseLink(String s, int i) {
  final close = s.indexOf(']', i + 1);
  if (close < 0) return null;
  if (close + 1 >= s.length || s[close + 1] != '(') return null;
  final end = s.indexOf(')', close + 2);
  if (end < 0) return null;

  var url = s.substring(close + 2, end).trim();
  // 可选标题 `(url "title")` → 只留 url
  final title = RegExp('''^(\\S+)\\s+["'(].*\$''').firstMatch(url);
  if (title != null) url = title.group(1)!;
  if (url.isEmpty) return null;

  final label = s.substring(i + 1, close).trim();
  return (label: label.isEmpty ? url : label, url: url, end: end + 1);
}

bool _isHttpUrl(String s) {
  final lower = s.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false;
  }
  return !s.contains(RegExp(r'\s'));
}

// ────────────────────────────── 给测试/预览用的小工具 ──────────────────────────────

/// 把内联结构拍平成纯文本（测试断言与纯文本预览用）。
String aiMdSpansText(List<AiMdSpan> spans) {
  final buf = StringBuffer();
  void walk(List<AiMdSpan> list) {
    for (final s in list) {
      switch (s) {
        case AiMdText(:final text):
          buf.write(text);
        case AiMdCode(:final text):
          buf.write(text);
        case AiMdStrong(:final children):
          walk(children);
        case AiMdEm(:final children):
          walk(children);
        case AiMdStrike(:final children):
          walk(children);
        case AiMdLink(:final label):
          buf.write(label);
      }
    }
  }

  walk(spans);
  return buf.toString();
}

/// 把整篇解析结果拍平成纯文本（保留块级换行）。
String aiMdBlocksText(List<AiMdBlock> blocks) {
  final buf = StringBuffer();
  void walk(List<AiMdBlock> list) {
    for (final b in list) {
      switch (b) {
        case AiMdHeading(:final spans):
          buf.writeln(aiMdSpansText(spans));
        case AiMdPara(:final spans):
          buf.writeln(aiMdSpansText(spans));
        case AiMdCodeBlock(:final code):
          buf.writeln(code);
        case AiMdList(:final items):
          for (final it in items) {
            buf.writeln('${'  ' * it.depth}${it.checked == null ? '' : '${it.checked!} '}${aiMdSpansText(it.spans)}');
          }
        case AiMdQuote(:final blocks):
          walk(blocks);
        case AiMdTable(:final rows):
          for (final row in rows) {
            buf.writeln(row.map(aiMdSpansText).join(' | '));
          }
        case AiMdRule():
          buf.writeln('---');
      }
    }
  }

  walk(blocks);
  return buf.toString();
}
