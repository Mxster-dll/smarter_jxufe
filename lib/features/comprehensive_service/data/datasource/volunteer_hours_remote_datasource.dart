import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';

class VolunteerHoursRemoteDataSource {
  final Dio _dio;

  VolunteerHoursRemoteDataSource(this._dio);

  Future<List<VolunteerActivity>> fetchVolunteerActivities() async {
    final response = await _dio.get('/admin/tzz/StuVolWork/stu_list.html');

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}');
    }

    return _parseHtml(response.data as String);
  }

  List<VolunteerActivity> _parseHtml(String html) {
    final document = html_parser.parse(html);
    final table = document.querySelector('#listTable');
    if (table == null) return [];

    final tbody = table.querySelector('tbody');
    if (tbody == null) return [];

    final rows = tbody.querySelectorAll('tr');
    final List<VolunteerActivity> activities = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 10) continue;

      try {
        final indexText = cells[0].text.trim();
        final index = int.tryParse(indexText) ?? 0;

        final activityName = cells[1].text.trim();
        final initiator = cells[2].text.trim();
        final responsiblePerson = cells[3].text.trim();
        final department = cells[4].text.trim();
        final activityCategory = cells[5].text.trim();
        final recognizedHours = cells[6].text.trim();
        final applicationStatus = cells[7].text.trim();
        final recognitionStatus = cells[8].text.trim();

        // 从操作列中提取 detail id 和 type
        String detailId = '';
        String detailType = '';
        final detailLink = cells[9].querySelector('a[href]');
        if (detailLink != null) {
          final href = detailLink.attributes['href'] ?? '';
          final idMatch = RegExp(
            "detail\\((\\d+),\\s*['\"]?(\\d+)['\"]?\\)",
          ).firstMatch(href);
          if (idMatch != null) {
            detailId = idMatch.group(1) ?? '';
            detailType = idMatch.group(2) ?? '';
          }
        }

        activities.add(
          VolunteerActivity(
            index: index,
            activityName: activityName,
            initiator: initiator,
            responsiblePerson: responsiblePerson,
            department: department,
            activityCategory: activityCategory,
            recognizedHours: recognizedHours,
            applicationStatus: applicationStatus,
            recognitionStatus: recognitionStatus,
            detailId: detailId,
            detailType: detailType,
          ),
        );
      } catch (_) {
        // 跳过解析失败的行
      }
    }

    return activities;
  }
}
