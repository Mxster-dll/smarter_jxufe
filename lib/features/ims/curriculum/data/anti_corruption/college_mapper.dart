import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/api_models/api_college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';

class CollegeMapper {
  // 解析形如 "[051]经济学院" 的字符串
  static (String, String) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[(\d+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      final unknownCode = match.group(1)!;
      final name = match.group(2)!;
      return (unknownCode, name);
    }

    return ('', raw);
  }

  CurriculumCollege fromApi(ApiCollege api) {
    final (unknownCode, name) = extractCodeAndName(api.name);
    return CurriculumCollege(code: api.code, name: name);
  }

  List<CurriculumCollege> fromApiList(List<ApiCollege> apiList) {
    return apiList.map(fromApi).toList();
  }
}
