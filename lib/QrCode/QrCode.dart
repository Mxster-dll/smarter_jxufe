import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';

abstract class QrCodeNetworkService {
  Future<void> process(BuildContext context);
  Future<void> refreshQrCode();
  Future<QrCodeStatus?> pollStatus();
}

class QrCode {
  final QrCodeNetworkService networkService;

  late String id;
  String? verifyCode;
  late String imgUrl;
  late Uint8List img;

  QrCode(this.networkService, [this.pollingInterval = 1500]);

  final BehaviorSubject<QrCodeStatus> stateSubject =
      BehaviorSubject<QrCodeStatus>.seeded(QrCodeStatus.loading);
  Stream<QrCodeStatus> get stateStream => stateSubject.stream;

  set status(QrCodeStatus? status) {
    if (!stateSubject.isClosed && status != null) {
      stateSubject.add(status);
    }
  }

  bool get isLoading => status == QrCodeStatus.loading;
  bool get isPending => status == QrCodeStatus.pending;

  QrCodeStatus get status => stateSubject.value;

  Future<void> refresh() async => await networkService.refreshQrCode();

  // 轮询相关
  Timer? _pollingTimer; // BUG 存在Timer在程序结束后未关闭
  final int pollingInterval;

  // TODO 轮询异常的判断和提示
  Future<void> _pollStatus() async {
    status = await networkService.pollStatus();

    if (status.isFinal) stopPolling();
  }

  void startPolling() {
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
