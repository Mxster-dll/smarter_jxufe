import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_box_provider.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_index_box_provider.dart';

part 'college_local_datasource_provider.g.dart';

@riverpod
Future<CollegeLocalDataSource> collegeLocalDataSource(
  CollegeLocalDataSourceRef ref,
) async {
  final box = await ref.read(collegeBoxProvider.future);
  final indexBox = await ref.watch(collegeIndexBoxProvider.future);

  return CollegeLocalDataSource(box, indexBox);
}
