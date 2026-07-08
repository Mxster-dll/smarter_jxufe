import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

/// 多账户本地存储（JSON 序列化）。
class AccountLocalDataSource {
  final Box<String> _box;

  static const _keyAccounts = 'accounts';
  static const _keyCurrentIndex = 'currentAccountIndex';

  AccountLocalDataSource(this._box) {
    _migrateIfNeeded();
  }

  /// 获取全部账户列表。
  List<Account> getAccounts() {
    final raw = _box.get(_keyAccounts);
    if (raw == null) return [];
    final list = json.decode(raw) as List<dynamic>;
    return list
        .map(
          (e) => Account(
            cardNumber: e['cardNumber'] as String,
            password: e['password'] as String,
            displayName: e['displayName'] as String? ?? '',
          ),
        )
        .toList();
  }

  /// 保存账户（去重）。
  Future<void> saveAccount(Account account) async {
    final accounts = getAccounts();
    final exists = accounts.any((a) => a.cardNumber == account.cardNumber);
    if (exists) return;
    accounts.add(account);
    await _saveList(accounts);
  }

  /// 删除指定账户。
  Future<void> deleteAccount(String cardNumber) async {
    final accounts = getAccounts();
    accounts.removeWhere((a) => a.cardNumber == cardNumber);
    await _saveList(accounts);
  }

  /// 获取当前登录账户索引。
  int? getCurrentIndex() {
    final raw = _box.get(_keyCurrentIndex);
    return raw != null ? int.tryParse(raw) : null;
  }

  /// 设置当前登录账户索引。
  Future<void> setCurrentIndex(int? index) async {
    if (index == null) {
      await _box.delete(_keyCurrentIndex);
    } else {
      await _box.put(_keyCurrentIndex, index.toString());
    }
  }

  /// 获取当前登录的账户。
  Account? getCurrentAccount() {
    final index = getCurrentIndex();
    if (index == null) return null;
    final accounts = getAccounts();
    if (index < 0 || index >= accounts.length) return null;
    return accounts[index];
  }

  /// 清除当前账户标记（不会删除账户数据本身）。
  Future<void> clearCurrentAccount() async {
    await _box.delete(_keyCurrentIndex);
  }

  /// 清空所有账户。
  Future<void> clearAll() async {
    await _box.delete(_keyAccounts);
    await _box.delete(_keyCurrentIndex);
  }

  Future<void> _saveList(List<Account> accounts) async {
    final data = accounts
        .map(
          (a) => {
            'cardNumber': a.cardNumber,
            'password': a.password,
            'displayName': a.displayName,
          },
        )
        .toList();
    await _box.put(_keyAccounts, json.encode(data));
  }

  /// 更新指定账户的显示名称。
  Future<void> updateDisplayName(String cardNumber, String displayName) async {
    final accounts = getAccounts();
    final idx = accounts.indexWhere((a) => a.cardNumber == cardNumber);
    if (idx == -1) return;
    accounts[idx] = Account(
      cardNumber: accounts[idx].cardNumber,
      password: accounts[idx].password,
      displayName: displayName,
    );
    await _saveList(accounts);
  }

  /// 从旧格式（单账号 key-value）迁移到新格式（JSON 列表）。
  void _migrateIfNeeded() {
    final oldUsername = _box.get('account_username');
    final oldPassword = _box.get('account_password');
    if (oldUsername == null || oldPassword == null) return;

    // 检查新格式是否已有数据
    final existing = getAccounts();
    if (existing.any((a) => a.cardNumber == oldUsername)) return;

    existing.add(Account(cardNumber: oldUsername, password: oldPassword));
    _saveList(existing);

    // 删除旧 key
    _box.delete('account_username');
    _box.delete('account_password');
  }
}
