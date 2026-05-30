import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/anti_corruption/college_mapper.dart';

part 'college_mapper_provider.g.dart';

@Riverpod(keepAlive: true)
CollegeMapper collegeMapper(CollegeMapperRef ref) => CollegeMapper();
