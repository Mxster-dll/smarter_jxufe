import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

part 'college.freezed.dart';
part 'college.g.dart';

@Freezed(toStringOverride: false)
@HiveType(typeId: 7, adapterName: 'CollegeAdapter')
class College with _$College {
  const factory College(@HiveField(0) String code, @HiveField(1) String name) =
      _College;

  factory College.fromJson(Map<String, dynamic> json) =>
      _$CollegeFromJson(json);

  @override
  String toString() => '$name ($code)';
}
