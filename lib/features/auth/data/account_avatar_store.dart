import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';

/// 账号头像的本地文件存储（目录由调用方注入 → 可单测）。
///
/// 目录 = 应用私有目录下的 `avatars/`；**账户记录里只存文件名**。
/// 选图时把原图**拷进来**：原图随后被删/移动/换机都不影响头像，
/// 卸载应用才会清掉。一个账号至多一个文件（换图先清旧文件）。
class AccountAvatarStore {
  AccountAvatarStore(this.directory);

  final Directory directory;

  /// 文件名 → 绝对路径（不校验存在性）。
  String pathOf(String fileName) => p.join(directory.path, fileName);

  /// 文件存在时返回绝对路径，否则 null（→ 界面回退首字/图标）。
  String? resolve(String fileName) {
    if (fileName.isEmpty) return null;
    final file = File(pathOf(fileName));
    return file.existsSync() ? file.path : null;
  }

  /// 把 [sourcePath] 拷进私有目录，返回新文件名（含归一化扩展名）。
  ///
  /// 同账号的旧头像（含扩展名不同者）先清掉，避免残留下多个文件。
  Future<String> save(String cardNumber, String sourcePath) async {
    final fileName = avatarFileName(cardNumber, sourcePath);
    final target = File(pathOf(fileName));
    // 用户选的本来就是本目录里的这张图 → 无需拷贝（先删会把源删掉）
    if (p.equals(sourcePath, target.path)) return fileName;
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    await removeAllOf(cardNumber);
    await File(sourcePath).copy(target.path);
    return fileName;
  }

  /// 删除该账号名下的全部头像文件（换图 / 删除账户时清理）。
  Future<void> removeAllOf(String cardNumber) async {
    if (!directory.existsSync()) return;
    final base = avatarBaseName(cardNumber);
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      if (p.basenameWithoutExtension(entity.path) != base) continue;
      await _deleteQuietly(entity);
    }
  }

  /// 删除指定头像文件（「移除头像」）。
  Future<void> remove(String fileName) async {
    if (fileName.isEmpty) return;
    final file = File(pathOf(fileName));
    if (!file.existsSync()) return;
    await _deleteQuietly(file);
  }

  /// 删除失败（被占用 / 权限）不抛：头像字段已清空，界面照样回退。
  Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // 落盘尽力而为
    }
  }
}
