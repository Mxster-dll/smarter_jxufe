import 'package:hive/hive.dart';

import 'package:smarter_jxufe/data/ims/course/models/AssessmentMethod.dart';
import 'package:smarter_jxufe/data/ims/course/models/CourseImportance.dart';
import 'package:smarter_jxufe/data/ims/course/models/CourseNature.dart';
import 'package:smarter_jxufe/data/ims/course/models/CourseRequirement.dart';
import 'package:smarter_jxufe/data/ims/course/models/Course.dart';
import 'package:smarter_jxufe/data/ims/curriculum/models/Curriculum.dart';

Future<void> registerHiveAdapters() async {
  Hive.registerAdapter(AssessmentMethodAdapter());
  Hive.registerAdapter(CourseImportanceAdapter());
  Hive.registerAdapter(CourseNatureAdapter());
  Hive.registerAdapter(CourseRequirementAdapter());
  Hive.registerAdapter(CourseImportanceAdapter());
  Hive.registerAdapter(CourseAdapter());
  Hive.registerAdapter(CurriculumAdapter());
}
