import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/major/data/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_box_provider.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_index_box_provider.dart';

part 'major_local_datasource_provider.g.dart';

@riverpod
Future<MajorLocalDataSource> majorLocalDataSource(
  MajorLocalDataSourceRef ref,
) async {
  final box = await ref.watch(majorBoxProvider.future);
  final indexBox = await ref.watch(majorIndexBoxProvider.future);

  return MajorLocalDataSource(box, indexBox);
}
