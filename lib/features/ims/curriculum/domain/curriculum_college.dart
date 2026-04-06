import 'package:freezed_annotation/freezed_annotation.dart';

part 'curriculum_college.freezed.dart';

@freezed
class CurriculumCollege with _$CurriculumCollege {
  const factory CurriculumCollege({
    required String code,
    required String name,
  }) = _CurriculumCollege;
}
