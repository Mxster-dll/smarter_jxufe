/// 后门模式「补全线索」的领域模型与常量。
///
/// 背景(实测 2026-09-11):入馆教育服务端在 **GET 内容页** 时就记账「该线索已
/// 学习」——全站找不到独立的「标记已学」接口(内容页既无 ajax 也无 beacon,
/// 动态加载的 `intro.js` 只是新手引导 tour)。线索学完后章节地图下发的
/// `exam('true', …)`(即 `isVisitAll`)翻真,答题页才从 302 `/html/401.html`
/// 变成 200 并下发 `examRecordDetailsId`。
///
/// 因此后门模式只要**逐节点 GET 一遍内容页**(贴近真人阅读的节奏),就能让服务端
/// 认定本章线索已学完;普通模式不做这一步,仍要求真的逐条学习。
library;

/// 每拉开一个线索后停留时长(用户拍板:2026-09-11 由 3 秒改为 0.2 秒)。
const Duration tsgxsClueSweepDwell = Duration(milliseconds: 200);

/// [tsgxsClueSweepDwell] 的界面文案(各页面统一引用,避免与常量漂移)。
final String tsgxsClueSweepDwellText = () {
  final ms = tsgxsClueSweepDwell.inMilliseconds;
  final text = ms % 1000 == 0 ? '${ms ~/ 1000}' : '${ms / 1000}';
  return '$text 秒';
}();

/// 补全后复核服务端状态的次数与间隔(服务端可能异步落库)。
const int tsgxsClueSweepVerifyAttempts = 3;
const Duration tsgxsClueSweepVerifyGap = Duration(seconds: 2);

/// 一次「补全线索」的结果。
class TsgxsClueSweepResult {
  /// 本章线索总数。
  final int total;

  /// 本次实际打开(拉取内容页)的线索数。
  final int fetched;

  /// 执行前服务端是否已认定「本章线索全部学习完成」。
  final bool alreadyLearned;

  /// 补全后服务端是否放行(复核到 `isVisitAll == true`)。
  final bool verified;

  /// 实际复核次数。
  final int verifyAttempts;

  const TsgxsClueSweepResult({
    required this.total,
    required this.fetched,
    required this.alreadyLearned,
    required this.verified,
    required this.verifyAttempts,
  });

  /// 服务端当前是否已认定本章线索学完(无需补全或补全成功)。
  bool get ok => alreadyLearned || verified;

  /// 给界面用的一句话结论。
  String get summary {
    if (alreadyLearned) return '服务端已认定本章线索全部学习完成(无需补全)';
    if (verified) return '服务端已确认:$fetched/$total 个线索记为已学习,答题已放行';
    return '已逐个打开 $fetched/$total 个线索,但服务端复核 $verifyAttempts 次仍未放行';
  }
}
