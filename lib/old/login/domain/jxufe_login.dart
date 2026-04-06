// features/login/domain/jxufe_login.dart

import '../data/repositories/login_repository.dart';

class JxufeLogin {
  final String account;
  final LoginRepository _loginRepository;

  JxufeLogin({required this.account, required LoginRepository loginRepository})
    : _loginRepository = loginRepository;

  String? get gid => _loginRepository.gid;

  Future<void> doLogin() async {
    final result = await _loginRepository.login('', '');
    result.fold(
      (failure) => print('登录失败: $failure'),
      (jsessionId) => print('登录成功: $jsessionId'),
    );
  }
}
