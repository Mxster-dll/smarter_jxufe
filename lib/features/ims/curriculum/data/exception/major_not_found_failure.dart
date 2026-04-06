import 'package:smarter_jxufe/core/errors/failures.dart';

class MajorNotFoundFailure extends Failure {
  MajorNotFoundFailure([super.message]);

  @override
  String toString() => 'MajorNotFoundFailure: $message';
}
