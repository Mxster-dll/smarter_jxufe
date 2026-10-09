/// 实践环节（培养方案第二张表）的装配。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/practice_curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/practice_curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/practice_curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/practice_curriculum_repository.dart';

/// 实践环节缓存 box 名（`Box<String>` 单 key JSON；见 §3「模型」）。
const String practiceCurriculumBoxName = 'practiceCurriculums';

/// 缓存 box（lazy 打开，无需改 `main.dart`）。
final practiceCurriculumBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(practiceCurriculumBoxName),
);

final practiceCurriculumHtmlParserProvider =
    Provider<PracticeCurriculumHtmlParser>(
      (ref) => const PracticeCurriculumHtmlParser(),
    );

/// 复用理论课程那条的 `currentImsDioProvider`（同一个教务会话）。
final practiceCurriculumRemoteDataSourceProvider =
    Provider<PracticeCurriculumRemoteDataSource>(
      (ref) => PracticeCurriculumRemoteDataSource(
        ref.watch(currentImsDioProvider),
      ),
    );

final practiceCurriculumLocalDataSourceProvider =
    FutureProvider<PracticeCurriculumLocalDataSource>((ref) async {
      final box = await ref.watch(practiceCurriculumBoxProvider.future);
      return PracticeCurriculumLocalDataSource(box);
    });

final practiceCurriculumRepositoryProvider =
    FutureProvider<PracticeCurriculumRepository>((ref) async {
      final local = await ref.watch(
        practiceCurriculumLocalDataSourceProvider.future,
      );
      final remote = ref.watch(practiceCurriculumRemoteDataSourceProvider);
      final parser = ref.watch(practiceCurriculumHtmlParserProvider);
      final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);
      return PracticeCurriculumRepository(
        localDataSource: local,
        remoteDataSource: remote,
        htmlParser: parser,
        imsAuthRepo: imsAuthRepo,
      );
    });
