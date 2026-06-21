import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/qr_login/data/providers/qr_code_repository_provider.dart';
import 'package:smarter_jxufe/features/qr_login/data/repositories/qr_code_repository.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_state.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_dialog.dart';

part 'qr_login_viewmodel.g.dart';

@Riverpod(keepAlive: true)
class QrLoginViewModel extends _$QrLoginViewModel {
  late final QrCodeRepository _repository;
  StreamSubscription<QrCodeStatus>? _statusSubscription;

  @override
  QrLoginState build() {
    _repository = ref.watch(qrCodeRepositoryProvider);
    ref.onDispose(_cleanup);
    return const QrLoginState();
  }

  void _cleanup() {
    _statusSubscription?.cancel();
  }

  void _listenToRepository() {
    _statusSubscription?.cancel();
    _statusSubscription = _repository.statusStream.listen((status) {
      state = state.copyWith(status: status);
    });
  }

  Future<void> scanLogin(BuildContext context) async {
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '扫描二维码登录',
      hintText: '使用微信或者企业微信扫一扫登录',
    );

    _showDialog(context).then((_) => stopPolling());

    try {
      await _repository.startScanLogin();
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
    }
  }

  Future<void> wechatLogin(BuildContext context) async {
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '微信登录',
      hintText: '使用微信扫一扫登录',
    );

    _showDialog(context).then((_) => stopPolling());

    try {
      await _repository.startWechatLogin();
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
    }
  }

  Future<({bool authorized, bool trustDevice})> mfaVerify(
    BuildContext context,
    String account,
    String password,
  ) async {
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      hintText: '使用微信或者企业微信扫一扫完成验证',
      username: account,
    );

    try {
      final needMfa = await _repository.startMfaVerification(account, password);
      if (!needMfa) return (authorized: false, trustDevice: false);
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
      return (authorized: false, trustDevice: false);
    }

    bool authorized = false;
    late final StreamSubscription<QrCodeStatus> mfaSub;
    mfaSub = _repository.statusStream.listen((status) {
      if (status == QrCodeStatus.authorized && context.mounted) {
        authorized = true;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    });

    await _showDialog(context);
    mfaSub.cancel();
    stopPolling();

    return (authorized: authorized, trustDevice: state.trustDevice);
  }

  void _syncFromRepository() {
    final data = _repository.qrCodeData;
    if (data != null) {
      state = state.copyWith(
        qrImage: data.img,
        verifyCode: data.verifyCode,
        status: _repository.currentStatus,
      );
    }
    _listenToRepository();
  }

  Future<void> refresh() async {
    try {
      await _repository.refresh();
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
    }
  }

  Future<void> _showDialog(BuildContext context) {
    return QrCodeDialog.show(
      context,
      title: state.title,
      info: state.info,
      onTrustChanged: (v) {
        state = state.copyWith(trustDevice: v);
      },
    );
  }

  void stopPolling() {
    _repository.stopPolling();
  }
}
