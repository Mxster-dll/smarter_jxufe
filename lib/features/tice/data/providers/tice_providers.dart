import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';

/// 体测成绩数据源（独立 Dio，不经过 IMS 认证拦截器）。
final ticeRemoteDataSourceProvider = Provider<TiceRemoteDataSource>(
  (ref) => TiceRemoteDataSource(),
);
