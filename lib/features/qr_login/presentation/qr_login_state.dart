import 'dart:typed_data';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

/// QR登录 UI 状态
class QrLoginState {
  final QrCodeStatus status;
  final Uint8List? qrImage;
  final String? verifyCode;
  final String title;
  final String info;
  final String hintText;
  final String username;
  final String displayName;
  final bool trustDevice;

  const QrLoginState({
    this.status = QrCodeStatus.loading,
    this.qrImage,
    this.verifyCode,
    this.title = '',
    this.info = '',
    this.hintText = '',
    this.username = '',
    this.displayName = '',
    this.trustDevice = false,
  });

  QrLoginState copyWith({
    QrCodeStatus? status,
    Uint8List? qrImage,
    String? verifyCode,
    String? title,
    String? info,
    String? hintText,
    String? username,
    String? displayName,
    bool? trustDevice,
  }) {
    return QrLoginState(
      status: status ?? this.status,
      qrImage: qrImage ?? this.qrImage,
      verifyCode: verifyCode ?? this.verifyCode,
      title: title ?? this.title,
      info: info ?? this.info,
      hintText: hintText ?? this.hintText,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      trustDevice: trustDevice ?? this.trustDevice,
    );
  }

  bool get isLoading => status == QrCodeStatus.loading;
  bool get isPending => status == QrCodeStatus.pending;
}
