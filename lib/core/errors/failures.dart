/// `Either<Failure, T>` 的**返回值**侧（dartz 风格，失败不抛、装进 `Left`）。
///
/// ⚠ 与 `app_exception.dart` 的 `AppException` **刻意并存，不要互相转换**（见 §33）：
/// 本文件 = 「不抛的那条路」（repository 的 `Either` 契约），`AppException` = 「抛出去的
/// 那条路」（数据源遇到协议 / 会话问题的异常）。两者服务不同的调用约定，合并只会让
/// 13 个用 `Either` 的仓库被迫改成 try/catch。
///
/// 收敛（2026-09-20 · 架构审查后）：此前 8 个子类**各自重复声明一遍
/// `final String? message;`**（把基类字段整个遮蔽掉，基类那个永远为 null）——
/// 现在只有基类持有字段，子类一律用 `super.message` 转发，并全部转为 `const`。
library;

abstract class Failure {
  const Failure([this.message]);

  final String? message;
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message]);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message]);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message]);
}

class ParseFailure extends Failure {
  const ParseFailure([super.message]);
}

class MappingFailure extends Failure {
  const MappingFailure([super.message]);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message]);
}

/// 账号或密码错误
class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure([super.message]);
}
