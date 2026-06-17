import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'student_info_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<String>> studentInfoBox(StudentInfoBoxRef ref) =>
    Hive.openBox<String>('studentInfo');
