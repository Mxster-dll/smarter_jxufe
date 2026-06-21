import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

class AccountLocalDataSource {
  final Box<String> _box;

  static const _keyAccounts = 'accounts';
  static const _keyCurrentIndex = 'currentAccountIndex';

  AccountLocalDataSource(this._box) {
    _migrateIfNeeded();
  }

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

  Future<void> saveAccount(Account account) async {
    final accounts = getAccounts();
    final exists = accounts.any((a) => a.cardNumber == account.cardNumber);
    if (exists) return;
    accounts.add(account);
    await _saveList(accounts);
  }

  Future<void> deleteAccount(String cardNumber) async {
    final accounts = getAccounts();
    accounts.removeWhere((a) => a.cardNumber == cardNumber);
    await _saveList(accounts);
  }

  int? getCurrentIndex() {
    final raw = _box.get(_keyCurrentIndex);
    return raw != null ? int.tryParse(raw) : null;
  }

  Future<void> setCurrentIndex(int? index) async {
    if (index == null) {
      await _box.delete(_keyCurrentIndex);
    } else {
      await _box.put(_keyCurrentIndex, index.toString());
    }
  }

  Account? getCurrentAccount() {
    final index = getCurrentIndex();
    if (index == null) return null;
    final accounts = getAccounts();
    if (index < 0 || index >= accounts.length) return null;
    return accounts[index];
  }

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

  void _migrateIfNeeded() {
    final oldUsername = _box.get('account_username');
    final oldPassword = _box.get('account_password');
    if (oldUsername == null || oldPassword == null) return;

    final existing = getAccounts();
    if (existing.any((a) => a.cardNumber == oldUsername)) return;

    existing.add(Account(cardNumber: oldUsername, password: oldPassword));
    _saveList(existing);

    _box.delete('account_username');
    _box.delete('account_password');
  }
}
