import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';

part 'curriculum_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<Curriculum>> curriculumBox(CurriculumBoxRef ref) =>
    Hive.openBox<Curriculum>(curriculumBoxName);
