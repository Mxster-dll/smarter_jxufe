import 'package:hive_flutter/hive_flutter.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

part 'curriculum.freezed.dart';
part 'curriculum.g.dart';

@freezed
@HiveType(typeId: 1, adapterName: 'CurriculumAdapter')
class Curriculum with _$Curriculum {
  const factory Curriculum({
    @HiveField(0) required int year,
    @HiveField(1) required College college,
    @HiveField(2) required Major major,
    @HiveField(3) required List<Course> courses,
    @HiveField(4) DateTime? lastUpdated,
  }) = _Curriculum;
}
