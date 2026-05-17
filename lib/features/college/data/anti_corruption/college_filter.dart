import 'package:smarter_jxufe/core/extension/iterable_extensions.dart';
import 'package:smarter_jxufe/features/college/data/datasources/api_models/api_college.dart';

class CollegeFilter {
  List<ApiCollege> distinctByName(List<ApiCollege> colleges) =>
      colleges.distinctBy((college) => college.name).toList();
}
