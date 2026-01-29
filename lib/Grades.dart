import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:html/parser.dart' as parser;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:fast_gbk/fast_gbk.dart';
// import 'log.dart';
import 'package:html/dom.dart' hide Text;
import 'package:html/parser.dart' show parse;

class GradesPage extends StatefulWidget {
  GradesPage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _GradesPageState createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  String t = "未初始化";
  List<Widget> cc = [];
  List<List<String>> td = [];
  final Map<String, String> headers = {
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    'Access-Control-Allow-Origin': 'https://jwxt.jxufe.edu.cn',
    'Cache-Control': 'max-age=0',
    'Connection': 'keep-alive',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Cookie': 'JSESSIONID=EA0D54F37FB528165114D1BF79A056B3',
    'Origin': 'https://jwxt.jxufe.edu.cn',
    'Referer':
        'https://jwxt.jxufe.edu.cn/student/xscj.jqchjpm10421.html?menucode=S40309',
    'Sec-Fetch-Dest': 'iframe',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
    'sec-ch-ua':
        '"Not(A:Brand";v="8", "Chromium";v="144", "Microsoft Edge";v="144"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
  };

  Map<String, int> jqlx = {
    '课程加权(所有学年)': 1,
    '课程加权（上学年）': 2,
    '课程加权（上学期）': 3,
    '毕业加权': 5,
    '辅修加权': 6,
    '推免加权': 7,
  };

  final Map<String, String> formData = {
    'jqlx': '1',
    'menucode_current': 'S40309',
  };
  @override
  Widget build(BuildContext context) {
    // String response = await sendRequest(headers, formData);
    cc = [
      ElevatedButton(child: Text("POST"), onPressed: () => showScore()),
      Text(t, style: Theme.of(context).textTheme.headlineLarge),
      TableWidget(tableData: td),
    ];
    setState(() {
      t = "${cc.length}";
    });
    return Scaffold(body: Column(children: cc));
  }

  void showScore() async {
    // 设置请求体

    String response = await sendRequest(headers, formData);
    setState(() {
      td = extractTableDataWithSpans(response);
      //   t = response;
      cc.add(TableWidget(tableData: td));
      //   cc.add(Text(response, style: Theme.of(context).textTheme.headlineLarge));
      t = "${cc.length}";
    });
  }

  List<List<String>> extractTableDataWithSpans(String htmlString) {
    final document = parse(htmlString);
    final tables = document.getElementsByTagName('table');

    if (tables.isEmpty) throw Exception('HTML中没有找到table元素');
    if (tables.length > 1) throw Exception('期望只有一个table，但找到了${tables.length}个');

    final table = tables[0];
    final rows = table.querySelectorAll('tr');

    // 首先，计算表格的最大列数，同时收集每个单元格的跨度信息
    int maxCols = 0;
    List<List<Map<String, dynamic>>> rawGrid = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('th, td');
      List<Map<String, dynamic>> rawRow = [];
      int colCount = 0;

      for (final cell in cells) {
        final text = cell.text?.trim() ?? '';
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

  Future<String> sendRequest(
    Map<String, String> headers,
    Map<String, String> formData,
  ) async {
    BaseOptions options = BaseOptions();
    options.responseDecoder =
        (
          List<int> responseBytes,
          RequestOptions options,
          ResponseBody responseBody,
        ) => gbk.decode(responseBytes);
    final dio = Dio(options);

    // 设置请求 URL
    const String url =
        'https://jwxt.jxufe.edu.cn/student/xscj.jqchjpm_data10421.jsp';

    try {
      // 发送 POST 请求
      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          headers: headers,
          // 响应类型设为纯文本，如果是JSON可以改为ResponseType.json
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      return response.data as String;
    } catch (error) {
      // 错误处理
      if (error is DioException) {
        print('请求错误: ${error.message}');
        if (error.response != null) {
          print('响应状态码: ${error.response!.statusCode}');
          print('响应数据: ${error.response!.data}');
        }
        return error.message as String;
      } else {
        print('其他错误: $error');
      }

      rethrow;
    }
  }
}

class TableWidget extends StatelessWidget {
  final List<List<String>> tableData;
  final bool firstRowIsHeader;
  final Map<int, TableColumnWidth>? columnWidths;
  final double minColumnWidth; // 新增：最小列宽
  final double maxColumnWidth; // 新增：最大列宽

  TableWidget({
    required this.tableData,
    this.firstRowIsHeader = true,
    this.columnWidths,
    this.minColumnWidth = 120.0, // 默认最小120
    this.maxColumnWidth = 300.0, // 默认最大300
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
