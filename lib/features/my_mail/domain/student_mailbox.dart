/// 学校学生邮箱（智慧江财「我的邮箱」）。
///
/// 门户接口 `GET /platForm/api/wx/email/getPwd?username=<GUID>` 返回
/// `{"email":"2000000000@stu.jxufe.edu.cn","pwd":"…"}`：**账号 = 学号 @ stu.jxufe.edu.cn**，
/// `pwd` 是学校邮件系统下发的初始密码（本账号实测 10 位）。
///
/// 小程序侧「我的邮箱」本体是跳独立小程序（appid `wx0bc2c17d023b213d`），App 侧
/// 只复刻门户能拿到的账号信息（用户 2026-09-16 裁定：只要「查看账号 / 初始密码 /
/// 复制邮箱 / 复制初始密码」四项，不做未读数与改绑）。
class StudentMailbox {
  const StudentMailbox({required this.email, required this.password});

  /// 邮箱地址（如 `2000000000@stu.jxufe.edu.cn`）。
  final String email;

  /// 初始密码（学校邮件系统下发；用户自行改过则这里仍是初始值）。
  final String password;

  static const StudentMailbox empty = StudentMailbox(email: '', password: '');

  bool get isEmpty => email.isEmpty && password.isEmpty;

  /// 掩码后的密码（星号数 = 密码长度，与小程序「邮箱密码」页同款）。
  String get maskedPassword => myMailMaskPassword(password);

  /// 容错解析：缺字段一律取空串，脏数据（String/num 混存）不抛异常。
  static StudentMailbox fromJson(Map<dynamic, dynamic> json) => StudentMailbox(
    email: (json['email'] ?? '').toString().trim(),
    password: (json['pwd'] ?? json['password'] ?? '').toString().trim(),
  );

  @override
  String toString() => 'StudentMailbox($email)';
}

/// 密码掩码：`'*' * length`（小程序 `getXing(pwd.length)` 的同款口径）。
String myMailMaskPassword(String password) => '*' * password.length;

/// 学生邮箱地址约定：`<学号>@stu.jxufe.edu.cn`（实测 2000000000 → 2000000000@stu.jxufe.edu.cn）。
///
/// 学号取不到（null / 空）时返回 null —— 调用方据此决定是否预填。
String? myMailStudentAddress(String? serialNo) {
  final s = (serialNo ?? '').trim();
  if (s.isEmpty) return null;
  return '$s@stu.jxufe.edu.cn';
}
