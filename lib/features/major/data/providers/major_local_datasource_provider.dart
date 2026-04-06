import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/major/data/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_box_provider.dart';

part 'major_local_datasource_provider.g.dart';

@riverpod
MajorLocalDataSource majorLocalDataSource(MajorLocalDataSourceRef ref) {
  final box = ref.watch(majorBoxProvider);
  return MajorLocalDataSource(box);
}
