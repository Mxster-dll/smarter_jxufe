import 'dart:io';

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
    await Hive.initFlutter(resolveDataDir());
    _registerAdapters();
  }

  /// 本地数据目录（`app_data/`）的解析顺序 —— **刻意不写死本机绝对路径**
  /// （公开仓库不写本机路径，守卫 §34.5 判据③ 盯着；要固定到别处用 ① 覆盖）：
  ///   ① 构建参数 `DATA_DIR`：`--dart-define=DATA_DIR=<绝对路径>`
  ///      或 `--dart-define-from-file=config.local.json`（该文件已 gitignore）；
  ///   ② 从**当前工作目录**逐级上溯找带 `pubspec.yaml` 的仓库根 → `<仓库根>/app_data`；
  ///   ③ 从**可执行文件所在目录**同样上溯（双击 exe 时 cwd 是 exe 目录，靠这条兜住）；
  ///   ④ 都没有 → 当前工作目录下的 `app_data/`。
  ///
  /// ⚠ 之所以要传**绝对**路径给 `initFlutter`：它内部是
  /// `Hive.init(path.join(文档目录, subDir))`，而 `path.join` 遇到绝对子路径会**整体替换**
  /// （实测 `join('C:\\…\\文档', 'D:/…/app_data') == 'D:/…/app_data'`）；传相对子路径会落到
  /// 「文档」目录里，不是仓库里这份数据。
  static String resolveDataDir({List<String?>? startDirs}) {
    const override = String.fromEnvironment('DATA_DIR');
    if (override.trim().isNotEmpty) return override.trim();
    final starts = startDirs ??
        <String?>[Directory.current.path, File(Platform.resolvedExecutable).parent.path];
    for (final start in starts) {
      final root = _findRepoRoot(start);
      if (root != null) return '$root${Platform.pathSeparator}app_data';
    }
    return '${Directory.current.path}${Platform.pathSeparator}app_data';
  }

  /// 从 [start] 逐级上溯（最多 6 层）找带 `pubspec.yaml` 的仓库根。
  static String? _findRepoRoot(String? start) {
    if (start == null || start.isEmpty) return null;
    var dir = Directory(start);
    for (var i = 0; i < 6; i++) {
      if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
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
