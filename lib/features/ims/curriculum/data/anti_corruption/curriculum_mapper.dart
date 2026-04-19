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
