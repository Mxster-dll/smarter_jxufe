import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/schedule_remote_datasource.dart';

part 'schedule_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
ScheduleRemoteDataSource scheduleRemoteDataSource(
  ScheduleRemoteDataSourceRef ref,
) {
  final dio = ref.watch(currentImsDioProvider);

  return ScheduleRemoteDataSource(dio);
}
