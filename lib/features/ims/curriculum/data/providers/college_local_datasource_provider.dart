import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/college_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/college_box_provider.dart';

part 'college_local_datasource_provider.g.dart';

@riverpod
CollegeLocalDataSource collegeLocalDataSource(CollegeLocalDataSourceRef ref) {
  final box = ref.watch(collegeBoxProvider);

  return CollegeLocalDataSource(box);
}
