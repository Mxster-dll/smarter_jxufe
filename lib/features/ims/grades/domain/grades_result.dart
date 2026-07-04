import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

class GradesResult {
  final List<Grade> grades;

  /// 本次远程获取相比缓存新增的课程名称（仅远程拉取时有值，缓存命中时为 null）。
  final List<String>? newCourseNames;

  /// 本次远程获取相比缓存减少的课程名称（仅远程拉取时有值，缓存命中时为 null）。
  final List<String>? removedCourseNames;

  const GradesResult({
    required this.grades,
    this.newCourseNames,
    this.removedCourseNames,
  });

  /// 是否有变更（新增或撤回）。
  bool get hasChanges =>
      (newCourseNames != null && newCourseNames!.isNotEmpty) ||
      (removedCourseNames != null && removedCourseNames!.isNotEmpty);

  Map<String, dynamic> toMap() => {
    'grades': grades.map((g) => g.toMap()).toList(),
    // diff 字段不持久化，仅内存传递
  };

  factory GradesResult.fromMap(Map<String, dynamic> m) => GradesResult(
    grades:
        (m['grades'] as List<dynamic>?)
            ?.map((e) => Grade.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [],
    // 缓存的旧数据没有 diff 信息
    newCourseNames: null,
    removedCourseNames: null,
  );
}
