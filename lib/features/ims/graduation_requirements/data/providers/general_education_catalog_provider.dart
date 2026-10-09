import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/graduation_requirements/data/anti_corruption/general_education_catalog_parser.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';

/// 通识课程库 asset 路径。
///
/// 生成脚本 = `tool/make_ge_catalog.py`（源 xlsx 不入库），
/// 守卫 = `test/general_education_catalog_test.dart`。
const String kGeneralEducationCatalogAsset =
    'assets/general_education/ge_catalog.json';

/// asset 解析器 Provider。
final generalEducationCatalogParserProvider =
    Provider<GeneralEducationCatalogParser>(
      (ref) => const GeneralEducationCatalogParser(),
    );

/// 通识课程库（**纯本地 asset，不发网络**）。
///
/// 读失败时返回 [GeneralEducationCatalog.empty] 而不是抛异常：这一项只是
/// 四个通识模块的口径来源，缺了不该把整页打红（页面会照实说明）。
final generalEducationCatalogProvider = FutureProvider<GeneralEducationCatalog>(
  (ref) async {
    final parser = ref.watch(generalEducationCatalogParserProvider);
    try {
      final raw = await rootBundle.loadString(kGeneralEducationCatalogAsset);
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return GeneralEducationCatalog.empty;
      }
      return parser.parse(decoded);
    } catch (_) {
      return GeneralEducationCatalog.empty;
    }
  },
);
