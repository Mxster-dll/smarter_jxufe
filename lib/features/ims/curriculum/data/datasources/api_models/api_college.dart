import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_college.freezed.dart';
part 'api_college.g.dart';

@freezed
class ApiCollege with _$ApiCollege {
  const factory ApiCollege({required String code, required String name}) =
      _ApiCollege;

  factory ApiCollege.fromJson(Map<String, dynamic> json) =>
      _$ApiCollegeFromJson(json);
}
