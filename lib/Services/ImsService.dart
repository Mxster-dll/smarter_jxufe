import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:smarter_jxufe/Services/JxufeLogin.dart';
import 'dart:convert';

class ImsService {
  late final Dio _dio;
  String? _jSessionId;
  final String gid;

  // 加权类型
  static const Map<String, int> jqlx = {
    '课程加权（所有学年）': 1,
    '课程加权（上学年）': 2,
    '课程加权（上学期）': 3,
    // '分流加权': 4,
    '毕业加权': 5,
    '辅修加权': 6,
    '推免加权': 7,
  };

  /// 构造函数
  /// [gid] 必须提供，是从统一门户跳转时携带的加密参数
  /// [initialJSessionid] 可选，如果已有JSESSIONID可直接传入
  ImsService({required this.gid, String? initialJSessionid}) {
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
              '"Not:A-Brand";v="99", "Microsoft Edge";vdddsccxz="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'Referer': 'http://ehall.jxufe.edu.cn/',
        },
        followRedirects: false,
        validateStatus: (status) => true,
      ),
    );
  }

  String? getJSessionId(List<String> setCookie) {
    for (var cookie in setCookie) {
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(cookie);

      if (match != null) return match.group(1);
    }

    return null;
  }

  /// 如果无 JSESSIONID 则返回 JSESSIONID
  /// 如果有 JSESSIONID 则为激活 JSESSIONID 的一步
  Future<void> casLogin() async {
    final ms = DateTime.now().millisecondsSinceEpoch.toString();

    final queryParameters = {
      't_s': '$ms', // 请注意：此时间戳可能已过期，建议动态生成
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

      if (_jSessionId != null) return;

      final setCookie = response.headers['set-cookie'];
      if (setCookie == null) throw Exception('缺少 set-cookie');

      _jSessionId = getJSessionId(setCookie);
      if (_jSessionId == null) throw Exception('缺少 JSESSIONID');

      _dio.options.headers['Cookie'] = 'JSESSIONID=$_jSessionId';
    } catch (e) {
      print('登录请求异常: $e');
    }
  }

  Future<void> redirect(String url) async {
    try {
      _dio.get(url);
    } catch (e) {}
  }

  Future<void> fetchJSessionId() async {
    _jSessionId = null;

    // 两个 casLogin 都是必要的，第一个刷新 JSESSIONID
    // 第二个为激活 JSESSIONID 的其中一步
    await casLogin();
    await casLogin();

    final LoginService loginService = LoginService();
    final url = await loginService.redirectImsUrl();
    await redirect(url);
  }

  /// 查询成绩
  Future<String?> getGrade() async {
    if (_jSessionId == null) {
      print('请先登录获取JSESSIONID');
      return null;
    }

    try {
      final response = await _dio.post(
        '/student/xscj.jqchjpm_data10421.jsp',
        data: 'jqlx=1&menucode_current=S40309',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          responseType: ResponseType.bytes,
        ),
      );

      return gbk.decode(response.data);
    } catch (e) {
      print('查询成绩异常: $e');
      return null;
    }
  }
}
