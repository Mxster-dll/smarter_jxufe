import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/data/ims/course/models/Course.dart';

part 'Curriculum.freezed.dart';
part 'Curriculum.g.dart';

@HiveType(typeId: 1, adapterName: 'CurriculumAdapter')
@freezed
class Curriculum with _$Curriculum {
  const factory Curriculum({
    @HiveField(0) required int year,
    @HiveField(1) required String collegeCode,
    @HiveField(2) required String majorCode,
    @HiveField(3) required List<Course> courses,
    @HiveField(4) DateTime? lastUpdated,
  }) = _Curriculum;

  factory Curriculum.fromJson(Map<String, dynamic> json) =>
      _$CurriculumFromJson(json);
}
