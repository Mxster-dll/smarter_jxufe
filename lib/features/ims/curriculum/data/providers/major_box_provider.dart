import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_major.dart';

part 'major_box_provider.g.dart';

@riverpod
Box<CurriculumMajor> majorBox(MajorBoxRef ref) =>
    Hive.box<CurriculumMajor>('curriculum_majors');
