import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import '../Services/GradeService.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  GradesPageState createState() => GradesPageState();
}

class GradesPageState extends State<GradesPage> {
  late Future<Widget> _futureTable;
  late final GradeService gradeService;
  WeightedType _weightedType = WeightedType.courseAll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            DropdownButton<WeightedType>(
              value: _weightedType,
              isExpanded: false,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              elevation: 8,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black87, fontSize: 16),
              // 选中项的下划线样式（默认有下划线，可设为SizedBox.shrink()隐藏）
              underline: Container(height: 1, color: Colors.grey[200]),
              onChanged: (WeightedType? value) async {
                if (value == null) throw Exception('value == null');

                setState(() {
                  _weightedType = value;
                  _futureTable = buildWeightedScoreCard();
                });

                await _futureTable;
              },
              items: WeightedType.values
                  .map(
                    (WeightedType wt) => DropdownMenuItem<WeightedType>(
                      value: wt,
                      child: Text(wt.name),
                    ),
                  )
                  .toList(),
            ),
            FutureBuilder<Widget>(
              future: _futureTable,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator()); // 加载中
                } else if (snapshot.hasError) {
                  return Text('错误：${snapshot.error}'); // 出错
                } else {
                  return snapshot.data!; // 成功
                }
              },
            ),
            ElevatedButton(
              child: Text('刷新'),
              onPressed: () async {
                setState(() {
                  _futureTable = buildWeightedScoreCard();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // 从统一门户获取的gid_参数（需替换为实际值）
    final gid =
        'S3lvSGM0NjRtSEtYcGhMcjZ2byszZnlGU0VkeXdGSTNOdllhckgyQVRaVnhhNi8zTUxRQ2hvWjhDbmlodWo1d0lVNGRzbDdqZ3hXU2FJYmxrK054TlE9PQ';

    gradeService = GradeService(gid: gid);

    _futureTable = buildWeightedScoreCard();
  }

  Future<Widget> buildWeightedScoreCard() async {
    final String? html = await gradeService.getWeightedGrade(_weightedType);
    if (html == null) return Text('空的响应体');

    final document = parse(html);
    final tables = document.getElementsByTagName('table');

    if (tables.length != 1) {
      print(html);
      return Text('期望有1个 table，但找到了${tables.length}个 table');
    }

    final tableData = extractTableDataWithSpans(tables[0]);

    return TableWidget(tableData: tableData);
  }

  List<List<String>> extractTableDataWithSpans(dom.Element table) {
    final rows = table.querySelectorAll('tr');

    // 首先，计算表格的最大列数，同时收集每个单元格的跨度信息
    int maxCols = 0;
    List<List<Map<String, dynamic>>> rawGrid = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('th, td');
      List<Map<String, dynamic>> rawRow = [];
      int colCount = 0;

      for (final cell in cells) {
        final text = cell.text.trim();
        final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '1') ?? 1;
        final colspan = int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1;
        rawRow.add({'text': text, 'rowspan': rowspan, 'colspan': colspan});
        colCount += colspan;
      }

      if (colCount > maxCols) maxCols = colCount;
      rawGrid.add(rawRow);
    }

    // 创建一个二维字符串矩阵，初始全部为空字符串
    List<List<String>> result = List.generate(
      rows.length,
      (i) => List.filled(maxCols, ''),
    );

    // 填充矩阵
    for (int rowIdx = 0; rowIdx < rawGrid.length; rowIdx++) {
      final rawRow = rawGrid[rowIdx];
      int colIdx = 0;

      for (final cell in rawRow) {
        // 找到当前行第一个为空字符串的位置（即未被之前的合并单元格占据的位置）
        while (colIdx < maxCols && result[rowIdx][colIdx].isNotEmpty) {
          colIdx++;
        }

        // 将单元格文本放入左上角位置
        result[rowIdx][colIdx] = cell['text'];

        // 标记合并单元格所覆盖的位置为占位符（这里我们用空字符串，但已经放了文本，所以需要跳过）
        // 我们用一个特殊值（如null）表示被合并的单元格，但这里我们使用空字符串已经可以，因为文本已经放在左上角。
        // 但是，我们需要防止其他单元格再放入这些位置，所以我们将这些位置标记为非空（这里我们放一个特殊字符串，比如'__span__'，但后面会被覆盖）
        // 实际上，我们可以直接跳过这些位置，在放置下一个单元格时，我们会跳过非空位置。
        // 所以这里我们只需要将合并单元格覆盖的位置设置为非空（比如空字符串）即可，但这样会和没有内容的单元格混淆。
        // 没有内容的单元格本身就是空字符串，所以我们需要另一个方式标记被合并单元格覆盖的位置。
        // 我们可以用null标记，但在Dart中，List<String>不能包含null，所以我们可以用一个不可能出现的字符串，比如'__span__'，然后在最后处理时，将所有'__span__'变为空字符串。

        // 为了简单，我们用一个临时的占位字符串
        final String placeholder = '__span__';
        for (int r = 0; r < cell['rowspan']; r++) {
          for (int c = 0; c < cell['colspan']; c++) {
            if (r == 0 && c == 0) continue; // 左上角已经放了文本

            int targetRow = rowIdx + r;
            int targetCol = colIdx + c;
            if (targetRow < rows.length && targetCol < maxCols) {
              result[targetRow][targetCol] = placeholder;
            }
          }
        }
        colIdx += cell['colspan'] as int;
      }
    }

    // 将占位符替换为空字符串
    for (int i = 0; i < result.length; i++) {
      for (int j = 0; j < maxCols; j++) {
        if (result[i][j] == '__span__') {
          result[i][j] = '';
        }
      }
    }

    return result;
  }
}

class TableWidget extends StatelessWidget {
  final List<List<String>> tableData;
  final bool firstRowIsHeader;
  final Map<int, TableColumnWidth>? columnWidths;
  final double minColumnWidth;
  final double maxColumnWidth;

  TableWidget({
    required this.tableData,
    this.firstRowIsHeader = true,
    this.columnWidths,
    this.minColumnWidth = 120.0,
    this.maxColumnWidth = 300.0,
  });

  @override
  Widget build(BuildContext context) {
    if (tableData.isEmpty) return Center(child: Text('没有表格数据'));

    final columnCount = tableData[0].length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!),
          defaultColumnWidth: FixedColumnWidth(150.0), // 设置默认固定宽度
          columnWidths: columnWidths ?? _buildColumnWidths(columnCount),
          children: _buildTableRows(),
        ),
      ),
    );
  }

  Map<int, TableColumnWidth> _buildColumnWidths(int columnCount) {
    final Map<int, TableColumnWidth> widths = {};

    for (int i = 0; i < columnCount; i++) {
      // 方案1：固定宽度
      //   widths[i] = FixedColumnWidth(minColumnWidth);

      // 方案2：根据内容自适应，但有最小宽度限制
      widths[i] = IntrinsicColumnWidth(flex: 1);

      // 方案3：弹性宽度，但限制最小宽度
      // widths[i] = MinColumnWidth(
      //   FixedColumnWidth(minColumnWidth),
      //   FlexColumnWidth(1.0),
      // );
    }

    return widths;
  }

  List<TableRow> _buildTableRows() {
    final startRowIndex = firstRowIsHeader ? 1 : 0;
    final List<TableRow> rows = [];

    // 添加表头（如果需要）
    if (firstRowIsHeader && tableData.isNotEmpty) {
      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(bottom: BorderSide(color: Colors.grey[400]!)),
          ),
          children: tableData[0].map((header) {
            return TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Container(
                padding: EdgeInsets.all(12),
                constraints: BoxConstraints(minHeight: 50),
                child: Text(
                  header,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // 添加数据行
    for (int i = startRowIndex; i < tableData.length; i++) {
      final rowData = tableData[i];

      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: i.isEven ? Colors.white : Colors.grey[50],
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          children: rowData.map((cell) {
            return TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Container(
                padding: EdgeInsets.all(10),
                constraints: BoxConstraints(minHeight: 40),
                child: Text(cell, style: TextStyle(fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      );
    }

    return rows;
  }
}
