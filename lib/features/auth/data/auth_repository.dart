import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/auth/domain/models/user.dart';

class AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepository(this.remoteDataSource);

  /// 登录流程：检测 MFA → 提交登录 → 获取 TGC → 构造 User
  Future<User> login(String username, String password) async {
    final fpVisitorId = _generateFpVisitorId();

    // 1. 检测 MFA，获取 state
    final mfaState = await remoteDataSource.detectMfa(
      username: username,
      password: password,
      fpVisitorId: fpVisitorId,
    );

    // 2. 提交登录，获取 TGC
    final tgc = await remoteDataSource.login(
      username: username,
      password: password,
      fpVisitorId: fpVisitorId,
      mfaState: mfaState,
    );

    // 3. 可选的获取用户详细信息（例如 /api/user/info）
    // final name = await _fetchUserName(tgc);
    const name = '待获取'; // 临时占位

    return User(token: tgc, name: name);
  }

  String _generateFpVisitorId() {
    return "9d832cfb4202ae54caf83ba4e2e1d8a2";
  }
}
