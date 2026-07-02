import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/schedule_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/datasources/schedule_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

class ScheduleRepository {
  final ImsAuthRepository _imsAuthRepo;
  final ScheduleRemoteDataSource _remoteDataSource;
  final ScheduleHtmlParser _htmlParser;

  ScheduleRepository({
    required ImsAuthRepository imsAuthRepo,
    required ScheduleRemoteDataSource remoteDataSource,
    required ScheduleHtmlParser htmlParser,
  }) : _imsAuthRepo = imsAuthRepo,
       _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser;

  /// [year] 学年，如 "2025"。
  /// [semester] 学期，如 "1"。
  /// [studentId] 学号。
  Future<List<ScheduleEntry>> getSchedule({
    required String year,
    required String semester,
    required String studentId,
  }) async {
    final jsessionResult = await _imsAuthRepo.getJsessionId();
    if (jsessionResult.isLeft()) throw Exception('获取 JSESSIONID 失败');
    final jsessionId = jsessionResult.getOrElse(() => '') ?? '';
    if (jsessionId.isEmpty) throw Exception('JSESSIONID 为空');

    final html = await _remoteDataSource.getScheduleInTableHtml(
      jsessionId: jsessionId,
      year: year,
      semester: semester,
      studentId: studentId,
    );
    return _htmlParser.parse(html);
  }
}
