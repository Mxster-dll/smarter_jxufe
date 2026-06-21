
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

class WecomLoginRemoteDataSource {
  final Dio _dio; // 预留，后续实现使用

  WecomLoginRemoteDataSource(this._dio);

  Future<void> process() {
    throw UnimplementedError('企业微信登录暂未开放');
  }

  Future<QrCodeStatus?> pollStatus() {
    // TODO: implement pollStatus
    throw UnimplementedError('企业微信登录暂未开放');
  }

  Future<void> refreshQrCode() {
    throw UnimplementedError('企业微信登录暂未开放');
  }
}
