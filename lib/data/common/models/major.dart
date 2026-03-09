import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

part 'major.freezed.dart';
part 'major.g.dart';

@Freezed(toStringOverride: false)
@HiveType(typeId: 8, adapterName: 'MajorAdapter')
class Major with _$Major {
  const factory Major(@HiveField(0) String code, @HiveField(1) String name) =
      _Major;

  factory Major.fromJson(Map<String, dynamic> json) => _$MajorFromJson(json);

  @override
  String toString() => '$name ($code)';
}
