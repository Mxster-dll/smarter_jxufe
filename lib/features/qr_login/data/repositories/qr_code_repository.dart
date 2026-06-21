import 'dart:async';

import 'package:rxdart/rxdart.dart';

import 'package:smarter_jxufe/features/qr_login/data/datasources/mfa_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/scan_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/wechat_login_remote_datasource.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_data.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

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

  final _statusSubject = BehaviorSubject<QrCodeStatus>.seeded(
    QrCodeStatus.loading,
  );

  Stream<QrCodeStatus> get statusStream => _statusSubject.stream;
  QrCodeStatus get currentStatus => _statusSubject.value;

  QrCodeData? _qrCodeData;
  QrCodeData? get qrCodeData => _qrCodeData;

  bool get isLoading => currentStatus == QrCodeStatus.loading;
  bool get isPending => currentStatus == QrCodeStatus.pending;

  Timer? _pollingTimer;
  late int _pollingInterval;

  _LoginType? _activeLoginType;

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
    }
  }

  void stopPolling() => _stopPolling();

  void dispose() {
    _stopPolling();
    _statusSubject.close();
  }
}

enum _LoginType { scan, wechat, mfa }
