import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/weighted_grade_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/weighted_grade_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/data/weighted_grade_repository.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

final weightedGradeRepositoryProvider = FutureProvider<WeightedGradeRepository>(
  (ref) async {
    final dio = ref.watch(currentImsDioProvider);
    final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

    return WeightedGradeRepository(
      remoteDataSource: WeightedGradeRemoteDataSource(dio),
      htmlParser: WeightedGradeHtmlParser(),
      imsAuthRepo: imsAuthRepo,
    );
  },
);

/// 按类型 ID 获取加权排名。typeId: 1=课程加权所有学年。
final weightedGradeRankingProvider = FutureProvider.family<WeightedGrade?, int>(
  (ref, typeId) async {
    final repo = await ref.watch(weightedGradeRepositoryProvider.future);
    final result = await repo.getWeightedGrade(typeId: typeId);
    return result.fold((_) => null, (wg) => wg);
  },
);
