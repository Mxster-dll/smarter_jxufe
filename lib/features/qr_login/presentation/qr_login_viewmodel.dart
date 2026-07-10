import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/qr_login/data/providers/qr_code_repository_provider.dart';
import 'package:smarter_jxufe/features/qr_login/data/repositories/qr_code_repository.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_state.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_dialog.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/mobile_mfa_dialog.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/unified_mfa_dialog.dart';

part 'qr_login_viewmodel.g.dart';

@Riverpod(keepAlive: true)
class QrLoginViewModel extends _$QrLoginViewModel {
  // 用 late（非 final）替代 late final，允许 build() 重复调用时重新赋值
  late QrCodeRepository _repository;
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

  /// MFA 验证，返回 true 表示验证成功（authorized），false 表示用户手动关闭
  /// 返回 (是否授权成功, 是否信任设备)
  Future<({bool authorized, bool trustDevice})> mfaVerify(
    BuildContext context,
    String account,
    String password,
    String mfaState,
  ) async {
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      hintText: '使用微信或者企业微信扫一扫完成验证',
      username: account,
    );

    try {
      await _repository.startMfaVerification(account, password, mfaState);
      _syncFromRepository();
    } catch (e) {
      state = state.copyWith(status: QrCodeStatus.error);
      return (authorized: false, trustDevice: false);
    }

    // 监听验证成功状态
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

    // 等待二维码对话框关闭
    await _showDialog(context);
    mfaSub.cancel();
    stopPolling();

    return (authorized: authorized, trustDevice: state.trustDevice);
  }

  /// 手机验证码 MFA 验证。
  /// 返回 (是否授权成功, 是否信任设备)
  Future<({bool authorized, bool trustDevice})> mobileMfaVerify(
    BuildContext context,
    String account,
    String password,
    String mfaState,
  ) async {
    // 初始化
    final (attestServer, gid, phoneNumber) = await _repository.initMobileMfa(
      mfaState,
    );

    // 显示对话框，回调处理发送/验证
    final result = await MobileMfaDialog.show(
      context,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      phoneNumber: phoneNumber,
      onSendCode: () => _repository.sendMobileMfaCode(attestServer, gid),
      onValidate: (code) =>
          _repository.validateMobileMfaCode(attestServer, gid, code),
    );

    return result;
  }

  /// 统一 MFA 验证（扫码 + 短信，用户可自行切换）。
  /// 返回 (是否授权成功, 是否信任设备)
  Future<({bool authorized, bool trustDevice})> unifiedMfaVerify(
    BuildContext context,
    String account,
    String password,
    String mfaState, {
    bool startInQrMode = true,
    bool showSwitchAccount = true,
    String displayName = '',
  }) async {
    // ── 先初始化扫码模式 ──
    state = state.copyWith(
      status: QrCodeStatus.loading,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      username: account,
      displayName: displayName,
    );

    await _repository.startMfaVerification(account, password, mfaState);
    _syncFromRepository();

    // 短信模式的 state（延迟初始化，切换时才请求）
    String? smsAttestServer;
    String? smsGid;

    // 显示统一对话框（对话框内部处理扫码状态监听和 auto-close）
    final result = await UnifiedMfaDialog.show(
      context,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
      startInQrMode: startInQrMode,
      showSwitchAccount: showSwitchAccount,
      qrStatusStream: _repository.statusStream,
      onSwitchToQr: () async {
        // 重新初始化扫码
        await _repository.startMfaVerification(account, password, mfaState);
        _syncFromRepository();
      },
      onSwitchToSms: () async {
        // 初始化短信模式
        final (server, gid, phone) = await _repository.initMobileMfa(mfaState);
        smsAttestServer = server;
        smsGid = gid;
        return '安全手机：$phone';
      },
      onSendCode: () async {
        if (smsAttestServer == null || smsGid == null) {
          throw Exception('请先切换至短信验证模式');
        }
        await _repository.sendMobileMfaCode(smsAttestServer!, smsGid!);
      },
      onValidate: (code) {
        if (smsAttestServer == null || smsGid == null) {
          throw Exception('请先切换至短信验证模式');
        }
        return _repository.validateMobileMfaCode(
          smsAttestServer!,
          smsGid!,
          code,
        );
      },
    ).catchError((_) => (authorized: false, trustDevice: false));

    stopPolling();
    return result;
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

  /// Update trustDevice flag from UI
  void setTrustDevice(bool v) {
    state = state.copyWith(trustDevice: v);
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
