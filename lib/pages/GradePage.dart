import 'package:flutter/material.dart';

import 'package:smarter_jxufe/Services/GradeService.dart';
import 'package:smarter_jxufe/Services/JxufeLogin.dart';
import 'package:smarter_jxufe/Widgets/AcademicYearPicker.dart';
import 'package:smarter_jxufe/IMS/AcademicTime.dart';
import 'package:smarter_jxufe/IMS/Subject.dart';
import 'package:smarter_jxufe/IMS/Grades.dart';

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
                  if (value == gradeService.academicYear.value) return;

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
