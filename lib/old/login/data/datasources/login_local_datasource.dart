import 'package:get_storage/get_storage.dart';

class LoginLocalDataSource {
  final String account;
  final GetStorage _box;

  LoginLocalDataSource(this.account) : _box = GetStorage('Login_$account');

  static const String _keyLastUsername = 'last_username';

  Future<void> saveLastUsername(String username) =>
      _box.write(_keyLastUsername, username);
  String? getLastUsername() => _box.read<String>(_keyLastUsername);
  Future<void> clearLastUsername() => _box.remove(_keyLastUsername);
}
