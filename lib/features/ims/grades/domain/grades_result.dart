import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade_summary.dart';

class GradesResult {
  final List<Grade> grades;
  final List<GradeSummary> summaries;

  const GradesResult({required this.grades, required this.summaries});
}
