import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:get_storage/get_storage.dart';

import 'package:smarter_jxufe/utils/Log.dart';
import 'package:smarter_jxufe/login/JxufeLogin.dart';

// TODO 增加账号管理
// 依据账号实现单例模式
// 默认使用当前账号创建实例
class ImsService {
  final box = GetStorage();
  late final Dio dio;
  late final LoginService _loginService;

  String? _jSessionId;
  String? get jSessionId => _jSessionId;

  void setJSessionId(String? id) {
    _jSessionId = id;

    if (id == null) {
      dio.options.headers.remove('Cookie');
      box.remove('JSESSIONID');
    } else {
      dio.options.headers['Cookie'] = 'JSESSIONID=$id';
      box.write('JSESSIONID', id);
    }
  }

  void clearJSessionId() => setJSessionId(null);

  void loadJSessionId() {
    _jSessionId = box.read('JSESSIONID');

    if (_jSessionId == null) {
      dio.options.headers.remove('Cookie');
    } else {
      dio.options.headers['Cookie'] = 'JSESSIONID=$_jSessionId';
    }
  }

  // BUG 对单个账号未实现单例模式
  ImsService([LoginService? loginService]) {
    _loginService = loginService ?? LoginService();

    dio = Dio(
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

    loadJSessionId();
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
      final response = await dio.get(
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

      setJSessionId(match?.group(1));
      if (_jSessionId == null) throw Exception('缺少 JSESSIONID');
    } catch (e) {
      logError('登录请求异常: $e\n');
    }

    return false;
  }

  Future<void> fetchJSessionId() async {
    if (_jSessionId != null || await casLogin()) return;

    await casLogin();

    final url = await _loginService.redirectImsUrl();
    await dio.get(url);
  }
}
