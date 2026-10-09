import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/school_calendar_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/data/school_calendar_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

// 「当下学期」判定已提取为纯域函数（校历区间优先 + 月份兜底），见
// domain/school_term.dart。这里 re-export 以保持既有 import 路径可用。
export 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';

/// 教务系统公开页专用 Dio（免登录，不挂 IMS 认证拦截器）。
///
/// 响应为 GBK 编码的 HTML：与 IMS 会话那条链共用
/// `core/network/dio_factory.dart` 的 [gbkAwareResponseDecoder]（按
/// Content-Type 字符集自动解码），不再各写一份 charset 探测。
final schoolCalendarDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return createAppDio(
    baseUrl: 'https://jwxt.jxufe.edu.cn',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    userAgent: deviceProfileRepo.userAgent,
    headers: {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
    responseDecoder: gbkAwareResponseDecoder(),
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
