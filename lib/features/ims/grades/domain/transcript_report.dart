/// 本科生成绩单（门户「本科生成绩单」H5）的领域口径。
///
/// 官方后端（实测 2026-09-16）：
/// - `POST https://wxcourse.jxufe.cn/layuiApp/score/verifySecondMajor`（form: userId）
///   → `{"status":true,"message":",1,2"}`：message 从下标 1 起按 `,` 切分，
///   `1` = 有主修、`2` = 有辅修；本账号实测 `,1`（只有主修）。
/// - `POST https://wxcourse.jxufe.cn/layuiApp/score/bkscj`（form: userId/email/courseId）
///   → `{"status":true,"message":"…"}`：**把加盖电子签章的成绩单 PDF 发到该邮箱**。
///
/// 即：小程序侧只有「邮箱投递」，没有下载接口（教务处 2025-05-20 上线口径）。
library;

/// 一种可申请的报表类型（= H5 里 `select[name=courseId]` 的一个选项）。
class TranscriptReportType {
  const TranscriptReportType({required this.courseId, required this.label});

  /// 提交给服务端的 courseId（`1` / `11` / `2` / `22`）。
  final String courseId;

  /// 界面文案（与 H5 选项同字面）。
  final String label;

  @override
  String toString() => 'TranscriptReportType($courseId, $label)';
}

/// courseId → 文案（与服务端约定一一对应）。
const Map<String, String> kTranscriptReportLabels = {
  '1': '主修成绩单（中）',
  '11': '主修成绩单（英）',
  '2': '辅修成绩单（中）',
  '22': '辅修成绩单（英）',
};

/// 服务端 `verifySecondMajor` 的 message（形如 `,1` / `,1,2`）→ 可选报表类型列表。
///
/// - 首位无意义（H5 `message.substring(1)` 的口径），丢掉；
/// - `1` → 主修（中/英）两项，`2` → 辅修（中/英）两项；
/// - 未知标记忽略；重复标记只出一次；空 / 无有效标记 → 空列表（界面据此提示）。
List<TranscriptReportType> transcriptReportTypes(String? message) {
  final raw = (message ?? '').trim();
  if (raw.isEmpty) return const [];
  final body = raw.startsWith(',') ? raw.substring(1) : raw;
  final out = <TranscriptReportType>[];
  final seen = <String>{};
  for (final token in body.split(',')) {
    final key = token.trim();
    final ids = switch (key) {
      '1' => const ['1', '11'],
      '2' => const ['2', '22'],
      _ => const <String>[],
    };
    for (final id in ids) {
      if (!seen.add(id)) continue;
      out.add(
        TranscriptReportType(
          courseId: id,
          label: kTranscriptReportLabels[id] ?? id,
        ),
      );
    }
  }
  return out;
}

/// 邮箱格式校验（与 H5 的正则同款）。
final RegExp _transcriptEmailPattern = RegExp(
  r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,6}$',
);

bool transcriptEmailValid(String email) =>
    _transcriptEmailPattern.hasMatch(email.trim());

/// 学信网成绩单验证入口（H5/通知里给的官方验证地址）。
const String kTranscriptVerifyUrl = 'https://www.chsi.com.cn/cjdyz/index';
