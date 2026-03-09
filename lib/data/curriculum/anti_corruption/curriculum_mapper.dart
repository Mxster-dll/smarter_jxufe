// // lib/data/anti_corruption/curriculum_mapper.dart

// import 'package:smarter_jxufe/data/curriculum/models/Curriculum.dart';
// import 'package:smarter_jxufe/data/curriculum/datasources/remote/apiModels/apiCurriculum.dart';

// class CurriculumMapper {
//   Curriculum fromApi(ApiCurriculum api) {
//     // 处理可能缺失的时间字段
//     DateTime? updated;
//     if (api.updateTime != null) {
//       updated = DateTime.tryParse(api.updateTime!);
//     }

//     // 转换课程组
//     final groups = api.groups.map((apiGroup) {
//       final courses = apiGroup.courses.map((apiCourse) {
//         return Course(
//           code: apiCourse.code,
//           name: apiCourse.name,
//           credits: apiCourse.credits,
//           category: apiCourse.category,
//           teacher: null, // 老接口可能没有教师信息，这里可以留空或从其他地方补充
//         );
//       }).toList();

//       return CourseGroup(
//         name: apiGroup.name,
//         requiredCredits: apiGroup.requiredCredits,
//         courses: courses,
//       );
//     }).toList();

//     return Curriculum(
//       id: api.id,
//       name: api.name,
//       totalCredits: api.totalCredits,
//       groups: groups,
//       lastUpdated: updated,
//     );
//   }
// }
