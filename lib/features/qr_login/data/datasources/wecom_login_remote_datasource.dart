import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

/// 企业微信登录远程数据源（暂未实现）
class WecomLoginRemoteDataSource {
  /// 预留：实现企业微信登录时用（整条链路当前未开放，见下方各方法的
  /// `UnimplementedError`）。**抑制范围收窄到这一行**——原来是文件级
  /// `ignore_for_file: unused_field`，那会把将来真正的未使用字段一起盖住。
  // ignore: unused_field
  final Dio _dio;

  WecomLoginRemoteDataSource(this._dio);

  Future<void> process() {
    throw UnimplementedError('企业微信登录暂未开放');
  }

  Future<QrCodeStatus?> pollStatus() {
    throw UnimplementedError('企业微信登录暂未开放');
  }

  Future<void> refreshQrCode() {
    throw UnimplementedError('企业微信登录暂未开放');
  }
}
