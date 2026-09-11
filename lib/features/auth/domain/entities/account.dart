class Account {
  final String cardNumber;
  final String password;
  final String displayName;

  /// 本地头像文件名（应用私有目录 `avatars/` 下，如 `0000000.png`）。
  ///
  /// 空串 = 未设置头像 → 界面回退「姓名首字 → 通用图标」。
  /// 只存文件名（不存绝对路径）：目录可随平台变化，也不怕用户挪动原图。
  final String avatar;

  const Account({
    required this.cardNumber,
    required this.password,
    this.displayName = '',
    this.avatar = '',
  });

  Account copyWith({String? displayName, String? avatar}) => Account(
    cardNumber: cardNumber,
    password: password,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
  );
}
