import 'package:flutter/material.dart';

import 'package:smarter_jxufe/ims/GradeService.dart';
import 'package:smarter_jxufe/ims/imsService.dart';
import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/Course.dart';
import 'package:smarter_jxufe/ims/Grades.dart';
import 'package:smarter_jxufe/widgets/AcademicYearPicker.dart';
import 'package:smarter_jxufe/widgets/ToggleButton.dart';
import 'package:smarter_jxufe/login/JxufeLogin.dart';

class GradesPage extends StatefulWidget {
  const GradesPage({super.key});

  @override
  GradesPageState createState() => GradesPageState();
}

class GradesPageState extends State<GradesPage> {
  late Future<Widget> _futureGradeText;
  late Future<Widget> _futureWeightedTable;
  // TODO 拆分futureBuilder （最细到每一个表格单元格）

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
                      _futureWeightedTable = buildWeightedGradeRank();
                      _futureGradeText = buildGradeText();
                    });
                  },
                ),
                ElevatedButton(
                  child: Text('刷新 Cookie'),
                  onPressed: () async {
                    gradeService.refresh();
                    setState(() {
                      _futureWeightedTable = buildWeightedGradeRank();
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
    ImsService imsService = ImsService(loginService);
    imsService.loadJSessionId();
    gradeService = GradeService(imsService);

    _futureWeightedTable = buildWeightedGradeRank();
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

      return grade?.toTable() ?? Text('buildGradeText: 空的 grade');
    } catch (e) {
      return Text('getWeightedGrade 异常: $e\n');
    }
  }

  Widget buildWeightedScoreCard() {
    return Center(
      child: Column(
        crossAxisAlignment: .center,
        children: [
          DropdownButton(
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
                _futureWeightedTable = buildWeightedGradeRank();
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

          Row(
            children: [
              AcademicYearPicker(
                1976,
                AcademicYear.now.value,
                onChanged: (int value) {
                  if (value == gradeService.academicYear.value) return;

                  setState(() {
                    gradeService.academicYear = AcademicYear(value);
                  });
                },
              ),
              Text('学年'),
              SizedBox(width: 20),
              DropdownButton(
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
                      (TimeLimit tl) =>
                          DropdownMenuItem(value: tl, child: Text(tl.name)),
                    )
                    .toList(),
              ),
              DropdownButton(
                value: gradeService.semesterType,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                dropdownColor: Colors.white,
                focusColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                underline: const SizedBox.shrink(), // 隐藏下划线
                onChanged: gradeService.timeLimit != .semester
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
                      (SemesterType st) =>
                          DropdownMenuItem(value: st, child: Text(st.name)),
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
                    gradeService.nextCourseFilter();
                    _futureGradeText = buildGradeText();
                  }),
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: gradeService.courseFilter.displayColor,
                ),
                child: Text(gradeService.courseFilter.displayText),
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

          Row(
            children: [
              ToggleButton(text: '序号'),
              ToggleButton(text: '课程代码'),
              ToggleButton(text: '课程名称', initialValue: true),
              ToggleButton(text: '学分', initialValue: true),
              ToggleButton(text: '类别'),
              ToggleButton(text: '修读性质'),
              ToggleButton(text: '考核方式'),
              ToggleButton(text: '成绩', initialValue: true),
              ToggleButton(text: '获得学分'),
              ToggleButton(text: '绩点', initialValue: true),
              ToggleButton(text: '学分绩点', initialValue: true),
              ToggleButton(text: '备注'),
            ],
          ),

          FutureBuilder(
            future: _futureWeightedTable,
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

          FutureBuilder(
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

extension _GradeTableShow on GradeTable {
  CourseGrade operator [](int i) => grades[i];

  DataTable toTable() {
    final tmp = [
      '序号',
      '课程/环节',
      '学分',
      '类别',
      '修读性质',
      '考核方式',
      '成绩',
      '获得学分',
      '绩点',
      '学分绩点',
      '备注',
    ];
    return DataTable(
      columns: tmp.map((text) => DataColumn(label: Text(text))).toList(),
      rows: grades
          .map(
            (CourseGrade courseGrade) => DataRow(
              cells: tmp
                  .sublist(1)
                  .map((t) => DataCell(Text(courseGrade[t])))
                  .toList(),
            ),
          )
          .toList(),
    );
  }
}

extension _CourseGradeShow on CourseGrade {
  String operator [](String property) => switch (property) {
    '课程代码' => course.code,
    '课程名称' => course.name,
    '课程学分' => course.credit.toStringAsFixed(1),
    '课程类别' => course.mainCategory.toString(),
    '考核方式' => course.assessmentMethod.toString(),
    '修读性质' => attempt.toString(),
    '成绩' => score.toStringAsFixed(1),
    '学分' => credit.toStringAsFixed(1),
    '绩点' => gradePoint.toStringAsFixed(1),
    '学分绩点' => gradePointCredit.toStringAsFixed(1),
    '备注' => remark,
    _ => '未知的属性: "$property"',
  };
}

extension SubjectFilterStyle on CourseFilter {
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
