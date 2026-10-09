import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/wechat_login_remote_datasource.dart';

part 'wechat_login_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
WechatLoginRemoteDataSource wechatLoginRemoteDataSource(
  WechatLoginRemoteDataSourceRef ref,
) {
  // 微信登录需要更长的超时时间（长轮询）
  final dio = createAppDio(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    // ⚠ 这一个必须保持「非 2xx 抛异常」的严格语义（与校园站点抓取相反）：
    // 微信登录靠 `DioException` 分支报错，不能改成「什么都算成功」。
    validateStatus: rejectNon2xxStatus,
  );
  return WechatLoginRemoteDataSource(dio);
}
