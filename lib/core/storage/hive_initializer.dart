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
  /// 单次初始化（幂等）。
  ///
  /// ⚠ `Hive.registerAdapter` 对同一个 typeId 重复注册会抛「already registered」，
  /// 因此初始化**只能跑一次**：`main()` 为了在首帧前拿到外观偏好会先调一次，
  /// `SplashScreen._checkAuth()` 随后还会再调一次（历史调用点），两次都必须安全。
  static Future<void>? _init;

  /// 幂等初始化：重复调用复用同一次结果。
  static Future<void> init() => _init ??= _run();

  static Future<void> _run() async {
    final hiveRootPath = "D:/Project/Ongoing/smarter_jxufe/app_data";

    await Hive.initFlutter(hiveRootPath);
    _registerAdapters();
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
}
