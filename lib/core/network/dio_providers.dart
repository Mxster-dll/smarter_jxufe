// import 'dart:convert';
// import 'package:dio/dio.dart';
// import 'package:fast_gbk/fast_gbk.dart';
// import 'package:riverpod_annotation/riverpod_annotation.dart';

// part 'dio_providers.g.dart';

// /// 提供专用于江西财经大学统一登录（SSL）的 Dio 实例
// @riverpod
// Dio jxufeLoginDio(JxufeLoginDioRef ref) {
//   final dio = Dio(
//     BaseOptions(
//       baseUrl: 'https://ssl.jxufe.edu.cn',
//       validateStatus: (status) => true, // 不抛出异常，自行处理状态码
//       followRedirects: false, // 关闭自动重定向，手动处理
//       headers: {
//         'User-Agent':
//             'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
//       },
//     ),
//   );

//   // 可选：添加日志拦截器便于调试
//   // dio.interceptors.add(LogInterceptor(responseBody: true));

//   return dio;
// }

// @riverpod
// Dio imsDio(ImsDioRef ref) {
//   final dio = Dio(
//     BaseOptions(
//       baseUrl: 'https://jwxt.jxufe.edu.cn',
//       headers: {
//         'User-Agent':
//             'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
//         'Accept':
//             'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
//         'Accept-Language': 'zh-CN,zh;q=0.9',
//         'sec-ch-ua':
//             '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
//         'sec-ch-ua-mobile': '?0',
//         'sec-ch-ua-platform': '"Windows"',
//         'Referer': 'http://ehall.jxufe.edu.cn/',
//       },
//       responseDecoder: (bytes, options, response) {
//         final encoding = getCharset(response.headers['Content-Type']);

//         return switch (encoding) {
//           'gbk' || 'gb2312' => gbk.decode(bytes),
//           'utf-8' => utf8.decode(bytes),
//           _ => utf8.decode(bytes),
//         };
//       },
//       followRedirects: false,
//       validateStatus: (status) => true,
//     ),
//   );
//   return dio;
// }

// String getCharset(List<String>? vs) {
//   if (vs == null || vs.isEmpty) return '';

//   final lowerCase = vs.first.toLowerCase();
//   final match = RegExp(r'charset=([^;]+)').firstMatch(lowerCase);

//   return match?.group(1)?.trim() ?? '';
// }
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/old/ims/data/repositories/ims/ImsService.dart';

part 'dio_providers.g.dart';

final imsService = ImsService();

@riverpod
Dio imsDio(ImsDioRef ref) {
  return imsService.dio;
}
