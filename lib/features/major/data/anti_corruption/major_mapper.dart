import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/major/data/datasources/api_models/api_major.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorMapper {
  static (String, String) extractCodeAndName(String raw) {
    final regex = RegExp(r'^\[([A-Za-z0-9]+)\](.*)$');
    final match = regex.firstMatch(raw);
    if (match != null) {
      final id = match.group(1)!;
      final name = match.group(2)!;
      return (id, name);
    }

    return ('', raw);
  }

  Major fromApi(ApiMajor api, {required int year, required College college}) {
    final (id, name) = extractCodeAndName(api.name);
    return Major(
      id: id,
      name: name,
      code: api.code,
      year: year,
      collegeName: college.name,
    );
  }

  List<Major> fromApiList(
    List<ApiMajor> apiList, {
    required int year,
    required College college,
  }) {
    return apiList
        .map((e) => fromApi(e, year: year, college: college))
        .toList();
  }
}
