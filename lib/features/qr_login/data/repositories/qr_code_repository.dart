import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'package:smarter_jxufe/features/qr_login/data/datasources/mfa_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/scan_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/wechat_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_data.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

/// QR码仓库——管理二维码生命周期（轮询、状态流、缓存定时器）
///
/// 参照项目现有仓库模式，无抽象接口，直接提供具体实现。
class QrCodeRepository {
  final ScanLoginRemoteDataSource _scanLoginDs;
  final WechatLoginRemoteDataSource _wechatLoginDs;
  final MfaLoginRemoteDataSource _mfaLoginDs;

  QrCodeRepository({
    required ScanLoginRemoteDataSource scanLoginDs,
    required WechatLoginRemoteDataSource wechatLoginDs,
    required MfaLoginRemoteDataSource mfaLoginDs,
  }) : _scanLoginDs = scanLoginDs,
       _wechatLoginDs = wechatLoginDs,
       _mfaLoginDs = mfaLoginDs;

  // ── 状态管理 ──
  final _statusSubject = BehaviorSubject<QrCodeStatus>.seeded(
    QrCodeStatus.loading,
  );

  Stream<QrCodeStatus> get statusStream => _statusSubject.stream;
  QrCodeStatus get currentStatus => _statusSubject.value;

  QrCodeData? _qrCodeData;
  QrCodeData? get qrCodeData => _qrCodeData;

  bool get isLoading => currentStatus == QrCodeStatus.loading;
  bool get isPending => currentStatus == QrCodeStatus.pending;

  // ── 轮询管理 ──
  Timer? _pollingTimer;
  late int _pollingInterval;

  /// 当前活跃的登录类型，用于 refresh 和 poll 时选择正确的分支
  _LoginType? _activeLoginType;

  /// 各登录类型所需的轮询上下文
  String? _scanCookie;
  String? _wechatUuid;
  String? _mfaAttestServer;
  String? _mfaGid;
  String? _mfaAccount;
  String? _mfaPassword;

  void _setStatus(QrCodeStatus status) {
    if (!_statusSubject.isClosed) {
      _statusSubject.add(status);
    }
  }

  // ═══ 扫码登录 ═══

  /// 发起扫码登录流程
  Future<void> startScanLogin({int pollingInterval = 1500}) async {
    _activeLoginType = _LoginType.scan;
    _pollingInterval = pollingInterval;

    final id = _scanLoginDs.generateQrCodeId();
    final imgUrl = _scanLoginDs.getQrCodeUrl(id);
    _setStatus(QrCodeStatus.loading);

    final (img, cookie) = await _scanLoginDs.downloadQrCode(id);
    _scanCookie = cookie;
    _qrCodeData = QrCodeData(id: id, imgUrl: imgUrl, img: img);
    _setStatus(QrCodeStatus.pending);
    _startPolling();
  }

  /// 刷新扫码登录二维码
  Future<void> refreshScanLogin() async {
    _stopPolling();
    _setStatus(QrCodeStatus.loading);

    final id = _scanLoginDs.generateQrCodeId();
    final imgUrl = _scanLoginDs.getQrCodeUrl(id);

    final (img, cookie) = await _scanLoginDs.downloadQrCode(id);
    _scanCookie = cookie;
    _qrCodeData = QrCodeData(id: id, imgUrl: imgUrl, img: img);
    _setStatus(QrCodeStatus.pending);
    _startPolling();
  }

  // ═══ 微信登录 ═══

  /// 发起微信登录流程
  Future<void> startWechatLogin() async {
    _activeLoginType = _LoginType.wechat;
    _pollingInterval = 17000; // 微信长轮询，间隔较长

    _setStatus(QrCodeStatus.loading);

    final uuid = await _wechatLoginDs.initAndGetUuid();
    _wechatUuid = uuid;

    final img = await _wechatLoginDs.downloadQrCode(uuid);
    _qrCodeData = QrCodeData(
      id: uuid,
      imgUrl: 'https://open.weixin.qq.com/connect/qrcode/$uuid',
      img: img,
    );
    _setStatus(QrCodeStatus.pending);
    _startPolling();
  }

  // ═══ MFA 验证 ═══

  /// 发起 MFA 验证流程
  /// 返回 true 表示需要 MFA（已弹出二维码），false 表示无需 MFA
  Future<bool> startMfaVerification(
    String account,
    String password, {
    int pollingInterval = 1500,
  }) async {
    _activeLoginType = _LoginType.mfa;
    _pollingInterval = pollingInterval;
    _mfaAccount = account;
    _mfaPassword = password;

    _setStatus(QrCodeStatus.loading);

    final (need, mfaState) = await _mfaLoginDs.detectMfa(account, password);
    if (!need) return false;


    final (attestServer, gid) = await _mfaLoginDs.initQrCode(mfaState);
    _mfaAttestServer = attestServer;
    _mfaGid = gid;

    final (verifyCode, imgUrl) = await _mfaLoginDs.fetchQrCode(
      attestServer,
      gid,
    );

    final img = await _mfaLoginDs.downloadQrCode(imgUrl);
    _qrCodeData = QrCodeData(
      id: gid,
      verifyCode: verifyCode,
      imgUrl: imgUrl,
      img: img,
    );
    _setStatus(QrCodeStatus.pending);
    _startPolling();

    return true;
  }

  /// 刷新 MFA 二维码
  Future<void> refreshMfa() async {
    _stopPolling();
    _setStatus(QrCodeStatus.loading);

    if (_mfaAccount == null || _mfaPassword == null) {
      throw Exception('MFA 刷新失败：缺少账号密码');
    }

    final (need, mfaState) = await _mfaLoginDs.detectMfa(
      _mfaAccount!,
      _mfaPassword!,
    );
    if (!need) {
      _setStatus(QrCodeStatus.error);
      return;
    }

    final (attestServer, gid) = await _mfaLoginDs.initQrCode(mfaState);
    _mfaAttestServer = attestServer;
    _mfaGid = gid;

    final (verifyCode, imgUrl) = await _mfaLoginDs.fetchQrCode(
      attestServer,
      gid,
    );

    final img = await _mfaLoginDs.downloadQrCode(imgUrl);
    _qrCodeData = QrCodeData(
      id: gid,
      verifyCode: verifyCode,
      imgUrl: imgUrl,
      img: img,
    );
    _setStatus(QrCodeStatus.pending);
    _startPolling();
  }

  // ═══ 通用方法 ═══

  /// 刷新当前活跃的二维码
  Future<void> refresh() async {
    switch (_activeLoginType) {
      case _LoginType.scan:
        await refreshScanLogin();
      case _LoginType.wechat:
        await _wechatLoginDs.refreshQrCode(); // 目前抛出 UnimplementedError
      case _LoginType.mfa:
        await refreshMfa();
      case null:
        throw Exception('没有活跃的登录流程');
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      Duration(milliseconds: _pollingInterval),
      (_) => _pollStatus(),
    );
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _pollStatus() async {
    try {
      final QrCodeStatus? status = switch (_activeLoginType) {
        _LoginType.scan => await _scanLoginDs.pollStatus(_scanCookie!),
        _LoginType.wechat => await _wechatLoginDs.pollStatus(_wechatUuid!),
        _LoginType.mfa => await _mfaLoginDs.pollStatus(
            _mfaAttestServer!,
            _mfaGid!,
          ),
        null => null,
      };

      if (status != null) {
        _setStatus(status);
        if (status.isFinal) {
          _stopPolling();
        }
      }
    } catch (_) {
      // 轮询异常静默处理，等待下一次轮询
    }
  }

  /// 停止轮询（对话框关闭时调用）
  void stopPolling() => _stopPolling();

  /// 释放资源
  void dispose() {
    _stopPolling();
    _statusSubject.close();
  }
}

enum _LoginType { scan, wechat, mfa }
