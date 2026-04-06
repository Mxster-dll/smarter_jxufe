import 'package:freezed_annotation/freezed_annotation.dart';

part 'curriculum_major.freezed.dart';

@freezed
class CurriculumMajor with _$CurriculumMajor {
  const factory CurriculumMajor({required String code, required String name}) =
      _CurriculumMajor;
}
