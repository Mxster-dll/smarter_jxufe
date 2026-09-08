/// md 解析产出的文档块模型 —— 供各模板渲染器消费。
library;

enum BlockKind { heading, para, table }

/// 合并单元格跨度（锚格属性）。锚槽 = 合并区左上物理槽。
class TableSpan {
  final int rowSpan;
  final int colSpan;

  const TableSpan(this.rowSpan, this.colSpan);
}

class TableData {
  /// 物理列（每表固定 columnCount 列）。行 0 = headers。
  final List<String> headers;
  final List<List<String>> rows;

  /// 合并锚：线性键 = row * columnCount + col（row 0 起，含 headers 行）。
  /// 锚槽文本在该槽；其覆盖的洞槽文本为空串、由渲染器跳过。
  final Map<int, TableSpan> spans;

  const TableData({
    required this.headers,
    required this.rows,
    this.spans = const {},
  });

  int get columnCount => headers.length;

  /// 总行数（含表头行）。
  int get rowCount => rows.length + 1;

  bool get hasSpans => spans.isNotEmpty;

  /// (row, col) 处文本：row 0 = headers。
  String cell(int row, int col) =>
      row == 0 ? headers[col] : rows[row - 1][col];

  /// (row, col) 是否为合并锚起点。
  TableSpan? spanAt(int row, int col) => spans[row * columnCount + col];

  /// (row, col) 槽是否被某合并锚覆盖（洞槽也计入覆盖）。
  bool coveredBySpan(int row, int col) {
    final s = spanAt(row, col);
    if (s != null) return true;
    // 从上方/左侧锚回溯太慢，这里仅查自身是否为洞：
    for (var r = 0; r <= row; r++) {
      for (var c = 0; c <= col; c++) {
        final sp = spanAt(r, c);
        if (sp == null) continue;
        if (r + sp.rowSpan > row && c + sp.colSpan > col) return true;
      }
    }
    return false;
  }
}

class DocBlock {
  final BlockKind kind;
  final int level; // heading: 1..3；其余 0
  final String text; // heading / para 文本
  final TableData? table;

  const DocBlock.heading(this.text, {this.level = 1})
      : kind = BlockKind.heading,
        table = null;

  const DocBlock.para(this.text)
      : kind = BlockKind.para,
        level = 0,
        table = null;

  const DocBlock.tableBlock(this.table)
      : kind = BlockKind.table,
        level = 0,
        text = '';
}

/// 章节目录条目（正文渲染时对应的块下标）。
class ChapterRef {
  final String label;
  final int blockIndex;

  const ChapterRef({required this.label, required this.blockIndex});
}

class DocArticle {
  final List<DocBlock> blocks;
  final List<ChapterRef> chapters;

  const DocArticle({required this.blocks, required this.chapters});
}
