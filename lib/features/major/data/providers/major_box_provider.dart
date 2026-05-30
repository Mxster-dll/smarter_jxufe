import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

part 'major_box_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<Major>> majorBox(MajorBoxRef ref) =>
    Hive.openBox<Major>(majorBoxName);
