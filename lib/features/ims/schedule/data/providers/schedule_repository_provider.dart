import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/network/schedule_repository.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_html_parser_provider.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_remote_datasource_provider.dart';

part 'schedule_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<ScheduleRepository> scheduleRepository(ScheduleRepositoryRef ref) async {
  final remoteDataSource = ref.watch(scheduleRemoteDataSourceProvider);
  final htmlParser = ref.watch(scheduleHtmlParserProvider);

  return ScheduleRepository(
    remoteDataSource: remoteDataSource,
    htmlParser: htmlParser,
  );
}
