import 'dart:async';
import 'dart:typed_data';
import 'package:rxdart/rxdart.dart';

import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';
import 'package:smarter_jxufe/Services/MfaService.dart';
import 'package:smarter_jxufe/Services/ScanLoginService.dart';

abstract class QrCode {
  late String id;
  String? verifyCode;
  late Uint8List img;

  final BehaviorSubject<QrCodeStatus> stateSubject =
      BehaviorSubject<QrCodeStatus>.seeded(QrCodeStatus.loading);
  Stream<QrCodeStatus> get stateStream => stateSubject.stream;

  set status(QrCodeStatus? status) {
    if (!stateSubject.isClosed && status != null) {
      stateSubject.add(status);
    }
  }

  QrCodeStatus get status => stateSubject.value;

  Future<void> refresh();

  // 轮询相关
  Timer? _pollingTimer;
  final int pollingInterval = 1500;

  Future<void> _pollStatus(); // TODO 轮询异常的判断和提示

  Future<void> startPolling() async {
    _pollingTimer = Timer.periodic(
      Duration(milliseconds: pollingInterval),
      (_) => _pollStatus(),
    );
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void dispose() {
    stopPolling();
    stateSubject.close();
  }
}

class MfaQrCode extends QrCode {
  final MfaService _loginService;

  MfaQrCode(this._loginService);

  @override
  Future<void> refresh() async => await _loginService.refreshQrCode();

  @override
  Future<void> _pollStatus() async {
    status = await _loginService.pollStatus();

    if (status.isFinal) stopPolling();
  }
}

class LoginQrCode extends QrCode {
  final ScanLoginService _loginService;
  LoginQrCode(this._loginService);

  @override
  Future<void> refresh() => _loginService.refreshQrCode();

  @override
  Future<void> _pollStatus() async {
    status = await _loginService.pollStatus();

    if (status.isFinal) stopPolling();
  }
}
