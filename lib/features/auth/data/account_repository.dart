import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/account_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

class AccountRepository {
  final AccountLocalDataSource _localDataSource;

  AccountRepository(this._localDataSource);

  /// 获取本地存储的账号，无数据时返回 null
  Future<Either<Failure, Account?>> getAccount() async {
    try {
      final account = await _localDataSource.getAccount();
      return Right(account);
    } catch (e) {
      return Left(UnknownFailure('读取账号失败: $e'));
    }
  }

  /// 加密保存账号
  Future<Either<Failure, void>> saveAccount(Account account) async {
    try {
      await _localDataSource.saveAccount(account);
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('保存账号失败: $e'));
    }
  }

  /// 删除存储的账号
  Future<Either<Failure, void>> deleteAccount() async {
    try {
      await _localDataSource.deleteAccount();
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('删除账号失败: $e'));
    }
  }
}
