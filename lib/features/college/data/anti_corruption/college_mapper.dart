import 'package:smarter_jxufe/features/college/data/datasources/api_models/api_college.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeMapper {
  // 解析形如 "[051]经济学院" 的字符串
  static (String, String) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[(\d+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      final id = match.group(1)!;
      final name = match.group(2)!;
      return (id, name);
    }

    return ('', raw);
  }

  College fromApi(ApiCollege api) {
    final (id, name) = extractCodeAndName(api.name);
    return College(id, name, api.code);
  }

  List<College> fromApiList(List<ApiCollege> apiList) {
    return apiList.map(fromApi).toList();
  }
}
