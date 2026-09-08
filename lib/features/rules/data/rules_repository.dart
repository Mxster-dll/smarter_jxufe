import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/doc_blocks.dart';
import '../domain/rule_doc.dart';
import 'md_parser.dart';

/// 规章制度模块数据入口：资产常量 + Riverpod 提供者。
const kRulesMetaAsset = 'assets/rules/meta/rules_catalog.json';

final rulesCatalogProvider = FutureProvider<RulesCatalog>((ref) async {
  final json = await rootBundle.loadString(kRulesMetaAsset);
  return RulesCatalog.fromJson(
    jsonDecode(json) as Map<String, dynamic>,
  );
});

/// 按文档懒加载 md 文本并解析（带缓存）。
final rulesArticleProvider =
    FutureProvider.family<DocArticle, RuleDoc>((ref, doc) async {
  final md = await rootBundle.loadString(doc.mdAsset);
  return MdParser().parse(md);
});

/// 打开原件 PDF：复制到临时目录后交给系统默认程序。
/// Windows 用 explorer.exe（ShellExecute），其余平台尝试 url_launcher file://。
Future<void> openOriginalPdf(RuleDoc doc) async {
  final data = await rootBundle.load(doc.pdfAsset);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}jxufe_rules_${doc.id}.pdf');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [file.path]);
    return;
  }
  final ok = await launchUrl(Uri.file(file.path));
  if (!ok) {
    throw StateError('当前设备无法打开 PDF：${file.path}');
  }
}
