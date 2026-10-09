import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';

class CurriculumMapper {
  static (String, String) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[(\d+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      final code = match.group(1)!;
      final name = match.group(2)!;
      return (code, name);
    }

    return ('', raw);
  }

  /// 「开课学期」列的表头写法（教务原文是 `学年学期`；另两个是防表头改名的兜底）。
  static const List<String> _termHeaders = ['学年学期', '开课学期', '学期'];

  /// 取每行的**开课学期**原文（与 [fromRows] **同序、同长**）。
  ///
  /// 按**表头名**找列（表里夹着隐藏列与合并列，按下标会错位）；找不到这一列、
  /// 或压根没有数据行时返回**空列表** —— 调用方按「这份方案没有开课学期信息」
  /// 处理（界面写「未排定」），不要瞎兜一个默认学期。
  ///
  /// 单行这一列为空是**正常**的（真实表里确实有没排定学期的课），空串原样保留。
  List<String> semestersFromRows(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final thead = rows.first;
    final at = thead.indexWhere((h) => _termHeaders.contains(h.trim()));
    if (at < 0) return const [];
    return [
      for (final line in rows.skip(1))
        at < line.length ? line[at].trim() : '',
    ];
  }

  List<Course> fromRows(List<List<String>> rows) {
    Map<String, int> idx = {};

    final thead = rows.first;
    for (int i = 0; i < thead.length; i++) {
      idx[thead[i]] = i;
    }

    return rows.skip(1).map((line) {
      String info(String key) => line[idx[key]!].trim();

      final (code, name) = extractCodeAndName(info('课程'));

      final categories = info('课程类别').split('/');

      return Course(
        code: code,
        name: name,
        credit: .parse(info('学分')),
        creditHour: CreditHour(
          total: .parse(info('总学时')),
          lecture: .parse(info('讲授学时')),
          lab: .parse(info('实验学时')),
          practice: .parse(info('实践学时')),
          other: .parse(info('其它学时')),
          weekly: .parse(info('周学时')),
        ),
        mainCategory: categories[0],
        subCategory: categories[1],
        tertiaryCategory: categories.length > 3 ? categories[2] : null,
        requirement: .parse(categories.last),
        nature: .theory,
        importance: (info('课程地位') == '主干课程') ? .core : .general,
        assessmentMethod: .parse(info('考核方式')),
        identification: info('标识'),
      );
    }).toList();
  }
}
