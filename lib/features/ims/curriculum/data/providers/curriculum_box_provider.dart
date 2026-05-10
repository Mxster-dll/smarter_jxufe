import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';

part 'curriculum_box_provider.g.dart';

@riverpod
Future<Box<Curriculum>> curriculumBox(CurriculumBoxRef ref) =>
    Hive.openBox<Curriculum>('curriculums');
