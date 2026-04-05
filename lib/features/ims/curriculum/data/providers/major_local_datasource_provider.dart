import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/major_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/major_box_provider.dart';

part 'major_local_datasource_provider.g.dart';

@riverpod
MajorLocalDataSource majorLocalDataSource(MajorLocalDataSourceRef ref) {
  final box = ref.watch(majorBoxProvider);

  return MajorLocalDataSource(box);
}
