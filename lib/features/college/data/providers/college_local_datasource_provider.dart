import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_box_provider.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_index_box_provider.dart';

part 'college_local_datasource_provider.g.dart';

@riverpod
CollegeLocalDataSource collegeLocalDataSource(CollegeLocalDataSourceRef ref) {
  final box = ref.watch(collegeBoxProvider);
  final indexBox = ref.watch(collegeIndexBoxProvider);

  return CollegeLocalDataSource(box, indexBox);
}
