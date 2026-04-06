import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'credit_hour.freezed.dart';
part 'credit_hour.g.dart';

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
