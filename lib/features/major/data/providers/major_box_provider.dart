import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/major/domain/major.dart';

part 'major_box_provider.g.dart';

@riverpod
Box<Major> majorBox(MajorBoxRef ref) => Hive.box<Major>('majors');
