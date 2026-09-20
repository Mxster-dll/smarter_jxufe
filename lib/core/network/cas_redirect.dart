/// 学校 CAS「把请求 302 打回登录页」判据的**唯一实现**（判 URL，非正文）。
///
/// 为什么需要它：CAS 在 TGC 失效时会把业务请求 302 回 `…/cas/login?service=…`
/// —— 这种「有 Location」**不是成功**。2026-09-19 实测踩过：`getRedirectImsUrl`
/// 对任何 Location 都当成功返回，于是换票拿到的是**未认证的匿名 JSESSIONID**，
/// 日志里却一直打印「换票成功」，直到首页课表卡片红字报「凭证已失效」。
///
/// 2026-09-20 架构审查发现这条判据被写了 3 份：`auth` 的严格版（末段比较），
/// 加上 `ssp` / `read_credit` 两处宽松的 `location.contains('cas/login')` ——
/// 宽松版会把 `/cas/loginfo` 以及「查询串里恰好带着 `/cas/login`」的地址
/// 误判成会话失效。现统一到本文件，各站点只保留**自己的**平台私有登录入口标记
/// （如 ssp 的 `/sso/login`、阅读学分平台的 `CASLogin`）。
library;

/// [url] 是否指向学校 CAS 登录页。
///
/// - **精确到路径末段**：`contains('/cas/login')` 会把 `/cas/loginfo` 误判进来；
/// - **先剥路径参数**：真实登录页长这样
///   `https://ssl.jxufe.edu.cn/cas/login;jsessionid=ABC`；
/// - **允许相对写法**：平台回跳实测有 `cas/login?service=…`（无前导斜杠），
///   补上前导斜杠后与绝对地址同判。
///
/// 调用方一律传 `Response.headers.value('location')` 或换证链当前跳转地址，
/// **不要**传响应正文（正文判据见 `sso_login_page.dart`）。
bool isCasLoginRedirect(String? url) {
  if (url == null || url.isEmpty) return false;
  final path = Uri.tryParse(url)?.path ?? '';
  var segment = path.split(';').first;
  if (!segment.startsWith('/')) segment = '/$segment';
  return segment == '/cas/login' || segment.endsWith('/cas/login');
}
