library;

import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/log.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/login/MfaService.dart';

part 'QrCodeCard.dart';
part 'QrCodeStatus.dart';
part 'ScanLogin.dart';
part 'WeChatLogin.dart';
part 'WeComLogin.dart';

abstract interface class QrCodeNetworkService {
  Future<void> process(BuildContext context);
  Future<void> refreshQrCode();
  Future<QrCodeStatus?> pollStatus();
}

final class QrCode {
  final QrCodeNetworkService networkService;

  late String id;
  String? verifyCode;
  late String imgUrl;
  late Uint8List img;

  QrCode(this.networkService, [this.pollingInterval = 1500]);

  final stateSubject = BehaviorSubject<QrCodeStatus>.seeded(.loading);
  Stream<QrCodeStatus> get stateStream => stateSubject.stream;

  set status(QrCodeStatus? status) {
    if (!stateSubject.isClosed && status != null) {
      stateSubject.add(status);
    }
  }

  bool get isLoading => status == .loading;
  bool get isPending => status == .pending;

  QrCodeStatus get status => stateSubject.value;

  Future<void> refresh() async => await networkService.refreshQrCode();

  Timer? _pollingTimer; // BUG 存在Timer在程序结束后未关闭
  final int pollingInterval;

  Future<void> _pollStatus() async {
    status = await networkService.pollStatus();

    if (status.isFinal) stopPolling();
  }

  void startPolling() {
    _pollingTimer = .periodic(
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
