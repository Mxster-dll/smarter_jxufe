import 'package:smarter_jxufe/core/errors/failures.dart';

class NoMatchFailure extends Failure {
  NoMatchFailure([super.message]);

  @override
  String toString() => 'NoMatchFailure: $message';
}
