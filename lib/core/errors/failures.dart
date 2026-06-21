abstract class Failure {
  final String? message;

  Failure([this.message]);
}

class UnknownFailure extends Failure {
  final String? message;
  UnknownFailure(this.message);
}

class NetworkFailure extends Failure {
  final String? message;
  NetworkFailure(this.message);
}

class ServerFailure extends Failure {
  final String? message;
  ServerFailure(this.message);
}

class CacheFailure extends Failure {
  final String? message;
  CacheFailure(this.message);
}

class ParseFailure extends Failure {
  final String? message;
  ParseFailure(this.message);
}

class MappingFailure extends Failure {
  final String? message;
  MappingFailure(this.message);
}

class NotFoundFailure extends Failure {
  final String? message;
  NotFoundFailure(this.message);
}

class InvalidCredentialsFailure extends Failure {
  final String? message;
  InvalidCredentialsFailure(this.message);
}
