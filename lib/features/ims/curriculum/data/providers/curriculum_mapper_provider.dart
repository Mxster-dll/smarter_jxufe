import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';

part 'curriculum_mapper_provider.g.dart';

@Riverpod(keepAlive: true)
CurriculumMapper curriculumMapper(CurriculumMapperRef ref) =>
    CurriculumMapper();
