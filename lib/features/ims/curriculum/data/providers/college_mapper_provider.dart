import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/college_mapper.dart';

part 'college_mapper_provider.g.dart';

@riverpod
CollegeMapper collegeMapper(CollegeMapperRef ref) => CollegeMapper();
