import 'package:smarter_jxufe/core/errors/failures.dart';

class MultipleMatchFailure extends Failure {
  MultipleMatchFailure([super.message]);

  @override
  String toString() => 'MultipleMatchFailure: $message';
}
