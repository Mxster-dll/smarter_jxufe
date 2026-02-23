import 'package:flutter/material.dart';

import 'package:smarter_jxufe/Services/GradeService.dart';
import 'package:smarter_jxufe/Services/JxufeLogin.dart';
import 'package:smarter_jxufe/Widgets/AcademicYearPicker.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  GradesPageState createState() => GradesPageState();
}

class GradesPageState extends State<GradesPage> {
  late Future<Widget> _futureWeightedText;
  late Future<Widget> _futureGradeText;

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

    LoginService loginService = LoginService();
    gradeService = GradeService(loginService);
    gradeService.loadJSessionId();

    _futureWeightedText = buildWeightedGradeRank();
    _futureGradeText = buildGradeText();
  }

  Future<Widget> buildWeightedGradeRank() async {
    try {
      final weightedGrade = await gradeService.getWeightedGrade();
      return Text(
        weightedGrade?.toString() ?? 'buildWeightedGradeRank: 空的 weightedGrade',
      );
    } catch (e) {
      return Text('getWeightedGrade 异常: $e\n');
    }
  }

  Future<Widget> buildGradeText() async {
    try {
      final grade = await gradeService.getGrade();

      return grade ?? Text('buildGradeText: 空的 grade');
    } catch (e) {
      return Text('getWeightedGrade 异常: $e\n');
    }
  }

  Widget buildWeightedScoreCard() {
    return Center(
      child: Column(
        crossAxisAlignment: .center,
        children: [
          DropdownButton<WeightedType>(
            value: gradeService.weightedType,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            dropdownColor: Colors.white,
            focusColor: Colors.white,
            style: const TextStyle(color: Colors.black87, fontSize: 16),
            underline: const SizedBox.shrink(), // 隐藏下划线
            onChanged: (WeightedType? value) async {
              if (value == null) throw Exception('value == null');
              if (value == gradeService.weightedType) return;

              setState(() {
                gradeService.weightedType = value;
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
              if (snapshot.connectionState == .waiting) {
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
                onChanged: (int value) {
                  if (value == gradeService.academicYear.year) return;

                  setState(() {
                    gradeService.academicYear = AcademicYear.of(value);
                  });
                },
              ),
              Text('学年'),
              SizedBox(width: 20),
              DropdownButton<TimeLimit>(
                value: gradeService.timeLimit,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                dropdownColor: Colors.white,
                focusColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                underline: const SizedBox.shrink(), // 隐藏下划线
                onChanged: (TimeLimit? value) async {
                  if (value == null) throw Exception('value == null');
                  if (value == gradeService.timeLimit) return;

                  setState(() {
                    gradeService.timeLimit = value;
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
                value: gradeService.semesterType,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                dropdownColor: Colors.white,
                focusColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                underline: const SizedBox.shrink(), // 隐藏下划线
                onChanged: gradeService.timeLimit != TimeLimit.semester
                    ? null
                    : (SemesterType? value) async {
                        if (value == null) throw Exception('value == null');
                        if (value == gradeService.semesterType) return;

                        setState(() {
                          gradeService.semesterType = value;
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
                    gradeService.nextSubjectFilter();
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gradeService.subjectFilter.displayColor,
                ),
                child: Text(gradeService.subjectFilter.displayText),
              ),
              ElevatedButton(
                onPressed: () => {
                  setState(() {
                    gradeService.showRawGrade = !gradeService.showRawGrade;
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gradeService.showRawGrade
                      ? Colors.green
                      : Colors.red,
                ),
                child: Text(gradeService.showRawGrade ? '原始成绩' : '有效成绩'),
              ),
              ElevatedButton(
                onPressed: () => {
                  setState(() {
                    gradeService.onlyNotPassed = !gradeService.onlyNotPassed;
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gradeService.onlyNotPassed
                      ? Colors.green
                      : Colors.white,
                ),
                child: Text(gradeService.onlyNotPassed ? '仅未通过' : '所有课程'),
              ),
            ],
          ),

          FutureBuilder<Widget>(
            future: _futureGradeText,
            builder: (context, snapshot) {
              if (snapshot.connectionState == .waiting) {
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

  const TableWidget({
    super.key,
    required this.tableData,
    this.firstRowIsHeader = true,
    this.columnWidths,
    this.minColumnWidth = 120.0,
    this.maxColumnWidth = 300.0,
  });

  @override
  Widget build(BuildContext context) {
    if (tableData.isEmpty) return Center(child: Text('没有表格数据'));

    final columnCount = tableData.first.length;

    return SingleChildScrollView(
      scrollDirection: .horizontal,
      child: SingleChildScrollView(
        scrollDirection: .vertical,
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
              verticalAlignment: .middle,
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
              verticalAlignment: .middle,
              child: Container(
                padding: .all(10),
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

extension SubjectFilterStyle on SubjectFilter {
  String get displayText => switch (this) {
    .major => '主修',
    .minor => '辅修',
    .all => '主修&辅修',
  };

  Color get displayColor => switch (this) {
    .major => Colors.blue,
    .minor => Colors.green,
    .all => Colors.red,
  };
}
