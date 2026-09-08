/// 综测本地存储：材料清单 + 各学年手动输入 + 附件文件管理。
library;

import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/zc_models.dart';

const _kMaterials = 'materials';
String _kManual(int year) => 'manual-$year';
const _uuid = Uuid();

/// 附件拷贝进应用目录失败（如文件不存在）抛出此异常。
class ZcFileException implements Exception {
  final String message;
  const ZcFileException(this.message);
  @override
  String toString() => message;
}

class ZcStore {
  final Box<String> box;

  /// 附件绝对目录（已创建）。
  final String filesDir;

  ZcStore(this.box, this.filesDir);

  // ---- 材料 ----
  Future<List<ZcMaterial>> loadMaterials() async {
    final raw = box.get(_kMaterials);
    if (raw == null || raw.isEmpty) return [];
    try {
      return zcMaterialsFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMaterials(List<ZcMaterial> list) =>
      box.put(_kMaterials, zcMaterialsJson(list));

  // ---- 手动输入 ----
  Future<ZcManual> loadManual(int year) async {
    final raw = box.get(_kManual(year));
    if (raw == null || raw.isEmpty) return const ZcManual();
    try {
      final decoded = jsonDecode(raw);
      return ZcManual.fromJson(
        decoded is Map<String, dynamic> ? decoded : null,
      );
    } catch (_) {
      return const ZcManual();
    }
  }

  Future<void> saveManual(int year, ZcManual manual) =>
      box.put(_kManual(year), jsonEncode(manual.toJson()));

  // ---- 附件 ----
  String get _fileStamp => _uuid.v4().substring(0, 8);

  /// 把外部文件拷入附件目录，返回相对文件名（含原扩展名）。
  Future<String> importFile(String srcPath) async {
    final src = File(srcPath);
    if (!await src.exists()) {
      throw ZcFileException('文件不存在：$srcPath');
    }
    final ext = p.extension(srcPath);
    final rel = '$_fileStamp$ext';
    await src.copy(p.join(filesDir, rel));
    return rel;
  }

  String fileAbsPath(String rel) => p.join(filesDir, rel);

  Future<void> deleteFile(String rel) async {
    final f = File(p.join(filesDir, rel));
    if (await f.exists()) await f.delete();
  }

  /// 删除材料及其附件（孤儿清理）。
  Future<void> deleteMaterial(List<ZcMaterial> all, ZcMaterial m) async {
    for (final rel in m.files) {
      await deleteFile(rel);
    }
    await saveMaterials([
      for (final x in all)
        if (x.id != m.id) x,
    ]);
  }
}
