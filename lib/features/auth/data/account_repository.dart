import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/account_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

class AccountRepository {
  final AccountLocalDataSource _localDataSource;

  AccountRepository(this._localDataSource);

  /// 获取全部账户列表。
  Either<Failure, List<Account>> getAccounts() {
    try {
      return Right(_localDataSource.getAccounts());
    } catch (e) {
      return Left(UnknownFailure('读取账户失败: $e'));
    }
  }

  /// 获取当前登录的账户。
  Either<Failure, Account?> getCurrentAccount() {
    try {
      return Right(_localDataSource.getCurrentAccount());
    } catch (e) {
      return Left(UnknownFailure('读取当前账户失败: $e'));
    }
  }

  /// 保存账户并自动设为当前登录账户。
  Future<Either<Failure, void>> saveAccount(Account account) async {
    try {
      await _localDataSource.saveAccount(account);
      // 自动设为当前账户
      final accounts = _localDataSource.getAccounts();
      final idx = accounts.indexWhere(
        (a) => a.cardNumber == account.cardNumber,
      );
      if (idx != -1) {
        await _localDataSource.setCurrentIndex(idx);
      }
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('保存账户失败: $e'));
    }
  }

  /// 设置当前登录账户。
  Future<Either<Failure, void>> setCurrentAccount(int index) async {
    try {
      await _localDataSource.setCurrentIndex(index);
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('切换账户失败: $e'));
    }
  }

  /// 清除当前账户标记（登录失败时调用，避免错误显示"已登录"状态）。
  Future<Either<Failure, void>> clearCurrentAccount() async {
    try {
      await _localDataSource.clearCurrentAccount();
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('清除当前账户失败: $e'));
    }
  }

  /// 删除账户。
  Future<Either<Failure, void>> deleteAccount(String cardNumber) async {
    try {
      await _localDataSource.deleteAccount(cardNumber);
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('删除账户失败: $e'));
    }
  }

  /// 更新账户的显示名称。
  Future<Either<Failure, void>> updateDisplayName(
    String cardNumber,
    String displayName,
  ) async {
    try {
      await _localDataSource.updateDisplayName(cardNumber, displayName);
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('更新显示名称失败: $e'));
    }
  }
}
