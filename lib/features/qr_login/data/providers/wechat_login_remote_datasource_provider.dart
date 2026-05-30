import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/qr_login/data/datasources/wechat_login_remote_datasource.dart';

part 'wechat_login_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
WechatLoginRemoteDataSource wechatLoginRemoteDataSource(
  WechatLoginRemoteDataSourceRef ref,
) {
  // 微信登录需要更长的超时时间（长轮询）
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));
  return WechatLoginRemoteDataSource(dio);
}
