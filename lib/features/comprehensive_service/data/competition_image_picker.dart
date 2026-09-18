import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';

/// 证书图片来源：相册 / 拍照 / 文件。
enum CompetitionImageSource { gallery, camera, files }

/// 证书图片选择器（可注入，测试用假实现）。
///
/// 官网只接受 `jpg / jpeg / png`、单张 ≤ 3MB、一次最多 10 张（前端校验），
/// 这里只负责取字节，大小 / 张数由表单校验。
abstract class CompetitionImagePicker {
  /// 选图；用户取消 / 平台不支持 → 返回空列表。
  Future<List<CompetitionAttachment>> pick(CompetitionImageSource source);

  /// 桌面端不出「拍照」（Windows 无相机插件）。
  bool get supportsCamera;
}

/// 真实实现：相册 / 拍照走 image_picker，多选文件走 file_picker。
class PlatformCompetitionImagePicker implements CompetitionImagePicker {
  const PlatformCompetitionImagePicker();

  @override
  bool get supportsCamera =>
      competitionImageMobilePlatformOn(defaultTargetPlatform.name);

  @override
  Future<List<CompetitionAttachment>> pick(
    CompetitionImageSource source,
  ) async {
    switch (source) {
      case CompetitionImageSource.camera:
        if (!supportsCamera) return const [];
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2400,
          imageQuality: 92,
        );
        return shot == null ? const [] : [await _fromXFile(shot)];
      case CompetitionImageSource.gallery:
        final picked = await ImagePicker().pickMultiImage(
          maxWidth: 2400,
          imageQuality: 92,
        );
        final out = <CompetitionAttachment>[];
        for (final file in picked) {
          out.add(await _fromXFile(file));
        }
        return out;
      case CompetitionImageSource.files:
        // file_picker v11 没有 `.platform`，这里是静态调用（同材料库写法）。
        final result = await FilePicker.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png'],
        );
        if (result == null) return const [];
        final out = <CompetitionAttachment>[];
        for (final file in result.files) {
          final bytes = file.bytes;
          if (bytes == null) continue;
          out.add(
            CompetitionAttachment(
              fileName: file.name,
              bytes: bytes,
              mimeType: competitionImageMimeOf(file.name),
            ),
          );
        }
        return out;
    }
  }

  Future<CompetitionAttachment> _fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    return CompetitionAttachment(
      fileName: file.name,
      bytes: bytes,
      mimeType: file.mimeType ?? competitionImageMimeOf(file.name),
    );
  }
}

/// 移动端判定（桌面端不出「拍照」）。
bool competitionImageMobilePlatformOn(String platform) =>
    platform == 'android' || platform == 'ios';

/// 由文件名推断 MIME（官网只认图片扩展名）。
String competitionImageMimeOf(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

/// 证书图片选择器提供者。
final competitionImagePickerProvider = Provider<CompetitionImagePicker>(
  (ref) => const PlatformCompetitionImagePicker(),
);
