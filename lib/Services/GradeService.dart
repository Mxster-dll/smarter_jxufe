import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'package:smarter_jxufe/Services/JxufeLogin.dart';

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

class GradeService {
  late final Dio _dio;

  String? _jSessionId;
  final String gid;

  String? get jSessionId => _jSessionId;
  set jSessionId(String? id) {
    _jSessionId = id;

    if (id == null) {
      _dio.options.headers.remove('Cookie');
    } else {
      _dio.options.headers['Cookie'] = 'JSESSIONID=$id';
    }
  }

  void clearJSessionId() {
    _jSessionId = null;
    _dio.options.headers.remove('Cookie');
  }

  /// 构造函数
  /// [gid] 必须提供，是从统一门户跳转时携带的加密参数
  /// [initialJSessionid] 可选，如果已有JSESSIONID可直接传入
  GradeService({required this.gid, String? initialJSessionid}) {
    _jSessionId = initialJSessionid;
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

  // TODO 可持续化 JSESSIONID
  String? getJSessionId(List<String> setCookie) {
    for (var cookie in setCookie) {
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(cookie);

      if (match != null) return match.group(1);
    }

    return null;
  }

  /// 如果无 JSESSIONID 则返回 JSESSIONID
  /// 如果有 JSESSIONID 则为激活 JSESSIONID 的一步
  /// 返回当前 JSESSIONID 是否有效
  Future<bool> casLogin() async {
    final ms = DateTime.now().millisecondsSinceEpoch;

    final queryParameters = {
      't_s': ms.toString(), // TODO 去掉
      'amp_sec_version_': '1',
      'gid_':
          'S3lvSGM0NjRtSEtYcGhMcjZ2byszZnlGU0VkeXdGSTNOdllhckgyQVRaVnhhNi8zTUxRQ2hvWjhDbmlodWo1d0lVNGRzbDdqZ3hXU2FJYmxrK054TlE9PQ',
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

      jSessionId = getJSessionId(setCookie);
      if (_jSessionId == null) throw Exception('缺少 JSESSIONID');
    } catch (e) {
      print('登录请求异常: $e');
    }

    return false;
  }

  Future<void> fetchJSessionId() async {
    if (await casLogin()) return;

    await casLogin();

    final LoginService loginService = LoginService();
    final url = await loginService.redirectImsUrl();
    await _dio.get(url);
  }

  Future<String?> getWeightedGrade(WeightedType wt, {int depth = 1}) async {
    if (_jSessionId == null) await fetchJSessionId();

    try {
      final response = await _dio.post(
        '/student/xscj.jqchjpm_data10421.jsp',
        data: {'jqlx': wt.id, 'menucode_current': 'S40309'},
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.data.toString().contains('温馨提示：凭证已失效，请重新登录!')) {
        if (depth > 1) throw Exception('尝试失败');

        clearJSessionId();
        return getWeightedGrade(wt, depth: 2);
      }

      return response.data;
    } catch (e) {
      print('查询成绩异常: $e');
      return null;
    }
  }

  final sem2xq = {
    SemesterType.first: '0',
    SemesterType.second: '1',
    SemesterType.next: '2',
  };

  Future<String?> getGrade({
    int depth = 1,
    required TimeLimit timeLimit, // 这个应该可以通过其他参数自适应
    // ysyx: yscj,
    // zx: 1,
    // fx: 1,
    // rxnj: 2025,
    // nj: 2025,
    // btnExport: %B5%BC%B3%F6,
    SemesterType? semType,
    AcademicYear? year,
    // ysyxS: on,
    // sjxzS: on,
    // zxC: on,
    // fxC: on,
    // xsjd: 1,
    // menucode_current: S40303,
  }) async {
    if (_jSessionId == null) await fetchJSessionId();

    try {
      final response = await _dio.post(
        '/student/xscj.jqchjpm_data10421.jsp',
        data: {
          'sjxz': timeLimit.name, // 时间限制
          'ysyx': 'yscj',
          'zx': '1',
          'fx': '1',
          'rxnj': '2025',
          'nj': '2025',
          'btnExport': '%B5%BC%B3%F6',
          'xn': ?year, // 学年下界
          'xn1': year?.nextYear ?? AcademicYear.thisYear, // 学年上界
          'xq': ?sem2xq[semType], // 学期
          'ysyxS': 'on',
          'sjxzS': 'on',
          'zxC': 'on',
          'fxC': 'on',
          'xsjd': '1',
          'menucode_current': 'S40303',
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.data.toString().contains('温馨提示：凭证已失效，请重新登录!')) {
        if (depth > 1) throw Exception('尝试失败');
      }

      return response.data;
    } catch (e) {
      print('查询成绩异常: $e');
      return null;
    }
  }
}

enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学年', 'sjxz3');

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
    if (year < 2000 || year > 2099) throw Exception('日期超限：year=$year');

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
