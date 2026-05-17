import 'package:smarter_jxufe/core/extension/iterable_extensions.dart';
import 'package:smarter_jxufe/features/major/data/datasources/api_models/api_major.dart';

class MajorFilter {
  List<ApiMajor> distinctByName(List<ApiMajor> majors) =>
      majors.distinctBy((major) => major.name).toList();
}
