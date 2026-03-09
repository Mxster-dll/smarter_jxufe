// import 'package:html/parser.dart' as parser;
// import 'package:smarter_jxufe/data/course/models/Course.dart';

// import 'package:smarter_jxufe/utils/Log.dart';
// import 'package:smarter_jxufe/core/extension/DomElementExtension.dart';

// class CurriculumHtmlParser {
//   List<Map<String, String>> parse(String html) {
//     final tables = parser.parse(html).querySelectorAll('table');

//     if (tables.length != 1) {
//       logInfo(html);
//       throw Exception('期望有1个 table，但找到了${tables.length}个 table\n $tables');
//     }

//     final matrix = tables.first.toMatrix;
//     Map<String, int> idx = {};

//     final thead = matrix.first;
//     for (int i = 0; i < thead.length; i++) {
//       idx[thead[i]] = i;
//     }

//     Course lineToCourse(List<String> line) {
//       String info(String key) => line[idx[key]!].trim();

//       CourseBuilder builder = CourseBuilder();

//       builder.codeAndName = info('课程');
//       builder.credit = double.parse(info('学分'));
//       builder.creditHour = CreditHour(
//         int.parse(info('总学时')),
//         int.parse(info('讲授学时')),
//         int.parse(info('实验学时')),
//         int.parse(info('实践学时')),
//         int.parse(info('其它学时')),
//         double.parse(info('周学时')),
//       );

//       builder.categories = info('课程类别');
//       builder.nature = CourseNature.theory;
//       builder.importance = (info('课程地位') == '主干课程') ? .core : .general;
//       builder.assessmentMethod = AssessmentMethod.parse(info('考核方式'));
//       builder.identification = info('标识');

//       return builder.build();
//     }

//     return matrix.skip(1).map(lineToCourse).toList();
//   }
//   }
// }
