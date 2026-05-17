import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/anti_corruption/college_filter.dart';

part 'college_filter_provider.g.dart';

@riverpod
CollegeFilter collegeFilter(CollegeFilterRef ref) => CollegeFilter();
