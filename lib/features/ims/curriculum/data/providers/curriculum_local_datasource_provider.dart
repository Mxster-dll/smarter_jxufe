import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_box_provider.dart';

part 'curriculum_local_datasource_provider.g.dart';

@riverpod
Future<CurriculumLocalDataSource> curriculumLocalDataSource(
  CurriculumLocalDataSourceRef ref,
) async {
  final box = await ref.watch(curriculumBoxProvider.future);
  return CurriculumLocalDataSource(box);
}
