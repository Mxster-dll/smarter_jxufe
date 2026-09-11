import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_remote_datasource.dart';

/// IMS 会话续期的**唯一实现**：CAS 回跳地址 + gid → 新 JSESSIONID → 激活。
///
/// 两条链路共用这一段，避免口径漂移：
/// - App 内：`ImsSession.renew()`（`lib/features/ims/auth/data/ims_session.dart`）；
/// - 桌面小组件后台刷新：`home_widget_background.dart` 的 `_renewJsessionId`。
///
/// [redirectUrl] / [gid] 由调用方按各自的凭据来源解析——App 侧有 TGC 过期后的
/// 缓存放凭据静默重登（`AuthRepository.getImsRedirectInfo`），小组件侧只有 TGC：
/// - App：`await authRepository.getImsRedirectInfo()`
/// - 小组件：`await AuthRemoteDataSource(casDio).getRedirectImsUrl(tgc)`
///
/// `gid` 为空时由 [ImsAuthRemoteDataSource.fetchJsessionId] 回退到内置默认值。
///
/// 第二步行（用新票访问 CAS 回跳地址）不可省：不激活的话教务业务接口仍视为未登录。
Future<String> fetchAndActivateJsessionId({
  required Dio imsDio,
  required String redirectUrl,
  String? gid,
}) async {
  final fresh = await ImsAuthRemoteDataSource(imsDio).fetchJsessionId(gid: gid);
  await imsDio.get(
    redirectUrl,
    options: Options(headers: {'Cookie': 'JSESSIONID=$fresh'}),
  );
  return fresh;
}
