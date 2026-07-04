import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'grades_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<String>> gradesBox(GradesBoxRef ref) =>
    Hive.openBox<String>('gradesCache');
