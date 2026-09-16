import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 一次「导出文件」的结果。
class FileShareResult {
  /// Android：是否已成功调起系统分享面板。
  final bool shared;

  /// 桌面端回退落盘的绝对路径（无系统分享面板时使用）。
  final String? savedPath;

  /// 失败原因；成功时为 null。
  final String? error;

  const FileShareResult({this.shared = false, this.savedPath, this.error});

  bool get ok => shared || savedPath != null;

  const FileShareResult.failure(String message) : this(error: message);

  @override
  String toString() =>
      'FileShareResult(shared: $shared, savedPath: $savedPath, error: $error)';
}

/// 把内存里的字节交给系统去「分享」或「落盘」。
///
/// - **Android**：走自研原生桥 [channel]（`smarter_jxufe/file_share`）——
///   写入应用缓存目录 → `FileProvider` 生成 `content://` → 调起
///   `ACTION_SEND` 系统分享面板（微信 / QQ / 邮件…）。**零第三方依赖**。
/// - **桌面（Windows 等）**：没有系统分享面板，退回「写入系统下载目录」，
///   由调用方提示路径（可用 [openFile] 打开）。
class FileShare {
  FileShare._();

  /// 原生桥通道名（与 `FileShareBridge.kt` 的 `CHANNEL` 必须一致）。
  static const MethodChannel channel = MethodChannel(
    'smarter_jxufe/file_share',
  );

  static const Duration _timeout = Duration(seconds: 20);

  /// 当前平台是否有原生分享能力。
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 分享（Android）或保存（桌面）一段字节。
  ///
  /// [fileName] 会原样作为文件名（调用方应已清洗过）；
  /// [mimeType] 决定分享面板给出的候选应用。
  static Future<FileShareResult> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
    String? subject,
    String? text,
  }) async {
    if (bytes.isEmpty) return const FileShareResult.failure('文件内容为空');

    if (isSupported) {
      try {
        final result = await channel
            .invokeMapMethod<String, Object?>('shareBytes', <String, Object?>{
              'bytes': bytes,
              'fileName': fileName,
              'mimeType': mimeType,
              'subject': subject,
              'text': text,
            })
            .timeout(_timeout);
        if (result == null) {
          return const FileShareResult.failure('分享失败：原生侧无响应');
        }
        if (result['shared'] == true) {
          return FileShareResult(
            shared: true,
            savedPath: result['path'] as String?,
          );
        }
        return FileShareResult.failure(
          (result['message'] as String?) ?? '分享失败',
        );
      } catch (error) {
        debugPrint('[file_share] 调起分享失败: $error');
        return FileShareResult.failure('调起系统分享失败：$error');
      }
    }

    // 桌面回退：写入下载目录
    try {
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      // 下载目录可能被重定向到尚未创建的路径（本机实测：Downloads → D:\Tmp）
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return FileShareResult(savedPath: file.path);
    } catch (error) {
      debugPrint('[file_share] 写入文件失败: $error');
      return FileShareResult.failure('保存文件失败：$error');
    }
  }

  /// 用系统默认程序打开本地文件（桌面端提示用，失败返回 false）。
  static Future<bool> openFile(String path) async {
    try {
      return await launchUrl(Uri.file(path));
    } catch (error) {
      debugPrint('[file_share] 打开文件失败: $error');
      return false;
    }
  }
}
