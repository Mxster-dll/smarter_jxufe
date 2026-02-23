import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smarter_jxufe/Log.dart';
import 'package:smarter_jxufe/Services/JxufeLogin.dart';

class GradeService {
  late final Dio _dio;
  final LoginService _loginService;

  String? _jSessionId;
  String? get jSessionId => _jSessionId;

  Future<void> setJSessionId(String? id) async {
    _jSessionId = id;

    final pref = await SharedPreferences.getInstance();
    if (id == null) {
      _dio.options.headers.remove('Cookie');
      pref.remove('JSESSIONID');
    } else {
      _dio.options.headers['Cookie'] = 'JSESSIONID=$id';
      pref.setString('JSESSIONID', id);
    }
  }

  void clearJSessionId() => setJSessionId(null);

  Future<void> loadJSessionId() async {
    final pref = await SharedPreferences.getInstance();
    _jSessionId = pref.getString('JSESSIONID');

    if (_jSessionId == null) {
      _dio.options.headers.remove('Cookie');
    } else {
      _dio.options.headers['Cookie'] = 'JSESSIONID=$_jSessionId';
    }
  }

  WeightedType weightedType = WeightedType.courseAll;
  TimeLimit timeLimit = TimeLimit.semester;
  bool showRawGrade = false;
  bool onlyNotPassed = false;
  SemesterType semesterType = SemesterType.first;
  AcademicYear academicYear = AcademicYear.thisYear;
  SubjectFilter subjectFilter = SubjectFilter.all;

  bool get selectedMajor => subjectFilter != SubjectFilter.minor;
  bool get selectedMinor => subjectFilter != SubjectFilter.major;

  void nextSubjectFilter() {
    subjectFilter = SubjectFilter
        .values[(subjectFilter.index + 1) % SubjectFilter.values.length];
  }

  GradeService(this._loginService) {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://jwxt.jxufe.edu.cn',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'sec-ch-ua':
              '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'Referer': 'http://ehall.jxufe.edu.cn/',
        },
        responseDecoder: (bytes, options, response) {
          final encoding = getCharset(response.headers['Content-Type']);

          return switch (encoding) {
            'gbk' || 'gb2312' => gbk.decode(bytes),
            'utf-8' => utf8.decode(bytes),
            _ => utf8.decode(bytes),
          };
        },
        followRedirects: false,
        validateStatus: (status) => true,
      ),
    );
  }

  String getCharset(List<String>? vs) {
    if (vs == null || vs.isEmpty) return '';

    final lowerCase = vs.first.toLowerCase();
    final match = RegExp(r'charset=([^;]+)').firstMatch(lowerCase);

    return match?.group(1)?.trim() ?? '';
  }

  /// 如果无 JSESSIONID 则返回 JSESSIONID
  /// 如果有 JSESSIONID 则为激活 JSESSIONID 的一步
  /// 返回当前 JSESSIONID 是否有效
  Future<bool> casLogin() async {
    final queryParameters = {
      't_s': DateTime.now().millisecondsSinceEpoch,
      'amp_sec_version_': '1',
      'gid_': _loginService.gid,
      'EMAP_LANG': 'zh',
      'THEME': 'cherry',
    };

    try {
      final response = await _dio.get(
        '/jxcjcaslogin',
        queryParameters: queryParameters,
      );

      if (_jSessionId != null) return true;

      final setCookie = response.headers['set-cookie'];
      if (setCookie == null) throw Exception('缺少 set-cookie');

      if (setCookie.length != 1) {
        throw Exception(
          '期望仅有1项 Cookie，但找到了${setCookie.length}个 Cookie\n $setCookie',
        );
      }

      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie.first);

      await setJSessionId(match?.group(1));
      if (_jSessionId == null) throw Exception('缺少 JSESSIONID');
    } catch (e) {
      logError('登录请求异常: $e\n');
    }

    return false;
  }

  Future<void> fetchJSessionId() async {
    if (await casLogin()) return;

    await casLogin();

    final url = await _loginService.redirectImsUrl();
    await _dio.get(url);
  }

  Future<WeightedGrade?> getWeightedGrade() async {
    if (_jSessionId == null) await fetchJSessionId();

    final response = await _dio.post(
      '/student/xscj.jqchjpm_data10421.jsp',
      data: {'jqlx': weightedType.id, 'menucode_current': 'S40309'},
      options: Options(
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );

    final String? html = response.data;
    if (html == null) throw Exception('空的响应体');
    if (html.contains('没有检索到记录!')) throw Exception('没有检索到记录!');
    if (html.contains('温馨提示：凭证已失效，请重新登录!')) {
      throw Exception('温馨提示：凭证已失效，请重新登录!');
    }

    final tables = parse(html).getElementsByTagName('table');

    if (tables.length != 1) {
      logInfo(html);
      throw Exception('期望有1个 table，但找到了${tables.length}个 table\n $tables');
    }

    List<List<String>> m = toMatrix(tables.first);
    return WeightedGrade.fromMap(Map.fromIterables(m[0], m[1]));
  }

  List<List<String>> toMatrix(dom.Element table) => table
      .querySelectorAll('tr')
      .map(
        (dom.Element row) => row
            .querySelectorAll('th, td')
            .map((dom.Element cell) => cell.text)
            .toList(),
      )
      .toList();

  final sem2xq = {
    SemesterType.first: '0',
    SemesterType.second: '1',
    SemesterType.next: '2',
  };

  Future<Widget?> getGrade() async {
    await Future.delayed(Duration(milliseconds: 1000));
    if (_jSessionId == null) await fetchJSessionId();

    try {
      final response = await _dio.post(
        '/student/xscj.stuckcj_data10421.jsp',
        data: {
          'sjxz': timeLimit.value, // 时间限制
          'ysyx': showRawGrade ? 'yscj' : 'yxcj', // 原始有效 原始成绩 有效成绩
          'zx': selectedMajor ? 1 : 0, // 主修
          'fx': selectedMinor ? 1 : 0, // 辅修
          if (selectedMajor) 'zxC': 'on', // ？？
          if (selectedMinor) 'fxC': 'on', // ？？
          if (onlyNotPassed) 'xwtg': 1, // 限未通过
          'rxnj': '2025', // TODO 待实现获取功能
          'nj': '2025', // TODO 待实现获取功能
          'btnExport': '%B5%BC%B3%F6',
          if (timeLimit != TimeLimit.sinceEnrollment)
            'xn': academicYear.year, // 学年下界
          'xn1': timeLimit == TimeLimit.sinceEnrollment
              ? AcademicYear.thisYear.year
              : academicYear.nextYear.year, // 学年上界
          if (timeLimit == TimeLimit.semester) 'xq': sem2xq[semesterType], // 学期
          'ysyxS': 'on',
          'sjxzS': 'on',
          'xsjd': '1',
          'menucode_current': 'S40303',
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer':
                'https://jwxt.jxufe.edu.cn/student/xscj.stuckcj.jsp?menucode=S40303',
          },
        ),
      );

      final String? html = response.data;
      if (html == null) throw Exception('空的响应体');
      if (html.contains('没有检索到记录!')) throw Exception('没有检索到记录!');
      if (html.contains('温馨提示：凭证已失效，请重新登录!')) {
        throw Exception('温馨提示：凭证已失效，请重新登录!');
      }

      final tables = parse(html).querySelectorAll('table').where((table) {
        final style = table.attributes['style'];
        if (style == null) return true;

        return !style.contains('border:none');
      }).toList();

      if (tables.length != 2) {
        logInfo(html);
        throw Exception('期望有2个 table，但找到了${tables.length}个 table\n $tables');
      }

      DataTable buildTable(dom.Element table) {
        final m = toMatrix(table);

        return DataTable(
          columns: m[0].map((cell) => DataColumn(label: Text(cell))).toList(),
          rows: m
              .sublist(1)
              .map(
                (List<String> line) => DataRow(
                  cells: line.map((cell) => DataCell(Text(cell))).toList(),
                ),
              )
              .toList(),
        );
      }

      return Column(
        children: [buildTable(tables.first), buildTable(tables[1])],
      );
    } catch (e) {
      return Text('查询成绩异常: $e\n');
    }
  }
}

enum WeightedType {
  courseAll('课程加权（所有学年）', 1),
  courseLastYear('课程加权（上学年）', 2),
  courseLastTerm('课程加权（上学期）', 3),
  // diversion( '分流加权', 4),
  graduate('毕业加权', 5),
  minor('辅修加权', 6),
  gradRec('推免加权', 7);

  const WeightedType(this.name, this.id);

  final String name;
  final int id;
}

class GradeTable {
  final List<SubjectGrade> grades;
  final double gpa;

  GradeTable(this.grades, this.gpa);
}

class SubjectGrade {
  final Subject subject;
  final String courseNature;
  final double score;
  final double credit;
  final double gradePoint;
  final double gradePointCredit;
  final String remark;

  SubjectGrade(
    this.subject,
    this.courseNature,
    this.score,
    this.credit,
    this.gradePoint,
    this.gradePointCredit,
    this.remark,
  );
}

enum SubjectCategory {
  compulsoryCourse,
  publicCourse2024,
  publicMathematicsCourse,
}

enum Subject {
  advancedMathematicsI('1004701034', '高等数学I', 4.0, [
    SubjectCategory.compulsoryCourse,
    SubjectCategory.publicCourse2024,
    SubjectCategory.publicMathematicsCourse,
  ], '考试');

  const Subject(
    this.code,
    this.name,
    this.credit,
    this.category,
    this.assessmentMethod,
  );

  final String code;
  final String name;
  final double credit;
  final List<SubjectCategory> category;
  final String assessmentMethod;
}

class WeightedGrade {
  final String grade;
  final int classRank, majorRank, gradeRank;

  WeightedGrade(this.grade, this.classRank, this.majorRank, this.gradeRank);

  static WeightedGrade fromMap(Map<String, dynamic> weightedGrade) {
    final grade = weightedGrade['课程加权成绩'];
    if (grade == null) throw Exception('缺少 "课程加权成绩"');

    int extractRank(String key) {
      final rankText = weightedGrade[key];
      if (rankText == null) throw Exception('缺少 "$key"');

      final rank = int.tryParse(rankText);
      if (rank == null) throw Exception('"$key" 格式错误');

      return rank;
    }

    return WeightedGrade(
      grade,
      extractRank('班级排名'),
      extractRank('专业排名'),
      extractRank('年级排名'),
    );
  }

  @override
  String toString() =>
      '''

::加权成绩排名::
课程加权成绩: $grade
班级排名: $classRank
专业排名: $majorRank
年级排名: $gradeRank

''';
}

enum SubjectFilter { major, minor, all }

enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.name, this.value);

  final String name;
  final String value;
}

enum SemesterType {
  first('第一学期', 1),
  second('第二学期', 2),
  next('第二阶段', -1);

  const SemesterType(this.name, this.code);

  final String name;
  final int code;
}

class AcademicYear {
  final int year;

  AcademicYear._internal(this.year);

  static final Map<int, AcademicYear> _cache = {};

  factory AcademicYear.of(int year) {
    if (year < 1976 || year > 2099) throw Exception('日期超限：year=$year');

    return _cache.putIfAbsent(year, () => AcademicYear._internal(year));
  }

  @override
  String toString() => '$year-${year + 1}学年';

  String get short {
    final str = year.toString();

    assert(str.length == 4);
    return str.substring(str.length - 2);
  }

  static AcademicYear get thisYear => AcademicYear.of(DateTime.now().year);

  AcademicYear get nextYear => AcademicYear.of(year + 1);
  AcademicYear get lastYear => AcademicYear.of(year - 1);

  AcademicYear operator +(int interval) => AcademicYear.of(year + interval);
  AcademicYear operator -(int interval) => AcademicYear.of(year - interval);
}

class Semester {
  final AcademicYear year;
  final SemesterType type;

  const Semester(this.year, this.type);

  @override
  String toString() => '$year${type.name}';

  String get code => '${year.short}${type.code}';
}
