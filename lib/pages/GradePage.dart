import 'package:flutter/material.dart';
import 'package:smarter_jxufe/Services/GradeService.dart';
import 'package:smarter_jxufe/Widgets/AcademicYearPicker.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  GradesPageState createState() => GradesPageState();
}

class GradesPageState extends State<GradesPage> {
  late Future<Widget> _futureWeightedText;
  WeightedType _weightedType = WeightedType.courseAll;

  late Future<Widget> _futureGradeText;
  TimeLimit _timeLimit = TimeLimit.semester;
  bool _showRawGrade = false;
  bool _onlyNotPassed = false;
  SemesterType? _semType = SemesterType.first;
  AcademicYear? _year = AcademicYear.thisYear;
  int _majorMinorState = 3;
  final mmColor = {1: Colors.blue, 2: Colors.green, 3: Colors.red};
  final mmText = {1: '主修', 2: '辅修', 3: '主修&辅修'};

  late final GradeService gradeService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ListView(
          children: [
            Row(
              children: [
                ElevatedButton(
                  child: Text('刷新成绩'),
                  onPressed: () async {
                    setState(() {
                      _futureWeightedText = buildWeightedGradeRank();
                      _futureGradeText = buildGradeText();
                    });
                  },
                ),
                ElevatedButton(
                  child: Text('刷新 Cookie'),
                  onPressed: () async {
                    gradeService.clearJSessionId();
                    setState(() {
                      _futureWeightedText = buildWeightedGradeRank();
                      _futureGradeText = buildGradeText();
                    });
                  },
                ),
              ],
            ),
            buildWeightedScoreCard(),
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
    gradeService.loadJSessionId();

    _futureWeightedText = buildWeightedGradeRank();
    _futureGradeText = buildGradeText();
  }

  Future<Widget> buildWeightedGradeRank() async {
    try {
      final weightedGrade = await gradeService.getWeightedGrade(_weightedType);
      return Text(
        weightedGrade?.toString() ?? 'buildWeightedGradeRank: 空的 weightedGrade',
      );
    } catch (e) {
      return Text('getWeightedGrade 异常: $e\n');
    }
  }

  Future<Widget> buildGradeText() async {
    try {
      if (_timeLimit == TimeLimit.academicYear) _semType = null;
      if (_timeLimit == TimeLimit.sinceEnrollment) {
        _year = null;
        _semType = null;
      }

      final grade = await gradeService.getGrade(
        timeLimit: _timeLimit,
        showRawGrade: _showRawGrade,
        selectMajor: _selectMajor,
        selectMinor: _selectMinor,
        onlyNotPassed: _onlyNotPassed,
        semType: _semType,
        year: _year,
      );
      // final grade = null;
      return grade ?? Text('buildGradeText: 空的 grade');
    } catch (e) {
      return Text('getWeightedGrade 异常: $e\n');
    }
  }

  bool _selectMajor = true;
  bool _selectMinor = true;

  Widget buildWeightedScoreCard() {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DropdownButton<WeightedType>(
            value: _weightedType,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            dropdownColor: Colors.white,
            focusColor: Colors.white,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            underline: const SizedBox.shrink(), // 隐藏下划线
            onChanged: (WeightedType? value) async {
              if (value == null) throw Exception('value == null');

              setState(() {
                if (_weightedType == value) return;

                _weightedType = value;
                _futureWeightedText = buildWeightedGradeRank();
              });
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
            future: _futureWeightedText,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Text('buildWeightedGradeRank 错误：\n${snapshot.error}');
              } else {
                return snapshot.data!;
              }
            },
          ),
          Row(
            children: [
              AcademicYearPicker(
                1976,
                DateTime.now().year,
                onChanged: (int value) => {
                  setState(() {
                    if (_year?.year == value) return;

                    _year = AcademicYear.of(value);
                  }),
                },
              ),
              Text('学年'),
              SizedBox(width: 20),
              DropdownButton<TimeLimit>(
                value: _timeLimit,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                dropdownColor: Colors.white,
                focusColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                underline: const SizedBox.shrink(), // 隐藏下划线
                onChanged: (TimeLimit? value) async {
                  if (value == null) throw Exception('value == null');

                  setState(() {
                    if (_timeLimit == value) return;

                    _timeLimit = value;
                    _futureGradeText = buildGradeText();
                  });
                },
                items: TimeLimit.values
                    .map(
                      (TimeLimit tl) => DropdownMenuItem<TimeLimit>(
                        value: tl,
                        child: Text(tl.name),
                      ),
                    )
                    .toList(),
              ),
              DropdownButton<SemesterType>(
                value: _semType,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                dropdownColor: Colors.white,
                focusColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                underline: const SizedBox.shrink(), // 隐藏下划线
                onChanged: (SemesterType? value) async {
                  if (value == null) throw Exception('value == null');

                  setState(() {
                    if (_semType == value) return;

                    _semType = value;
                    _futureGradeText = buildGradeText();
                  });
                },
                items: SemesterType.values
                    .map(
                      (SemesterType st) => DropdownMenuItem<SemesterType>(
                        value: st,
                        child: Text(st.name),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          Row(
            children: [
              ElevatedButton(
                onPressed: () => {
                  setState(() {
                    _majorMinorState = (_majorMinorState + 1) % 3 + 1;
                    _selectMajor = _majorMinorState & 1 == 1;
                    _selectMinor = _majorMinorState & 10 == 1;
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: mmColor[_majorMinorState],
                ),
                child: Text(mmText[_majorMinorState] ?? ''),
              ),
              ElevatedButton(
                onPressed: () => {
                  setState(() {
                    _showRawGrade = !_showRawGrade;
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _showRawGrade ? Colors.green : Colors.red,
                ),
                child: Text(_showRawGrade ? '原始成绩' : '有效成绩'),
              ),
              ElevatedButton(
                onPressed: () => {
                  setState(() {
                    _onlyNotPassed = !_onlyNotPassed;
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _onlyNotPassed ? Colors.green : Colors.white,
                ),
                child: Text(_onlyNotPassed ? '仅未通过' : '所有课程'),
              ),
            ],
          ),

          FutureBuilder<Widget>(
            future: _futureGradeText,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Text('buildGradeText 错误：\n${snapshot.error}');
              } else {
                return snapshot.data!;
              }
            },
          ),
        ],
      ),
    );
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
