import 'package:smarter_jxufe/data/common/models/major.dart';

class MajorMapper {
  Major fromJson(Map<String, String> json) =>
      Major(json['code'] ?? '', json['name'] ?? '');

  List<Major> fromJsonList(List<Map<String, String>> jsonList) =>
      jsonList.map((json) => fromJson(json)).toList();
}
