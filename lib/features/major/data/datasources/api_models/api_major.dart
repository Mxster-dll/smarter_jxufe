import 'package:freezed_annotation/freezed_annotation.dart';

part 'api_major.freezed.dart';
part 'api_major.g.dart';

@freezed
class ApiMajor with _$ApiMajor {
  const factory ApiMajor({required String code, required String name}) =
      _ApiMajor;

  factory ApiMajor.fromJson(Map<String, dynamic> json) =>
      _$ApiMajorFromJson(json);

  static List<ApiMajor> fromJsonList(List<dynamic> jsonList) => jsonList
      .map((e) => ApiMajor.fromJson(e as Map<String, dynamic>))
      .toList();
}
