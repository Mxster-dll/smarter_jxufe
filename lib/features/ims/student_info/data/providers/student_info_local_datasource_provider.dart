import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_box_provider.dart';

part 'student_info_local_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
Future<StudentInfoLocalDataSource> studentInfoLocalDataSource(
  StudentInfoLocalDataSourceRef ref,
) async {
  final box = await ref.watch(studentInfoBoxProvider.future);
  return StudentInfoLocalDataSource(box);
}
