// import 'package:hive_flutter/hive_flutter.dart';

// import 'package:smarter_jxufe/core/function_type.dart';
// import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';

// // TODO 把 College 和 Major 仓库也使用年份架构
// class CourseLocalDataSource {
//   final Box<Course> _box;

//   CourseLocalDataSource(this._box);

//   String _indexKey(int year, String collegeId, String code) =>
//       '${year}_${collegeId}_$code';

//   Future<void> saveCourse(
//     Course course, {
//     required int year,
//     required String collegeId,
//   }) => _box.put(_indexKey(year, collegeId, course.code), course);

//   Future<void> saveCourseList(
//     List<Course> courses, {
//     required int year,
//     required String collegeId,
//   }) => Future.wait(
//     courses.map((e) => saveCourse(e, year: year, collegeId: collegeId)),
//   );

//   bool contains(String key) => _box.containsKey(key);

//   Course? getCourseByUuid(String uuid) => _box.get(uuid);
//   List<Course> getCourseList() => _box.values.toList();

//   List<Course> findCourseKnownAs(String name) =>
//       _box.values.where((c) => c.isKnownAs(name)).toList();

//   List<String>? getCourseUuidsIn(int year, String collegeId) =>
//       _indexBox.get(_indexKey(year, collegeId));

//   /// 注意区分空列表与 null，前者表示该条件下无专业，后者表示本地无缓存
//   List<Course>? getCourseListIn(
//     FunctionType function, {
//     required int year,
//     required String collegeId,
//   }) => getCourseUuidsIn(year, collegeId)
//       ?.map(getCourseByUuid)
//       .whereType<Course>()
//       .where((e) => e.functionIdIn.containsKey(function))
//       .toList();

//   // Future<void> deleteCourse(String uuid) => _box.delete(uuid);

//   Future<void> clearAll() async {
//     await _box.clear();
//     await _indexBox.clear();
//   }
// }
