import 'package:hive_flutter/hive_flutter.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';

part 'curriculum.freezed.dart';
part 'curriculum.g.dart';

@freezed
@HiveType(typeId: kCurriculumTypeId)
class Curriculum with _$Curriculum {
  const factory Curriculum({
    @HiveField(0) required int year,
    @HiveField(1) required String collegeName,
    @HiveField(2) required String majorName,
    @HiveField(3) required List<Course> courses,
    @HiveField(4) DateTime? lastUpdated,
  }) = _Curriculum;
}
