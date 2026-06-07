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

  /// 扫码登录
  Future<void> scanLogin(BuildContext context) async {
    // 先初始化状态再显示对话框（确保首次渲染拿到 loading）
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '扫描二维码登录',
      hintText: '使用微信或者企业微信扫一扫登录',
    );

    // 显示对话框（不 await，fire-and-forget）
    // 对话框关闭时自动停止轮询
    _showDialog(context).then((_) => stopPolling());

    try {
      await _repository.startScanLogin();
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
    }
  }

  /// 微信登录
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

  /// MFA 验证
  Future<void> mfaVerify(
    BuildContext context,
    String account,
    String password,
  ) async {
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      hintText: '使用微信或者企业微信扫一扫完成验证',
    );

    try {
      final needMfa = await _repository.startMfaVerification(account, password);
      if (!needMfa) return;
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
      return;
    }

    // 等待二维码对话框关闭后再返回
    await _showDialog(context);
    stopPolling();
  }

  /// 从 repository 同步数据到 state
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

  /// 刷新二维码
  Future<void> refresh() async {
    try {
      await _repository.refresh();
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
    }
  }

  /// 显示二维码对话框，返回 Future 在对话框关闭时完成
  Future<void> _showDialog(BuildContext context) {
    return QrCodeDialog.show(context, title: state.title, info: state.info);
  }

  /// 停止轮询
  void stopPolling() {
    _repository.stopPolling();
  }
}
