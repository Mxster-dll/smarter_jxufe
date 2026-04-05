import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';

part 'college_box_provider.g.dart';

@riverpod
Box<CurriculumCollege> collegeBox(CollegeBoxRef ref) =>
    Hive.box<CurriculumCollege>('curriculum_colleges');
