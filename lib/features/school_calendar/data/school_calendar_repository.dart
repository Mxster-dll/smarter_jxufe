import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/school_calendar_html_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/school_calendar_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 校历数据仓库：取 HTML → 解析为结构化 [SchoolCalendar]。
class SchoolCalendarRepository {
  final SchoolCalendarRemoteDataSource _datasource;
  final SchoolCalendarHtmlParser _parser;

  SchoolCalendarRepository(this._datasource, this._parser);

  Future<SchoolCalendar> fetchCalendar({
    required int xn,
    required int xq,
  }) async {
    final html = await _datasource.fetchCalendarHtml(xn: xn, xq: xq);
    return _parser.parse(html, xn: xn, xq: xq);
  }
}
