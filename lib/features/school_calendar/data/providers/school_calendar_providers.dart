import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/school_calendar_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/data/school_calendar_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 教务系统公开页专用 Dio（免登录，不挂 IMS 认证拦截器）。
///
/// 响应为 GBK 编码的 HTML，这里与 [imsDioProvider] 一样按
/// Content-Type 字符集自动解码为 String。
final schoolCalendarDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://jwxt.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
      responseDecoder: (bytes, options, response) {
        final contentType = response.headers['Content-Type']?.first;
        final charsetMatch =
            RegExp(r'charset=([^;]+)').firstMatch(contentType ?? '');
        final charset = charsetMatch?.group(1)?.trim().toLowerCase() ?? '';
        return switch (charset) {
          'gbk' || 'gb2312' => gbk.decode(bytes),
          _ => utf8.decode(bytes),
        };
      },
    ),
  );
});

/// 校历远程数据源。
final schoolCalendarRemoteDataSourceProvider =
    Provider<SchoolCalendarRemoteDataSource>(
  (ref) => SchoolCalendarRemoteDataSource(
    ref.watch(schoolCalendarDioProvider),
  ),
);

/// 校历 HTML 解析器。
final schoolCalendarHtmlParserProvider = Provider<SchoolCalendarHtmlParser>(
  (ref) => SchoolCalendarHtmlParser(),
);

/// 校历仓库。
final schoolCalendarRepositoryProvider = Provider<SchoolCalendarRepository>(
  (ref) => SchoolCalendarRepository(
    ref.watch(schoolCalendarRemoteDataSourceProvider),
    ref.watch(schoolCalendarHtmlParserProvider),
  ),
);

/// (学年起始年, 学段) → 该学段校历。失败抛出异常供页面呈现。
final schoolCalendarProvider =
    FutureProvider.family<SchoolCalendar, ({int xn, int xq})>(
  (ref, term) async {
    final repo = ref.watch(schoolCalendarRepositoryProvider);
    return repo.fetchCalendar(xn: term.xn, xq: term.xq);
  },
);

/// 由当前日期推「此刻正在进行的学段」：与课表学期口径一致。
///
/// 3~8 月 → (上年, 第二学期 xq=1)；其余月份 → (当年, 第一学期 xq=0)。
/// （第二阶段/暑期校历不默认展示，用户可手动切到 xq=2。）
({int xn, int xq}) currentSchoolTerm(DateTime now) {
  final m = now.month;
  if (m >= 3 && m <= 8) {
    return (xn: now.year - 1, xq: 1);
  }
  return (xn: now.year, xq: 0);
}
