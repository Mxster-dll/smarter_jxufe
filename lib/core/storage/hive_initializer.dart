import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';

import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class HiveInitializer {
  static Future<void> init() async {
    await Hive.initFlutter();
    _registerAdapters();
    await _openBoxes();
  }

  static void _registerAdapters() {
    Hive.registerAdapter(AssessmentMethodAdapter());
    Hive.registerAdapter(CourseImportanceAdapter());
    Hive.registerAdapter(CourseNatureAdapter());
    Hive.registerAdapter(CourseRequirementAdapter());
    Hive.registerAdapter(CreditHourAdapter());
    Hive.registerAdapter(CourseAdapter());
    Hive.registerAdapter(CurriculumAdapter());
    Hive.registerAdapter(MajorAdapter());
    Hive.registerAdapter(CollegeAdapter());
    Hive.registerAdapter(FunctionTypeAdapter());
  }

  static Future<void> _openBoxes() async {
    await Hive.openBox<Curriculum>('curriculums');
    await Hive.openBox<College>('colleges');
    await Hive.openBox<Major>('majors');
  }
}
