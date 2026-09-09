import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'ca_installer.dart';
import 'guid_capture_proxy.dart';
import 'system_proxy.dart';

/// 捕获会话阶段。
enum GuidCaptureStage {
  /// 空闲。
  idle,

  /// 准备中（加载证书 / 安装 CA / 启动代理）。
  preparing,

  /// 等待用户去微信操作（代理已就绪）。
  waiting,

  /// 捕获成功。
  success,

  /// 失败 / 超时 / 用户取消。
  stopped,
}

/// App 内一键捕获 GUID 的会话编排。
///
/// 流程：加载内置 MITM 证书 → 首次安装 CA 到系统 Root → 启动纯 Dart 代理 →
/// 开启系统代理 → 引导用户在微信打开智慧江财 → 捕获 platformUsername →
/// 自动收尾（停代理、还原系统代理）。
class GuidCaptureSession extends ChangeNotifier {
  GuidCaptureSession({void Function(String)? onLog}) : _onLog = onLog;

  final void Function(String)? _onLog;

  GuidCaptureStage _stage = GuidCaptureStage.idle;
  String? _capturedGuid;
  String? _error;
  String? _detail;
  GuidCaptureProxy? _proxy;
  ({bool enabled, String server})? _prevProxy;
  Timer? _timeout;
  Completer<void> _settled = Completer<void>();

  GuidCaptureStage get stage => _stage;
  String? get capturedGuid => _capturedGuid;
  String? get error => _error;

  /// 状态副文本（给 UI 显示）。
  String? get detail => _detail;

  bool get busy =>
      _stage == GuidCaptureStage.preparing ||
      _stage == GuidCaptureStage.waiting;

  void _log(String s) {
    _detail = s;
    _onLog?.call(s);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 主流程
  // ------------------------------------------------------------------

  /// 开始一键捕获。返回后 UI 通过 [stage] 跟踪进度。
  Future<void> startCapture() async {
    if (busy) return;
    _capturedGuid = null;
    _error = null;
    _settled = Completer<void>();
    _stage = GuidCaptureStage.preparing;
    _log('正在准备证书与代理…');
    notifyListeners();

    try {
      final context = await _buildServerContext();

      // 1) 首次安装 CA 到系统 Root。
      if (!await CaInstaller.isInstalled()) {
        _log('首次使用，正在把本地证书加入系统信任…');
        final dir = await getTemporaryDirectory();
        final caFile = '${dir.path}${Platform.pathSeparator}smarter_jxufe_ca.cer';
        final caAsset = await rootBundle.load('assets/capture_certs/ca.cer');
        await File(caFile).writeAsBytes(caAsset.buffer.asUint8List());
        final installed = await CaInstaller.install(caFile);
        if (!installed) {
          throw StateError('证书安装失败，请检查系统是否允许（首次需要确认一次）');
        }
        _log('证书已加入系统信任。');
      } else {
        _log('本地证书已在系统信任中。');
      }

      // 2) 启动本地 MITM 代理。
      final proxy = GuidCaptureProxy(tlsContext: context, listenPort: 8899);
      proxy.onGuid = _onGuid;
      await proxy.start();
      _proxy = proxy;

      // 3) 开启系统代理（记录原状，收尾还原）。
      final prev = await SystemProxy.read();
      _prevProxy = prev;
      final ok = await SystemProxy.enable('127.0.0.1', 8899);
      if (!ok) {
        throw StateError('无法开启系统代理');
      }
      _log('代理已就绪：系统流量已指向本机 8899。');

      // 4) 等待捕获（90s 超时）。
      _stage = GuidCaptureStage.waiting;
      _timeout = Timer(const Duration(seconds: 90), () {
        _finish(
          success: false,
          error: '等待超时：未在微信中检测到平台标识。请确认已打开智慧江财并进入需要登录的功能页。',
        );
      });
      notifyListeners();
      await _settled.future;
    } catch (e) {
      _finish(success: false, error: '$e');
    }
  }

  /// 捕获成功回调（来自代理扫描）。
  void _onGuid(String guid) {
    if (_settled.isCompleted) return;
    _log('捕获到平台标识！');
    _capturedGuid = guid;
    _finish(success: true);
  }

  void _finish({required bool success, String? error}) {
    if (_settled.isCompleted) return;
    _timeout?.cancel();
    _error = error;
    if (!success) {
      _stage = GuidCaptureStage.stopped;
      _detail = error;
    } else {
      _stage = GuidCaptureStage.success;
    }
    unawaited(_teardown());
    if (!_settled.isCompleted) _settled.complete();
    notifyListeners();
  }

  /// 用户主动取消并还原环境。
  Future<void> cancel() async {
    if (_settled.isCompleted && !busy) return;
    _timeout?.cancel();
    if (!_settled.isCompleted) _settled.complete();
    _stage = GuidCaptureStage.stopped;
    _detail = '已取消';
    await _teardown();
    notifyListeners();
  }

  Future<void> _teardown() async {
    final proxy = _proxy;
    _proxy = null;
    try {
      await proxy?.stop();
    } catch (_) {}
    final prev = _prevProxy;
    _prevProxy = null;
    if (prev != null) {
      await SystemProxy.restore(enabled: prev.enabled, server: prev.server);
    }
  }

  void reset() {
    _stage = GuidCaptureStage.idle;
    _capturedGuid = null;
    _error = null;
    _detail = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // 证书加载
  // ------------------------------------------------------------------

  Future<SecurityContext> _buildServerContext() async {
    final cert = await rootBundle.load('assets/capture_certs/leaf.crt');
    final ca = await rootBundle.load('assets/capture_certs/ca.crt');
    final key = await rootBundle.load('assets/capture_certs/leaf.key');
    final ctx = SecurityContext();
    ctx.useCertificateChainBytes(
      Uint8List.fromList([...cert.buffer.asUint8List(), ...ca.buffer.asUint8List()]),
    );
    ctx.usePrivateKeyBytes(key.buffer.asUint8List());
    return ctx;
  }

  // ------------------------------------------------------------------
  // 微信进程辅助
  // ------------------------------------------------------------------

  /// 微信主程序（或小程序容器）是否在运行。
  static Future<bool> wechatRunning() async {
    final r = await Process.run('tasklist', ['/FI', 'IMAGENAME eq Weixin.exe']);
    return (r.stdout as String).contains('Weixin.exe');
  }

  /// 关闭微信（含小程序容器进程）。代理变更需要微信重启才生效。
  static Future<void> stopWechat() async {
    for (final name in ['Weixin.exe', 'WeChatAppEx.exe']) {
      await Process.run('taskkill', ['/IM', name, '/F']);
    }
  }

  /// 重新打开微信（读注册表安装路径；失败返回 false）。
  static Future<bool> startWechat() async {
    String? path;
    final reg = await Process.run(
      'reg',
      ['query', r'HKCU\Software\Tencent\Weixin', '/v', 'InstallPath'],
    );
    if (reg.exitCode == 0) {
      final line = (reg.stdout as String)
          .split('\n')
          .firstWhere((l) => l.contains('InstallPath'), orElse: () => '');
      final idx = line.lastIndexOf('REG_SZ');
      if (idx >= 0) {
        final p = line.substring(idx + 6).trim();
        if (p.isNotEmpty && File(p + r'\Weixin.exe').existsSync()) {
          path = p + r'\Weixin.exe';
        }
      }
    }
    path ??= r'D:\Program\Weixin\Weixin.exe';
    if (!File(path).existsSync()) return false;
    try {
      await Process.start(path, const []);
      return true;
    } catch (_) {
      return false;
    }
  }
}
