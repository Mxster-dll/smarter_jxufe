import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'major_index_box_provider.g.dart';

@riverpod
Box<List<String>> majorIndexBox(MajorIndexBoxRef ref) =>
    Hive.box<List<String>>('majorIndexes');
