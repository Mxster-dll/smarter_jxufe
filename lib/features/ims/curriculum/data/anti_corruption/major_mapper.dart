import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/api_models/api_major.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_major.dart';

class MajorMapper {
  // 解析形如 "[0701001]信息与计算科学" 的字符串
  static (String, String) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[([A-Za-z0-9]+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      final unknownCode = match.group(1)!;
      final name = match.group(2)!;
      return (unknownCode, name);
    }

    return ('', raw);
  }

  CurriculumMajor fromApi(ApiMajor api) {
    final (unknownCode, name) = extractCodeAndName(api.name);
    return CurriculumMajor(code: api.code, name: name);
  }

  List<CurriculumMajor> fromApiList(List<ApiMajor> apiList) {
    return apiList.map(fromApi).toList();
  }
}
