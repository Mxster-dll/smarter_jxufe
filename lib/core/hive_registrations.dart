import 'package:hive/hive.dart';

import 'package:smarter_jxufe/data/course/models/assessment_method.dart';
import 'package:smarter_jxufe/data/course/models/course_importance.dart';
import 'package:smarter_jxufe/data/course/models/course_nature.dart';
import 'package:smarter_jxufe/data/course/models/course_requirement.dart';
import 'package:smarter_jxufe/data/course/models/course.dart';
import 'package:smarter_jxufe/data/curriculum/models/curriculum.dart';
import 'package:smarter_jxufe/data/common/models/college.dart';
import 'package:smarter_jxufe/data/common/models/major.dart';

Future<void> registerHiveAdapters() async {
  Hive.registerAdapter(AssessmentMethodAdapter());
  Hive.registerAdapter(CourseImportanceAdapter());
  Hive.registerAdapter(CourseNatureAdapter());
  Hive.registerAdapter(CourseRequirementAdapter());
  Hive.registerAdapter(CourseImportanceAdapter());
  Hive.registerAdapter(CourseAdapter());
  Hive.registerAdapter(CurriculumAdapter());
  Hive.registerAdapter(CollegeAdapter());
  Hive.registerAdapter(MajorAdapter());
}
