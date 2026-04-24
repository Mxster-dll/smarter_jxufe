import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';

part 'credit_hour.freezed.dart';
part 'credit_hour.g.dart';

/// ### 学时信息
@HiveType(typeId: kCreditHourTypeId)
@freezed
class CreditHour with _$CreditHour {
  const factory CreditHour({
    @HiveField(0) required int total, // 总学时
    @HiveField(1) required int lecture, // 讲授学时
    @HiveField(2) @Default(0) int lab, // 实验学时
    @HiveField(3) @Default(0) int practice, // 实践学时
    @HiveField(4) @Default(0) int other, // 其它学时
    @HiveField(5) required double weekly, // 周学时
  }) = _CreditHour;
}
