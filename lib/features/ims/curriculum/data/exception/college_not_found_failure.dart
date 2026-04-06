import 'package:smarter_jxufe/core/errors/failures.dart';

class CollegeNotFoundFailure extends Failure {
  CollegeNotFoundFailure([super.message]);

  @override
  String toString() => 'CollegeNotFoundFailure: $message';
}
