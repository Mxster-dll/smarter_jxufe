/// 培养方案「开课学期」侧表的装配（`Box<String>` 单 key JSON）。
///
/// 形态照 `practice_curriculum_providers.dart`：**手写 provider，不走
/// riverpod_generator** —— 本模块的 `curriculum_box_provider.dart` 是生成物，
/// 往里加 provider 要重跑 build_runner（会顺带重写全仓生成物，并行会话下风险大）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_terms_local_datasource.dart';

/// 侧表 box（lazy 打开，无需改 `main.dart`）。
final curriculumTermsBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(curriculumTermsBoxName),
);

final curriculumTermsLocalDataSourceProvider =
    FutureProvider<CurriculumTermsLocalDataSource>((ref) async {
      final box = await ref.watch(curriculumTermsBoxProvider.future);
      return CurriculumTermsLocalDataSource(box);
    });
