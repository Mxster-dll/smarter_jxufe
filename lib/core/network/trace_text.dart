/// 诊断 / 轨迹文本的统一截断口径（trace、异常消息里嵌响应正文时用）。
///
/// 2026-09-20 收敛：此前 **8 个文件各写一份 `_clip`** —— 6 份逐字相同、`tsgxs` 只改了
/// 参数名、`lib/features/ai/data/ai_client.dart` 带 `[int max = 200]` 默认值、
/// `lib/features/tice/data/tice_remote_datasource.dart` 固定 200 —— 语义完全一致
/// （超长就从 [max] 处截断并补 `…`），故合并为一份。
///
/// ⚠ **只用于日志与异常消息**：任何会进入界面、落盘或参与比较的业务字段都不要用它
/// （它静默丢字）。
library;

/// [value] 超过 [max] 个字符时截断并补省略号，否则原样返回。
String clipForTrace(String value, int max) =>
    value.length > max ? '${value.substring(0, max)}…' : value;

/// 默认按 200 字符截断（`ai_client` / `tice` 两处历史上的默认值）。
String clipForTrace200(String value) => clipForTrace(value, 200);
