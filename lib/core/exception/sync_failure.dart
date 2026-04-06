import 'package:smarter_jxufe/core/errors/failures.dart';

class SyncFailure extends Failure {
  SyncFailure([super.message]);

  @override
  String toString() => 'SyncFailure: $message';
}
