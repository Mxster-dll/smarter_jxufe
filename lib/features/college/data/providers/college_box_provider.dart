import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';

part 'college_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<College>> collegeBox(CollegeBoxRef ref) =>
    Hive.openBox<College>(collegeBoxName);
