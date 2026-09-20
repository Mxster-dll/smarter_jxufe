/// 异常体系的唯一基类（2026-09-20 立 · 架构审查后收敛）。
///
/// **为什么要有它**：收敛前全仓 29 个站点异常**各自 `implements Exception`**，各自重复
/// 写一遍 `final String message;` 与 `String toString() => message;`，彼此**没有任何公共
/// 类型** —— 于是「把异常文案说给用户听」这件事在 29 处各写一遍，界面层也**无法按类型
/// 分支**，只能退回「在 `e.toString()` 里搜关键字」这种「拿文案当类型」的写法。
///
/// 三条契约（新增异常一律照此，别再写 `implements Exception`）：
/// 1. `extends AppException`（会话失效用下面的 `SessionExpiredException`）；
/// 2. `message` = 能**直接说给用户听**的一句话（不带类名前缀、不带 `Exception: ` 前缀）；
/// 3. `toString()` 恒等于 `message` —— 界面层的 `'…：$e'` 打出来就是干净文案
///    （收敛前 `TgcExpiredException` 会把 `TgcExpiredException: ` 一起打给用户）。
///
/// 与 `failures.dart` 的分工（**刻意并存，不要互相转换**）：`Failure` 是
/// `Either<Failure, T>` 的**返回值**侧（dartz 风格，不抛）；本文件是**抛出**侧。
library;

/// 一切「能用一句话向用户解释」的异常的共同基类。
abstract class AppException implements Exception {
  const AppException(this.message);

  /// 能直接说给用户听的一句话。
  final String message;

  @override
  String toString() => message;
}

/// 「会话失效 / 需要重新登录」——**按类型分支，不许再拿文案当类型**。
///
/// 判据 = **名字里的 Expired + 补救动作都是「重新换票 / 重新登录」**。本族成员
/// （2026-09-20）：`JwSessionExpiredException`（教务）、`TgcExpiredException`（CAS 统一
/// 认证）、`ChaoxingSessionExpiredException`（学习通）、`TsgxsSessionExpiredException`
/// （入馆教育）、`ReadCreditSessionExpiredException`（阅读学分）、`LibspSessionExpiredException`
/// （图书馆）、`SspSessionExpiredException`（综合服务）、`DzjSessionExpiredException`
/// （数据中台）、`SelectionSessionExpired`（选课）。
///
/// ⚠ **不属于**本族（换票没用，别混进来）：学习通被风控
/// `ChaoxingChallengedException`（要等冷却）、入馆教育被顶下线 / 未解锁
/// `TsgxsAccessDeniedException`（业务状态，只有 `TsgxsSessionExpiredException` 才是会话），
/// 以及「会话**建立**失败」（`CxstarSessionException` / `LibspSessionException` 等）。
abstract class SessionExpiredException extends AppException {
  const SessionExpiredException(super.message);
}

/// 异常 → **可直接上屏的一句话**（界面层显示错误的唯一出口）。
///
/// 两件事：
/// 1. `AppException` 家族 → 直接取 `message`（本来就干净）；
/// 2. 历史遗留的 `throw Exception('文案')` → 剥掉 Dart 自带的 `Exception: ` 前缀
///    （`Exception('x').toString()` 是 `'Exception: x'`，直接 `'失败：$e'` 会把
///    英文类名打给用户）。
///
/// ⚠ 第 2 条是**过渡路径**：正解是把 `throw Exception(` 换成 typed 异常
/// （见 §33.5 的迁移清单），那样这里只剩第 1 条分支。数据中台曾自己写过一个
/// `dzjFriendlyError`（`lib/features/data_center/presentation/dzj_peer_sheet.dart`，
/// 只在数据中台与 AA 用），2026-09-20 上提到这里 —— **别再写第二份**。
String friendlyErrorText(Object error) {
  if (error is AppException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
