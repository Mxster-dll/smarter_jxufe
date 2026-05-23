import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_providers.g.dart';

final _imsDio = Dio(
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
    followRedirects: false,
    validateStatus: (status) => true,
    responseDecoder: (bytes, options, response) {
      final contentType = response.headers['Content-Type']?.first;
      final charset = _extractCharset(contentType);
      switch (charset) {
        case 'gbk':
        case 'gb2312':
          return gbk.decode(bytes);
        default:
          return utf8.decode(bytes);
      }
    },
  ),
);

// 可选：添加日志拦截器方便调试（生产环境可移除）
// dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));

@riverpod
Dio imsDio(ImsDioRef ref) => _imsDio;

String _extractCharset(String? contentType) {
  if (contentType == null) return '';
  final match = RegExp(
    r'charset=([^;]+)',
  ).firstMatch(contentType.toLowerCase());
  return match?.group(1)?.trim() ?? '';
}

@riverpod
Dio loginDio(LoginDioRef ref) {
  return Dio(
    BaseOptions(
      baseUrl: 'https://ssl.jxufe.edu.cn',
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ),
  );
}
