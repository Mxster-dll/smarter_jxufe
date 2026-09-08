import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/tice/data/models/tice_models.dart';

/// 「赛康精益」国家体测成绩远程数据源。
///
/// 后端零鉴权（无 token/签名/绑定校验），仅需学号 + 学校 + 测试窗口日期；
/// 微信小程序里「解绑/重绑才能查多人」只是前端限制，本数据源只查登录本人。
/// 窗口日期约定：学年第 [year] 秋季测试窗口内任意日期即可命中该学年成绩，
/// 统一取 `$year-11-01`。
class TiceRemoteDataSource {
  TiceRemoteDataSource({Dio? dio}) : _dio = dio ?? _buildDio();

  final Dio _dio;

  static const _base = 'https://www.skjycx.com';
  static const _school = '江西财经大学';

  static Dio _buildDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.bytes, // 自行按 UTF-8 解码，不依赖 charset 探测
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 '
                  'MicroMessenger/7.0.20.1781(0x6700143B) NetType/WIFI '
                  'MiniProgramEnv/Windows WindowsWechat/WMPF',
          'Referer':
              'https://servicewechat.com/wx6ff9ff67c25de356/44/page-frame.html',
        },
      ),
    );
  }

  /// 查询 [stuNum] 在 [year] 学年秋季窗口的体测成绩。
  ///
  /// 网络/解析错误抛 [TiceRequestException]（中文文案，供页面直接展示）；
  /// 接口业务失败（未上传/免测等）不抛异常，返回 [TiceResult.ok=false]。
  Future<TiceResult> query(String stuNum, int year) async {
    final String text;
    try {
      final resp = await _dio.post<dynamic>(
        '$_base/src/StuSpace/queryStuResult.php',
        data: {
          'stuNum': stuNum,
          'stuSchool': _school,
          'StartTestDate': '$year-11-01',
          'openid': 'smarter_jxufe_app',
          'nickName': '登录',
          'userUrl': '../../static/img/loginIcon.png',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final bytes = resp.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw TiceRequestException('服务器返回为空（HTTP ${resp.statusCode}）');
      }
      text = utf8.decode(bytes, allowMalformed: true);
    } on DioException catch (e) {
      throw TiceRequestException(_dioMessage(e));
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw TiceRequestException('响应不是有效 JSON：${_clip(text)}');
    }
    if (decoded is! Map) {
      throw TiceRequestException('响应结构异常：${_clip(text)}');
    }
    final map = decoded.map((k, v) => MapEntry(k.toString(), v));

    final message = (map['message'] as String?)?.trim() ?? '';
    if ('${map['result']}' != '1') {
      return TiceResult(ok: false, message: message.isEmpty ? '查询失败' : message);
    }

    final data = map['data'];
    final dataMap = data is Map
        ? data.map((k, v) => MapEntry(k.toString(), v))
        : const <String, Object?>{};

    TiceStuInfo? info;
    final stuInfo = dataMap['stuInfo'];
    if (stuInfo is Map) {
      final si = stuInfo.map((k, v) => MapEntry(k.toString(), v));
      info = TiceStuInfo(
        stuNum: '${si['stuNum'] ?? ''}',
        stuName: '${si['stuName'] ?? ''}',
        stuSex: '${si['stuSex'] ?? ''}',
        gradeNum: '${si['gradeNum'] ?? ''}',
        deptName: '${si['deptName'] ?? ''}',
      );
    }

    final years = <TiceYearResult>[];
    final stuResult = dataMap['stuResult'];
    if (stuResult is List) {
      for (final entry in stuResult) {
        if (entry is! Map) continue;
        final yr = entry.map((k, v) => MapEntry(k.toString(), v));
        final yearText = '${yr['year'] ?? ''}';
        final total = yr['totalResult'];
        final totalMap = total is Map
            ? total.map((k, v) => MapEntry(k.toString(), v))
            : const <String, Object?>{};
        final items = <TiceItem>[];
        final resultMap = yr['Result'];
        if (resultMap is Map) {
          resultMap.forEach((rawCode, value) {
            final code = rawCode.toString();
            items.add(TiceItem.fromJson(code, value));
          });
        }
        years.add(
          TiceYearResult(
            year: int.tryParse(yearText) ?? year,
            totalScore: double.tryParse('${totalMap['totalScore'] ?? ''}'),
            totalGrade: '${totalMap['totalClass'] ?? ''}',
            items: items,
          ),
        );
      }
    }
    years.sort((a, b) => a.year.compareTo(b.year));

    return TiceResult(
      ok: years.isNotEmpty,
      message: years.isEmpty ? '无成绩记录' : message,
      info: info,
      years: years,
    );
  }

  String _dioMessage(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        '连接超时，请检查网络后重试',
      DioExceptionType.connectionError => '无法连接服务器，请检查网络后重试',
      DioExceptionType.badResponse => '服务器错误（HTTP ${e.response?.statusCode}）',
      _ => '网络请求失败：${e.message ?? e.type.name}',
    };
  }

  static String _clip(String text) =>
      text.length > 200 ? '${text.substring(0, 200)}…' : text;
}

/// 体测查询的网络/解析错误（文案可直接展示给用户）。
class TiceRequestException implements Exception {
  final String message;
  const TiceRequestException(this.message);

  @override
  String toString() => message;
}
