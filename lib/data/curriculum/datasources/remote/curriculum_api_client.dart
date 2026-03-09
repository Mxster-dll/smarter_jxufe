// import 'package:dio/dio.dart';

// // import;

// class CurriculumApiClient {
//   final Dio _dio;

//   CurriculumApiClient(this._dio);

//   /// 获取学院列表（原始 JSON）
//   Future<List<ApiCollege>> getCollegeList() async {
//     final response = await _dio.post(
//       '/frame/droplist/getDropLists.action',
//       data: {
//         'comboBoxName': 'MsYXB',
//         'paramValue': '',
//         'isYXB': 0, // 院系部
//         'isCDDW': 0,
//         'isXQ': 0, // 学期？
//         'isDJKSLB': 0,
//         'isZY': 0, // 专业？
//       },
//       options: Options(
//         headers: {
//           'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
//           'Referer':
//               'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
//         },
//       ),
//     );

//     return List<Map<String, String>>.from(response.data);
//   }

//   /// 获取专业列表（原始 JSON）
//   Future<List<ApiMajor>> getMajorList(int year, String dwh) async {
//     final response = await _dio.post(
//       '/frame/droplist/getDropLists.action',
//       data: {
//         'comboBoxName': 'MsYXB_Specialty',
//         'paramValue': 'nj=$year&dwh=$dwh',
//         'isYXB': 0,
//         'isCDDW': 0,
//         'isSXJD': 0,
//         'isXQ': 0,
//       },
//       options: Options(
//         headers: {
//           'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
//           'Referer':
//               'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
//         },
//       ),
//     );

//     return List<Map<String, String>>.from(response.data);
//   }

//   Future<String> getRawCurriculum(int year, String selYxb, String selZy) async {
//     final response = await _dio.post(
//       '/taglib/DataTable.jsp?tableId=2508',
//       data: {
//         'count': '1',
//         'initQry': '0',
//         'nj_': year,
//         'sel_yxb': selYxb,
//         'sel_zy': selZy,
//         'fzyxs': 'zx',
//         'menucode_current': 'S20101',
//       },
//       options: Options(
//         headers: {
//           'Content-Type': 'application/x-www-form-urlencoded',
//           'Referer':
//               'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
//         },
//       ),
//     );

//     return response.data as String;
//   }
// }
