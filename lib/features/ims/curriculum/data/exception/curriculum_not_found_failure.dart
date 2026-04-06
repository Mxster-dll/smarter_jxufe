import 'package:smarter_jxufe/core/errors/failures.dart';

class CurriculumNotFoundFailure extends Failure {
  CurriculumNotFoundFailure([super.message]);

  @override
  String toString() => 'CurriculumNotFoundFailure: $message';
}
