import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

class GradesResult {
  final List<Grade> grades;

  const GradesResult({required this.grades});

  Map<String, dynamic> toMap() => {
    'grades': grades.map((g) => g.toMap()).toList(),
  };

  factory GradesResult.fromMap(Map<String, dynamic> m) => GradesResult(
    grades:
        (m['grades'] as List<dynamic>?)
            ?.map((e) => Grade.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
