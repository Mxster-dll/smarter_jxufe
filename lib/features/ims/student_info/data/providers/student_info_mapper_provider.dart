import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_mapper.dart';

part 'student_info_mapper_provider.g.dart';

@Riverpod(keepAlive: true)
StudentInfoMapper studentInfoMapper(StudentInfoMapperRef ref) =>
    StudentInfoMapper();
