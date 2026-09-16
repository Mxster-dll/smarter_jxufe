/// 分数估计 · 备忘录 providers：图片目录与选图实现。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/ge_memo.dart';
import 'ge_memo_importer.dart';
import 'ge_memo_store.dart';

/// 备忘录图片根目录（应用私有目录 `ge_memos/`），进程内只解析一次。
///
/// 目录内再按 `<账号>/<课程 id>/` 分档（见 [GeMemoStore]），因此切号不会串图。
final geMemoStoreProvider = FutureProvider<GeMemoStore>((ref) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, kGeMemoDirName));
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  return GeMemoStore(directory);
});

/// 选图实现（相册 / 拍照 / 文件多选）。
///
/// 抽成 provider 是为了让测试注入假实现 —— 否则 widget 测试里
/// 一按「添加图片」就会弹真系统对话框。
final geMemoPickerProvider = Provider<GeMemoPicker>(
  (ref) => const PlatformGeMemoPicker(),
);
