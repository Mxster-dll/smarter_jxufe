import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_box_provider.dart';

part 'curriculum_local_datasource_provider.g.dart';

@riverpod
CurriculumLocalDataSource curriculumLocalDataSource(
  CurriculumLocalDataSourceRef ref,
) {
  final box = ref.watch(curriculumBoxProvider);
  return CurriculumLocalDataSource(box);
}
