class LoginState {
  final String account;
  final String password;
  final bool isLoading;
  final String? errorMessage;
  final bool passwordVisible;
  final bool loginSuccess;

  const LoginState({
    this.account = '',
    this.password = '',
    this.isLoading = false,
    this.errorMessage,
    this.passwordVisible = false,
    this.loginSuccess = false,
  });

  LoginState copyWith({
    String? account,
    String? password,
    bool? isLoading,
    String? errorMessage,
    bool? passwordVisible,
    bool? loginSuccess,
  }) {
    return LoginState(
      account: account ?? this.account,
      password: password ?? this.password,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      passwordVisible: passwordVisible ?? this.passwordVisible,
      loginSuccess: loginSuccess ?? this.loginSuccess,
    );
  }
}
