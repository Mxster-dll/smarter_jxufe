import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';

/// IMS 会话的**门面**：真正的会话状态与换票逻辑全在全局唯一的 [ImsSession]
/// 里（见 `ims_session.dart`），本类只做 `Either` 风格适配，供既有的
/// 成绩 / 课表 / 学籍 / 培养方案 / 毕业学分 / 加权 等仓库调用。
///
/// 历史包袱说明：这里以前自己持有 Dio 与本地数据源，每个调用方各自
/// 「取票 / 换票」，于是每次进入 IMS 功能都要重走一遍 CAS 换票。现在
/// **只有 [ImsSession] 一个实例**，本类不再持有任何状态。
class ImsAuthRepository {
  ImsAuthRepository(this._session);

  final ImsSession _session;

  /// 取可用会话：**本地有就直接返回、不发任何请求**；没有才换票。
  ///
  /// [forceRefresh] 为 true 时强制换票（成绩页发现「凭证已失效」后的重试用）。
  Future<Either<Failure, String?>> getJsessionId({
    bool forceRefresh = false,
  }) async {
    try {
      final id = forceRefresh
          ? await _session.renew()
          : await _session.ensureReady();
      return Right(id);
    } catch (e) {
      return Left(UnknownFailure('失败: $e'));
    }
  }

  /// 强制换票（无视本地会话），成功后落盘。
  Future<String> refreshJsessionId() => _session.renew();

  /// 退出登录：忘记**当前账号**的会话（内存 + 磁盘）。
  ///
  /// ⚠️ 切换账号不要调这里——切号只是会话实例重建，各账号的会话按账号
  /// 分开存着，切回来还能直接复用。
  Future<void> logout() => _session.forget();

  /// 当前会话归属的账号。
  String get account => _session.account;
}
