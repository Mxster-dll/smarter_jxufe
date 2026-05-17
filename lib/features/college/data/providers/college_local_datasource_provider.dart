import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/datasources/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_box_provider.dart';

part 'college_local_datasource_provider.g.dart';

@riverpod
Future<CollegeLocalDataSource> collegeLocalDataSource(
  CollegeLocalDataSourceRef ref,
) async {
  final box = await ref.read(collegeBoxProvider.future);

  return CollegeLocalDataSource(box);
}
