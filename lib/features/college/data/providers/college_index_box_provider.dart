import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'college_index_box_provider.g.dart';

@riverpod
Box<Set<String>> collegeIndexBox(CollegeIndexBoxRef ref) =>
    Hive.box<Set<String>>('collegeIndexes');
