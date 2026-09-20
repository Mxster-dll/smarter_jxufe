/// 教务（强智）页面解码口径 —— 一处实现，公共查询 / 选课 / 课表 共用。
///
/// **实测事实（2026-09-14，见 `reverse_engineering/公共查询接口.md` §编码）**：
/// - **正文页**（选课结果 `wsxk.zxjg.jsp`、公共查询报表、`taglib/DataTable.jsp` 列表）
///   是 **GBK**，且响应头**不带 charset**；
/// - 但**会话失效页是 UTF-8**：547 字节的
///   `<script>alert('温馨提示：凭证已失效，请重新登录!');…`。
///
/// 坑：`fast_gbk` 对任意字节都能解出结果（UTF-8 的中文会解成
/// `娓╅Θ鎻愮ず` 这类乱码），所以「先按 GBK 解、再用 `contains('凭证已失效')` 判失效」
/// 的写法**永远判不出失效** —— 页面会静默退化成「空结果」，
/// 界面显示「没有已选课程 / 没有检索到记录」，把会话过期伪装成没数据。
///
/// **本文件 = 教务页文本口径的唯一出处**（2026-09-20 收敛，架构审查后）：
/// - **怎么解** → [decodeJwPage]；
/// - **怎么判失效** → [jwSessionExpired]（此前 `public_query.dart` 的
///   `isExpiredSession` 与选课数据源的静态 `isExpiredSession` 是同一判据的另外两份
///   写法，已删除 / 转发到本函数）；
/// - **失效抛什么** → [JwSessionExpiredException]（此前 6 处各写
///   `throw Exception('凭证已失效，请重新登录')`，仓库层只能拿文案当类型去
///   `e.toString().contains('凭证已失效')`）；
/// - **怎么识别失效异常** → [isJwSessionExpiredError]。
///
/// ⚠ `lib/core/network/interceptors/ims_auth_interceptor.dart` 用的是**故意更严**的
/// [jwSessionExpiredPrefix]（只认页首那串精确 alert 前缀），因为它的动作是「换票重试」，
/// 误判代价高于漏判；它拒绝时会把 [JwSessionExpiredException] 塞进
/// `DioException.error`，于是 [isJwSessionExpiredError] 能统一认出两条来源。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';

/// 教务会话失效的判据（547 字节 alert 页的文案）。**全仓唯一实现。**
bool jwSessionExpired(String body) =>
    body.contains('凭证已失效') || body.contains('请重新登录');

/// 失效 alert 页的**整串前缀**（比 [jwSessionExpired] 严：要求从正文首字符起逐字一致）。
///
/// 用在「误判的代价高于漏判」的地方 —— 目前只有
/// `lib/core/network/interceptors/ims_auth_interceptor.dart`（命中就会换票重试），
/// 它宁可只认完整前缀，也不认「正文里恰好引用了这句文案」。
/// 文案本身也只在这里写一份（服务端 2026-09-14 实测为 UTF-8、547 字节）。
const String jwSessionExpiredPrefix =
    "<script>alert('温馨提示：凭证已失效，请重新登录!');";

/// 教务会话失效（「凭证已失效，请重新登录」alert 页）。
///
/// [message] 保持各调用点原有的用户可见文案（半角/全角叹号历史上不统一，**不要
/// 顺手统一** —— 有测试与界面按原文案断言）；[toString] 返回它，所以历史上任何
/// 还在拿 `e.toString()` 判别的代码**行为不变**。
class JwSessionExpiredException extends SessionExpiredException {
  const JwSessionExpiredException([super.message = '凭证已失效，请重新登录！']);
}

/// 这个异常是不是「教务会话失效」—— **按类型判，不看文案**。
///
/// 两条来源都要认：
/// 1. 数据源直接抛的 [JwSessionExpiredException]；
/// 2. `ImsAuthInterceptor` 换票重试三次仍失败后 `reject` 的 [DioException]，
///    它把同一个异常放在 `DioException.error` 里。
bool isJwSessionExpiredError(Object error) {
  if (error is JwSessionExpiredException) return true;
  if (error is DioException && error.error is JwSessionExpiredException) {
    return true;
  }
  return false;
}

/// 按教务真实编码解一页 HTML（先严格试 UTF-8 认失效页，其余一律 GBK）。
///
/// 顺序不能反：GBK 对 UTF-8 字节不报错，先 GBK 就再也认不出失效页。
String decodeJwPage(List<int> bytes) {
  if (bytes.isEmpty) return '';
  try {
    final utf8Text = utf8.decode(bytes);
    if (jwSessionExpired(utf8Text)) return utf8Text;
  } catch (_) {
    // 正常 GBK 正文页在这里抛（字节不是合法 UTF-8）→ 走下面的 GBK。
  }
  try {
    return gbk.decode(bytes);
  } catch (_) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}

/// 教务会话**建立**失败（与「已失效」[JwSessionExpiredException] 区分：
/// 这个的补救动作是重试 / 重登，不是换票）。
///
/// 2026-09-20 加：`lib/core/network/schedule_repository.dart` 原来抛裸
/// `Exception('获取 JSESSIONID 失败')` —— `toString()` 带 `Exception: ` 前缀。
class JwSessionException extends AppException {
  const JwSessionException(super.message);
}
