import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/schedule_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/schedule_remote_datasource.dart';

    // TODO 实现允许模糊匹配，即10-8月一定可以判断学年
class ScheduleRepository {
  final ScheduleRemoteDataSource _remoteDataSource;
  final ScheduleHtmlParser _htmlParser;

  ScheduleRepository({
    required ScheduleRemoteDataSource remoteDataSource,
    required ScheduleHtmlParser htmlParser,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser;

  Future<List<List<String>>> getSchedule() async {
    final html = await _remoteDataSource.getScheduleInTableHtml();
    return _htmlParser.parse(html);
  }
}
