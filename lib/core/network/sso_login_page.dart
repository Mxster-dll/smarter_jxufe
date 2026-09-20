/// SSO 门户（综合管理平台 / 第二课堂 / 志愿时长 / 蛟湖阅读）登录页判据的**唯一实现**。
///
/// 这些服务同属学校 SSO（`ssp.jxufe.edu.cn` 一族），会话失效有两种表现：
/// 3xx 跳登录页（由各数据源判 `Location`），或 **200 + 登录页 HTML**（本文件）。
/// 2026-09-20 收敛前，同一段判据在 `lib/features/comprehensive_service/` 里
/// 被逐字复制 **4 份**（另加 1 份只看前 512 字节的二进制版）→ 现统一到这里。
///
/// ⚠ 判据**只对以 HTML 开头的正文生效**：业务数据（HTML 片段、JSON、docx 字节）
/// 一律不参与匹配，否则「通知正文里恰好提到 `/sso/login`」会被误判成会话失效。
library;

/// 响应体是否为 SSO 登录页 / 会话失效页（3xx 之外的第二道判据）。
bool ssoLoginPage(String body) {
  final trimmed = body.trimLeft();
  if (!trimmed.startsWith('<!DOCTYPE html') && !trimmed.startsWith('<html')) {
    return false;
  }
  return trimmed.contains('authFailure') ||
      trimmed.contains('/sso/login') ||
      RegExp(r'<title>\s*登录').hasMatch(trimmed);
}

/// 二进制响应体（如 Word 登记表下载）是否为登录页。
///
/// 真实的登记表是 OOXML 压缩包（`PK\x03\x04`）或旧版 OLE（`D0 CF 11 E0`），
/// 都不会以 `<` 开头；只看开头 [headBytes] 字节，非 ASCII 一律按空格。
bool ssoLoginPageBytes(List<int> bytes, {int headBytes = 512}) {
  final head = bytes
      .take(headBytes)
      .map((byte) => byte < 0x80 ? String.fromCharCode(byte) : ' ')
      .join()
      .trimLeft();
  if (head.startsWith('<')) return true;
  return head.contains('authFailure') || head.contains('/sso/login');
}
