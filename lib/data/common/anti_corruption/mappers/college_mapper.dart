import 'package:smarter_jxufe/data/common/models/college.dart';

class CollegeMapper {
  College fromJson(Map<String, String> json) =>
      College(json['code'] ?? '', json['name'] ?? '');

  List<College> fromJsonList(List<Map<String, String>> jsonList) =>
      jsonList.map((json) => fromJson(json)).toList();
}
