/// 分数估计 · 备忘录图片的导入链路：选图 → 压缩 → 落盘。
///
/// 三段职责分开，便于单测：
/// 1. 选图 = [GeMemoPicker]（[PlatformGeMemoPicker] = 相册 / 拍照 / 文件多选）；
/// 2. 压缩 = [geMemoCompressImage]（纯函数，可跑在 isolate 上）；
/// 3. 编排 = [importGeMemoImages]（体积/数量限额、逐张落盘、失败原因汇总）。
///
/// 选图**不传** `maxWidth/maxHeight/imageQuality` 给 image_picker：
/// 压缩口径只留 [geMemoCompressImage] 一处（否则原生压一次、Dart 再压一次，
/// "压到 1600px" 的约定会分散在两个地方）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../domain/ge_memo.dart';
import 'ge_memo_store.dart';

/// 取图来源。
enum GeMemoPickSource {
  /// 相册（移动端；桌面端没有相册概念，只有文件对话框）。
  gallery,

  /// 拍照（**仅移动端**）。
  camera,

  /// 文件多选（桌面 / 移动都可用）。
  files,
}

/// 本平台可用的取图来源（桌面端只给文件多选）。
List<GeMemoPickSource> geMemoPickSources({required bool mobile}) => mobile
    ? const [
        GeMemoPickSource.gallery,
        GeMemoPickSource.camera,
        GeMemoPickSource.files,
      ]
    : const [GeMemoPickSource.files];

/// 取图项主标题。
String geMemoPickLabel(GeMemoPickSource source, {required bool mobile}) =>
    switch (source) {
      GeMemoPickSource.gallery => '从相册选择',
      GeMemoPickSource.camera => '拍照',
      GeMemoPickSource.files => '选择图片文件',
    };

/// 取图项副标题。
String geMemoPickHint(GeMemoPickSource source, {required bool mobile}) =>
    switch (source) {
      GeMemoPickSource.gallery => '可一次选择多张',
      GeMemoPickSource.camera => '拍完自动加入备忘录',
      GeMemoPickSource.files => mobile ? '从文件管理器中多选' : '可一次多选图片文件',
    };

/// 待导入的一张源图（**只带路径**：导入时先查体积，超限的不会被读进内存）。
@immutable
class GeMemoSourceFile {
  /// 展示用文件名。
  final String name;

  /// 本地绝对路径。
  final String path;

  const GeMemoSourceFile({required this.name, required this.path});
}

/// 选图接口（测试注入假实现，见 `geMemoPickerProvider`）。
abstract interface class GeMemoPicker {
  /// 返回用户选中的文件；取消 → 空列表。
  Future<List<GeMemoSourceFile>> pick(GeMemoPickSource source);
}

/// 真实实现：相册 / 拍照走 image_picker，文件多选走 file_picker。
class PlatformGeMemoPicker implements GeMemoPicker {
  const PlatformGeMemoPicker();

  @override
  Future<List<GeMemoSourceFile>> pick(GeMemoPickSource source) async {
    switch (source) {
      case GeMemoPickSource.camera:
        // 桌面端 image_picker 无相机实现（ImageSource.camera 抛 StateError）。
        if (!geMemoMobilePlatformOn(defaultTargetPlatform.name)) {
          return const [];
        }
        final shot = await ImagePicker().pickImage(source: ImageSource.camera);
        if (shot == null || shot.path.isEmpty) return const [];
        return [GeMemoSourceFile(name: p.basename(shot.path), path: shot.path)];
      case GeMemoPickSource.gallery:
        final picked = await ImagePicker().pickMultiImage();
        return [
          for (final file in picked)
            if (file.path.isNotEmpty)
              GeMemoSourceFile(name: p.basename(file.path), path: file.path),
        ];
      case GeMemoPickSource.files:
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: geMemoImageExtensions.toList(),
        );
        final files = result?.files ?? const <PlatformFile>[];
        return [
          for (final file in files)
            if ((file.path ?? '').isNotEmpty)
              GeMemoSourceFile(name: file.name, path: file.path!),
        ];
    }
  }
}

/// 压缩结果。
@immutable
class GeMemoCompressed {
  final Uint8List bytes;
  final int width;
  final int height;
  final String ext;

  /// 是否真的重编码过（false = 原图已合规，字节原样保留）。
  final bool reencoded;

  const GeMemoCompressed({
    required this.bytes,
    required this.width,
    required this.height,
    required this.ext,
    this.reencoded = true,
  });
}

/// 图片格式 → 扩展名。
String geMemoExtOfFormat(img.ImageFormat? format) =>
    switch (format?.name) {
      'png' => 'png',
      'gif' => 'gif',
      'bmp' => 'bmp',
      'webp' => 'webp',
      _ => 'jpg',
    };

/// 最长边压到 [maxEdge]（等比），并给出最终尺寸与扩展名。
///
/// - 已经在限制内**且**体积不超过 [keepMaxBytes] → 原样返回（不二次编码）；
/// - 重编码：带 alpha 通道（`numChannels == 4`）保 PNG，否则 JPEG q[quality]；
/// - 重编码反而更大且原图尺寸合规 → 回退原图；
/// - 不是图片 / 解不开 → 抛 [FormatException]（调用方记为「无法识别」）。
///
/// GIF/动图只保留首帧（备忘录是静态截图，不做动图播放）。
GeMemoCompressed geMemoCompressImage(
  Uint8List bytes, {
  int maxEdge = geMemoMaxEdge,
  int quality = geMemoJpegQuality,
  int keepMaxBytes = geMemoKeepMaxBytes,
}) {
  // 只读文件头拿尺寸/格式（不做整图解码）。
  var width = 0;
  var height = 0;
  img.ImageFormat? format;
  try {
    format = img.findFormatForData(bytes);
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    width = info?.width ?? 0;
    height = info?.height ?? 0;
  } catch (_) {
    // 头部解析失败 → 走完整解码，由它抛 FormatException
  }

  final longest = width > height ? width : height;
  final withinEdge = width > 0 && height > 0 && longest <= maxEdge;
  if (withinEdge && bytes.length <= keepMaxBytes) {
    return GeMemoCompressed(
      bytes: bytes,
      width: width,
      height: height,
      ext: geMemoExtOfFormat(format),
      reencoded: false,
    );
  }

  // 不是图片 / 头部就坏了 → 统一成 FormatException（调用方记为「无法识别」）。
  // 注意 `decodeImage` 对垃圾字节能抛出各种底层异常（曾见 PSD 解码器
  // 抛 `RangeError (length)`），所以这里必须连异常一起收。
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('无法解码图片');
  }
  if (decoded == null) throw const FormatException('无法解码图片');

  final scaled = longest > maxEdge
      ? (decoded.width >= decoded.height
            ? img.copyResize(
                decoded,
                width: maxEdge,
                interpolation: img.Interpolation.linear,
              )
            : img.copyResize(
                decoded,
                height: maxEdge,
                interpolation: img.Interpolation.linear,
              ))
      : decoded;

  final hasAlpha = scaled.numChannels == 4;
  final encoded = hasAlpha
      ? img.encodePng(scaled)
      : img.encodeJpg(scaled, quality: quality);
  final out = Uint8List.fromList(encoded);

  // 越压越大且原图尺寸本来就合规 → 保留原图（避免"压缩"把图变大）。
  if (withinEdge && out.length >= bytes.length) {
    return GeMemoCompressed(
      bytes: bytes,
      width: width,
      height: height,
      ext: geMemoExtOfFormat(format),
      reencoded: false,
    );
  }

  return GeMemoCompressed(
    bytes: out,
    width: scaled.width,
    height: scaled.height,
    ext: hasAlpha ? 'png' : 'jpg',
  );
}

/// 默认参数版本（喂给 `compute`：`compute` 只能传一个位置参数）。
GeMemoCompressed geMemoCompressDefault(Uint8List bytes) =>
    geMemoCompressImage(bytes);

/// 单张图片被跳过的原因。
enum GeMemoSkipReason {
  /// 超过单张导入上限（[geMemoImportMaxBytes]）。
  tooLarge,

  /// 不是能识别的图片。
  undecodable,

  /// 已达 [geMemoMaxImages] 张上限。
  overLimit,

  /// 读文件 / 落盘失败。
  failed,
}

/// 一张被跳过的图片。
@immutable
class GeMemoImportSkip {
  final String name;
  final GeMemoSkipReason reason;

  const GeMemoImportSkip(this.name, this.reason);
}

/// 跳过原因的中文提示（SnackBar 里逐条显示）。
String geMemoSkipText(GeMemoImportSkip skip) {
  final size = geMemoSizeText(geMemoImportMaxBytes);
  return switch (skip.reason) {
    GeMemoSkipReason.tooLarge => '${skip.name}：超过 $size，已跳过',
    GeMemoSkipReason.undecodable => '${skip.name}：不是可识别的图片，已跳过',
    GeMemoSkipReason.overLimit => '${skip.name}：已达 $geMemoMaxImages 张上限，已跳过',
    GeMemoSkipReason.failed => '${skip.name}：读取或保存失败，已跳过',
  };
}

/// 一次导入的结果。
@immutable
class GeMemoImportResult {
  /// 已落盘、可直接追加进备忘录的图片。
  final List<GeMemoImage> added;

  /// 被跳过的图片（含原因）。
  final List<GeMemoImportSkip> skipped;

  const GeMemoImportResult({this.added = const [], this.skipped = const []});

  bool get isEmpty => added.isEmpty && skipped.isEmpty;

  int get addedCount => added.length;

  /// 一句话结果（SnackBar 用）。
  String get summary {
    final parts = <String>[
      if (added.isNotEmpty) '已添加 ${added.length} 张',
      if (skipped.isNotEmpty) '跳过 ${skipped.length} 张',
    ];
    return parts.isEmpty ? '没有可导入的图片' : parts.join(' · ');
  }
}

/// 选中的文件 → 压缩 → 落盘，返回可追加的 [GeMemoImage] 列表。
///
/// [remainingSlots] = 这门课还能放几张（超出部分记 `overLimit`）。
/// [compress] 只在测试里注入（默认跑在 isolate 上，避免大图解码卡界面）。
Future<GeMemoImportResult> importGeMemoImages({
  required GeMemoStore store,
  required String account,
  required String courseId,
  required List<GeMemoSourceFile> sources,
  required int remainingSlots,
  int maxBytes = geMemoImportMaxBytes,
  GeMemoCompressed Function(Uint8List bytes)? compress,
}) async {
  final added = <GeMemoImage>[];
  final skipped = <GeMemoImportSkip>[];
  final slots = remainingSlots.clamp(0, geMemoMaxImages);

  for (final source in sources) {
    if (added.length >= slots) {
      skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.overLimit));
      continue;
    }
    try {
      final file = File(source.path);
      if (!await file.exists()) {
        skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.failed));
        continue;
      }
      // 先看体积再读内容：几十 MB 的文件不会被整个读进内存。
      final size = await file.length();
      if (size <= 0) {
        skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.failed));
        continue;
      }
      if (size > maxBytes) {
        skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.tooLarge));
        continue;
      }

      final raw = await file.readAsBytes();
      final compressed = compress != null
          ? compress(raw)
          : await compute(geMemoCompressDefault, raw);

      final fileName = await store.save(
        account: account,
        courseId: courseId,
        bytes: compressed.bytes,
        ext: compressed.ext,
      );
      added.add(
        GeMemoImage(
          fileName: fileName,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          bytes: compressed.bytes.length,
          width: compressed.width,
          height: compressed.height,
        ),
      );
    } on FormatException {
      skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.undecodable));
    } catch (error) {
      debugPrint('[score_estimate] 备忘录导入失败（${source.name}）：$error');
      skipped.add(GeMemoImportSkip(source.name, GeMemoSkipReason.failed));
    }
  }

  return GeMemoImportResult(added: added, skipped: skipped);
}
