/// 分数估计 · 备忘录图片的本地文件存储。
///
/// 目录结构：`<应用私有目录>/ge_memos/<账号>/<课程 id>/<uuid>.<扩展名>`，
/// 课程 JSON 里只存文件名（见 `domain/ge_memo.dart`）。
/// 目录由调用方注入 → 可单测（同 `AccountAvatarStore`）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/ge_memo.dart';

class GeMemoStore {
  GeMemoStore(this.directory);

  /// 根目录（通常是应用私有目录下的 `ge_memos/`）。
  final Directory directory;

  /// 某账号某课程的图片目录（不保证存在）。
  Directory courseDir(String account, String courseId) => Directory(
    p.join(
      directory.path,
      geMemoSafeSegment(account),
      geMemoSafeSegment(courseId),
    ),
  );

  /// 文件名 → 绝对路径（不校验存在性）。
  String pathOf(String account, String courseId, String fileName) =>
      p.join(courseDir(account, courseId).path, fileName);

  /// 文件存在时返回绝对路径，否则 null（→ 界面回退占位图）。
  String? resolve(String account, String courseId, String fileName) {
    if (fileName.isEmpty) return null;
    final file = File(pathOf(account, courseId, fileName));
    return file.existsSync() ? file.path : null;
  }

  /// 落盘一张图片，返回文件名。
  ///
  /// [fileName] 可指定（测试用）；缺省生成 `<uuid>.<ext>`，因此
  /// **同名图片可以共存**（备忘录是多图网格，允许重复添加同一张图）。
  Future<String> save({
    required String account,
    required String courseId,
    required Uint8List bytes,
    required String ext,
    String? fileName,
  }) async {
    final dir = courseDir(account, courseId);
    if (!dir.existsSync()) await dir.create(recursive: true);
    final name = (fileName == null || fileName.isEmpty)
        ? '${const Uuid().v4()}.${geMemoNormalizeExt('x.$ext')}'
        : fileName;
    await File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// 删除一张图片（不存在 / 被占用都不抛：记录已摘掉，界面照常）。
  Future<void> remove({
    required String account,
    required String courseId,
    required String fileName,
  }) async {
    if (fileName.isEmpty) return;
    await _deleteQuietly(File(pathOf(account, courseId, fileName)));
  }

  /// 删除该课程的全部图片文件（清空备忘录 / 删除课程时调用）。
  Future<void> removeAllOfCourse(String account, String courseId) async {
    final dir = courseDir(account, courseId);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is File) await _deleteQuietly(entity);
    }
  }

  /// 删除该账号的全部备忘录图片（删除账号时调用）。
  Future<void> removeAllOfAccount(String account) async {
    final dir = Directory(p.join(directory.path, geMemoSafeSegment(account)));
    if (!dir.existsSync()) return;
    await _deleteQuietly(dir);
  }

  /// 该课程已占用的字节数（0 = 目录不存在）。
  int bytesOf(String account, String courseId) {
    final dir = courseDir(account, courseId);
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      try {
        total += entity.lengthSync();
      } catch (_) {
        // 统计失败不影响主流程
      }
    }
    return total;
  }

  /// 删除失败（被占用 / 权限）不抛：记录已摘掉，界面照常。
  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: entity is Directory);
    } catch (_) {
      // 落盘尽力而为
    }
  }
}
