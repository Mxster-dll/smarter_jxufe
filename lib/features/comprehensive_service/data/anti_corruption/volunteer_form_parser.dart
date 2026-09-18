/// 《志愿服务时长认定登记表》（Word 原件）解析 —— 志愿活动**日期**的数据源。
///
/// 背景（2026-09-18）：详情页 `apply_one_detail.html?id=…` 现在一律返回
/// 「出错了」错误页（实测 5/5 条记录、各种 header 变体都是同一张 51271 字节页），
/// 逐行取时间的旧链路整条失效 → 列表里每个活动都没有日期 → 综测的
/// 「学年志愿时长」自动值恒为 null（回退手动填写）。
///
/// 学校页右上角「下载时长认定登记表」的接口 `StuVolWork/downloadInfo.do`
/// 仍然可用，返回的是**逐条活动**的登记表：
/// ```
/// 序号 | 活动名称 | 认定日期 | 所属类别 | 时长
/// 1    | Ad1149…  | 2025年10月27日 | A类 | 4.0小时
/// ```
/// 表格是「一份表两栏并排」的版式（表头有 2 组、每组的列序相同），所以这里
/// **不按固定列号取数**，而是「先找日期格，再往左取名称、往右取类别、同行找时长」。
///
/// 口径：日期取**认定日期**（唯一可得的口径）。学年归集在
/// `domain/volunteer_hours_stats.dart` 里按这个日期算，综测的
/// 「学年志愿时长」用它，**跨学年的活动不会被算进同一学年**。
library;

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/docx_text.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';

/// 认定登记表里的一行。
class VolunteerFormRow {
  /// 序号（表格第一列；取不到按 0）。
  final int index;

  /// 活动名称（原样，含登记表里的 `Sa0076` 这类编号前缀）。
  final String name;

  /// 认定日期，规范成 `YYYY-MM-DD`。
  final String date;

  /// 所属类别（`A类` / `B类` / `C类` / `D类`；取不到为空串）。
  final String category;

  /// 认定时长（`4.0`，已去掉「小时」后缀）。
  final String hours;

  const VolunteerFormRow({
    required this.index,
    required this.name,
    required this.date,
    this.category = '',
    this.hours = '',
  });

  /// 认定时长（小时）；解析不出按 0。
  double get hoursValue => double.tryParse(hours) ?? 0;

  @override
  String toString() =>
      'VolunteerFormRow($index, $name, $date, $category, $hours)';
}

/// 只解析 `word/document.xml`（便于单测，不碰 ZIP）。
List<VolunteerFormRow> parseVolunteerFormRows(List<List<String>> rows) {
  final out = <VolunteerFormRow>[];
  for (final cells in rows) {
    final dateAt = cells.indexWhere((c) => volunteerFormDateOf(c) != null);
    // 日期必须不在首列 —— 它左边至少要有「活动名称」。
    if (dateAt < 1) continue;
    final name = cells[dateAt - 1].trim();
    if (name.isEmpty) continue;
    // 表头行（序号 | 活动名称 | 认定日期 | …）、合计行（志愿服务总时长）不算记录。
    if (name == '活动名称' || name.contains('总时长')) continue;
    final date = volunteerFormDateText(cells[dateAt])!;
    final category = dateAt + 1 < cells.length
        ? cells[dateAt + 1].trim()
        : '';
    var hours = '';
    for (var i = dateAt + 1; i < cells.length; i++) {
      if (!cells[i].contains('小时')) continue;
      hours = cells[i].replaceAll('小时', '').trim();
      break;
    }
    out.add(
      VolunteerFormRow(
        index: dateAt >= 2 ? (int.tryParse(cells[dateAt - 2].trim()) ?? 0) : 0,
        name: name,
        date: date,
        category: category,
        hours: hours,
      ),
    );
  }
  return out;
}

/// DOCX 字节 → 认定登记表的行；不是 docx / 解析不出 → 空列表。
List<VolunteerFormRow> parseVolunteerForm(List<int> bytes) =>
    parseVolunteerFormRows(docxTableRowsOfBytes(bytes));

final RegExp _formDate = RegExp(
  r'^(\d{4})\s*(?:年|[-/.])\s*(\d{1,2})\s*(?:月|[-/.])\s*(\d{1,2})\s*日?$',
);

/// 解析登记表里的日期（`2025年10月27日` / `2025-10-27` / `2025/10/27`）。
DateTime? volunteerFormDateOf(String raw) {
  final match = _formDate.firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  // 回读校验（2025-02-30 之类要被判错）。
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

/// `2025年10月27日` → `2025-10-27`；解析不出 → null。
String? volunteerFormDateText(String raw) {
  final date = volunteerFormDateOf(raw);
  if (date == null) return null;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// 活动名的匹配键：**去掉全部空白**。
///
/// 登记表与列表页的空格不一致（列表 `Ea  574  迎新晚会志愿时长` ↔
/// 登记表 `Ea 574 迎新晚会志愿时长`），逐字符比对必然错配。
String volunteerActivityKey(String name) =>
    name.replaceAll(RegExp(r'[\s\u3000]+'), '');

/// 用认定登记表的日期补齐活动列表（列表页本身没有时间列）。
///
/// 按 [volunteerActivityKey] 匹配名称；**只补没有日期的行**（详情页若哪天
/// 恢复，已有值优先）。未命中的行原样保留 —— 调用方据此决定是否走兜底链路。
List<VolunteerActivity> volunteerApplyFormDates(
  List<VolunteerActivity> activities,
  List<VolunteerFormRow> rows,
) {
  if (activities.isEmpty || rows.isEmpty) return activities;
  final byName = <String, String>{};
  for (final row in rows) {
    if (row.date.isEmpty) continue;
    byName.putIfAbsent(volunteerActivityKey(row.name), () => row.date);
  }
  if (byName.isEmpty) return activities;
  var changed = false;
  final out = <VolunteerActivity>[];
  for (final activity in activities) {
    final filled =
        activity.startDate.isEmpty && activity.endDate.isEmpty
        ? byName[volunteerActivityKey(activity.activityName)]
        : null;
    if (filled == null) {
      out.add(activity);
      continue;
    }
    changed = true;
    out.add(activity.copyWith(startDate: filled, endDate: filled));
  }
  return changed ? out : activities;
}
