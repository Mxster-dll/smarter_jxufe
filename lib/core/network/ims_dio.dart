import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/debug_proxy.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/core/network/interceptors/ims_auth_interceptor.dart';

/// IMS（教务 `jwxt.jxufe.edu.cn`）Dio 的**唯一构造入口**。
///
/// 返回 Dio 与其专属的凭证失效拦截器：
/// - 拦截器随 Dio 创建，**不再用全局单例 + `setDio`**——那样在多账户并存时
///   后建的 Dio 会覆盖重试用的 Dio，把重试发到别人的会话上；
/// - 调用方拿到后必须 `interceptor.setRefreshCallback(session.renew)`
///   （见 `features/ims/auth/data/providers/ims_session_provider.dart`）。
///
/// 全局只应存在一个 IMS Dio（由 `ImsSession` 持有）；除了别处确有需要的
/// 无会话场景（如桌面小组件后台），不要重复创建。
({Dio dio, ImsAuthInterceptor interceptor}) createImsDio(
  DeviceProfileRepository deviceProfileRepo,
) {
  final dio = createAppDio(
    baseUrl: 'https://jwxt.jxufe.edu.cn',
    // 换证链要逐跳看 `Set-Cookie`：重定向必须自己走。
    followRedirects: false,
    // 教务接口偶发挂起：必须给足超时，否则请求会无限转圈
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    userAgent: deviceProfileRepo.userAgent,
    headers: {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'sec-ch-ua':
          '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'Referer': 'http://ehall.jxufe.edu.cn/',
    },
    // 教务正文是 GBK（`jwxt` 一族的老毛病）。
    responseDecoder: gbkAwareResponseDecoder(),
  );
  final interceptor = ImsAuthInterceptor(dio: dio);
  dio.interceptors.add(interceptor);
  // 抓包：`--dart-define=FIDDLER_PROXY=true` 打开，默认常量 false（见 debug_proxy.dart）。
  if (kFiddlerProxyEnabled) applyFiddlerProxy(dio);
  return (dio: dio, interceptor: interceptor);
}
