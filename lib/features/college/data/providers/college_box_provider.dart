import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/domain/college.dart';

part 'college_box_provider.g.dart';

@riverpod
Box<College> collegeBox(CollegeBoxRef ref) => Hive.box<College>('colleges');
