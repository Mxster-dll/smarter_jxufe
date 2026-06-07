import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

class AccountLocalDataSource {
  final Box<String> _box;

  static const _keyUsername = 'account_username';
  static const _keyPassword = 'account_password';

  AccountLocalDataSource(this._box);

  Future<void> saveAccount(Account account) async {
    await _box.put(_keyUsername, account.username);
    await _box.put(_keyPassword, account.password);
  }

  Future<Account?> getAccount() async {
    final username = _box.get(_keyUsername);
    final password = _box.get(_keyPassword);
    if (username == null || password == null) return null;
    return Account(username: username, password: password);
  }

  Future<void> deleteAccount() async {
    await _box.delete(_keyUsername);
    await _box.delete(_keyPassword);
  }
}
