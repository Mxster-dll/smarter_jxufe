import 'package:hive_flutter/hive_flutter.dart';

part 'assessment_method.g.dart';

/// 考核方式
@HiveType(typeId: 4, adapterName: 'AssessmentMethodAdapter')
enum AssessmentMethod {
  @HiveField(0)
  exam,
  @HiveField(1)
  coursework,
  @HiveField(2)
  unknown;

  String get name => switch (this) {
    exam => '考试',
    coursework => '考查',
    unknown => '未知',
  };

  factory AssessmentMethod.parse(String source) => switch (source) {
    '考试' => exam,
    '考查' => coursework,
    _ => unknown,
  };
}
