import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_box_provider.dart';

part 'grades_local_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
Future<GradesLocalDataSource> gradesLocalDataSource(
  GradesLocalDataSourceRef ref,
) async {
  final box = await ref.watch(gradesBoxProvider.future);
  return GradesLocalDataSource(box);
}
