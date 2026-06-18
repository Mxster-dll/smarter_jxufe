class Account {
  final String cardNumber;
  final String password;
  final String displayName;

  const Account({
    required this.cardNumber,
    required this.password,
    this.displayName = '',
  });
}
