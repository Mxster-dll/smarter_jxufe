import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive/hive.dart';

part 'CreditHour.freezed.dart';
part 'CreditHour.g.dart';

/// 学时信息
@HiveType(typeId: 6, adapterName: 'CreditHourAdapter')
@freezed
class CreditHour with _$CreditHour {
  const factory CreditHour({
    @HiveField(0) required int total,
    @HiveField(1) required int lecture,
    @HiveField(2) required int lab,
    @HiveField(3) required int practice,
    @HiveField(4) required int other,
    @HiveField(5) required double weekly,
  }) = _CreditHour;

  factory CreditHour.fromJson(Map<String, dynamic> json) =>
      _$CreditHourFromJson(json);
}
