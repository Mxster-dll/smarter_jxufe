// ignore_for_file: unused_field

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

/// 企业微信登录远程数据源（暂未实现）
class WecomLoginRemoteDataSource {
  final Dio _dio; // 预留，后续实现使用

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
