import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 课表 HTML 解析器
///
/// 从教务系统课表页面 HTML 中解析出 [ScheduleEntry] 列表。
/// 其中"上课时间地点"字段会被进一步解析为 [ClassTime] 列表。
class ScheduleHtmlParser {
  // ─── 正则表达式 ───────────────────────────────────────────────

  /// 匹配一次上课安排，如 `1-16周(单) 一[6-8] 麦三教3407(70)(麦庐园校区)`
  ///
  /// 分组: 1=起始周, 2=结束周, 3=单/双(可选), 4=星期, 5=起始节, 6=结束节, 7=地点剩余部分
  static final RegExp _sessionRegex = RegExp(
    r'(\d+)-(\d+)周(?:\(([单双])\))?\s*([一二三四五六日])\[(\d+)-(\d+)\]\s*(.+)',
  );

  /// 匹配地点部分，如 `麦三教3407(70)(麦庐园校区)`
  ///
  /// 分组: 1=教室名称, 2=容量, 3=校区(可选)
  static final RegExp _locationRegex = RegExp(
    r'^(.+?)\((\d+)\)(?:\((.+?)\))?$',
  );

  /// 匹配课程代码+名称，如 `[1004600282]大学英语II`
  static final RegExp _courseRegex = RegExp(r'^\[([^\]]+)\](.+)$');

  /// 匹配教师代码+姓名，如 `[1200400772]史希平`
  static final RegExp _teacherRegex = RegExp(r'^\[([^\]]+)\](.+)$');

  // ─── 公开方法 ─────────────────────────────────────────────────

  /// 解析课表 HTML，返回 [ScheduleEntry] 列表
  List<ScheduleEntry> parse(String html) {
    final rows = _extractRawRows(html);
    final entries = <ScheduleEntry>[];

    for (final cells in rows) {
      if (cells.length < 12) {
        logInfo('跳过列数不足的行: ${cells.length}列 → $cells');
        continue;
      }

      try {
        entries.add(_parseRow(cells));
      } catch (e) {
        logInfo('解析课表行失败: $e\n原始数据: $cells');
      }
    }

    return entries;
  }

  // ─── 私有方法 ─────────────────────────────────────────────────

  /// 从 HTML 中提取所有非表头行的单元格文本
  List<List<String>> _extractRawRows(String html) {
    final document = parser.parse(html);
    final tables = document.querySelectorAll('table');

    if (tables.length != 1) {
      logInfo(html);
      throw Exception('期望有1个 table，但找到了${tables.length}个 table');
    }

    final table = tables.first;
    final rows = table
        .querySelectorAll('tr')
        .where((tr) => !tr.classes.contains('H'))
        .toList();
    final List<List<String>> result = [];

    for (var tr in rows) {
      final tds = tr.children
          .whereType<Element>()
          .where((td) => !td.classes.contains('td1'))
          .toList();

      final rowCells = tds.map((td) {
        for (final br in td.querySelectorAll('br')) {
          br.replaceWith(Text('\n'));
        }
        return td.text.trim();
      }).toList();

      if (rowCells.isNotEmpty) {
        result.add(rowCells);
      }
    }

    return result;
  }

  /// 解析一行原始单元格数组为 [ScheduleEntry]
  ///
  /// 列索引对应关系（基于 `schedule_remote_datasource.dart` 中的 thead）：
  /// 0=上课班级代码, 1=上课班级名称, 2=课程, 3=总学时, 4=学分,
  /// 5=修读性质, 6=任课教师, 7=选课状态, 8=外年级/专业选课,
  /// 9=教材, 10=上课时间地点, 11=备注
  ScheduleEntry _parseRow(List<String> cells) {
    final courseMatch = _courseRegex.firstMatch(cells[2]);
    final courseCode = courseMatch?.group(1) ?? '';
    final courseName = courseMatch?.group(2) ?? cells[2];

    final teacherMatch = _teacherRegex.firstMatch(cells[6]);
    final teacherCode = teacherMatch?.group(1) ?? '';
    final teacherName = teacherMatch?.group(2) ?? cells[6];

    final classTimes = _parseClassTimes(cells[10]);

    return ScheduleEntry(
      classCode: cells[0],
      className: cells[1],
      courseCode: courseCode,
      courseName: courseName,
      totalHours: int.tryParse(cells[3]) ?? 0,
      credits: double.tryParse(cells[4]) ?? 0,
      studyNature: cells[5],
      teacherCode: teacherCode,
      teacherName: teacherName,
      selectionStatus: cells[7],
      isCrossMajor: cells[8] == '是',
      hasTextbook: cells[9] == '是',
      classTimes: classTimes,
      remark: cells.length > 11 ? cells[11].nullIfEmpty : null,
    );
  }

  /// 解析"上课时间地点"字段为 [ClassTime] 列表
  ///
  /// 多个上课时段以英文逗号 `,` 分隔
  List<ClassTime> _parseClassTimes(String raw) {
    if (raw.isEmpty) return const [];

    // 按英文逗号分割（注意教室名中不含逗号，所以直接 split 是安全的）
    final parts = raw.split(',');
    final results = <ClassTime>[];

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final match = _sessionRegex.firstMatch(trimmed);
      if (match == null) {
        logInfo('无法解析上课时间: "$trimmed"');
        continue;
      }

      final dayOfWeek = DayOfWeek.fromChinese(match.group(4)!);
      final location = match.group(7)!;
      final locMatch = _locationRegex.firstMatch(location);

      results.add(
        ClassTime(
          startWeek: int.parse(match.group(1)!),
          endWeek: int.parse(match.group(2)!),
          weekParity: WeekParity.fromChinese(match.group(3)),
          dayOfWeek: dayOfWeek,
          startPeriod: int.parse(match.group(5)!),
          endPeriod: int.parse(match.group(6)!),
          classroom: locMatch?.group(1) ?? location,
          capacity: locMatch != null ? int.tryParse(locMatch.group(2)!) : null,
          campus: locMatch?.group(3),
        ),
      );
    }

    return results;
  }
}

/// 扩展方法：空字符串 → null
extension _StringNullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
