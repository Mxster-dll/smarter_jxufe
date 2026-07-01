import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/schedule_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/schedule_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

class ScheduleRepository {
  final ScheduleRemoteDataSource _remoteDataSource;
  final ScheduleHtmlParser _htmlParser;

  ScheduleRepository({
    required ScheduleRemoteDataSource remoteDataSource,
    required ScheduleHtmlParser htmlParser,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser;

  Future<List<ScheduleEntry>> getSchedule() async {
    final html = await _remoteDataSource.getScheduleInTableHtml();
    return _htmlParser.parse(html);
  }
}
