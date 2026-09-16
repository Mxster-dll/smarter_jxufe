/// 「数据一览」课程加权卡的排名胶囊文案。
///
/// 用户 2026-09-15 裁定：a/b/c = 班级 / 专业 / 年级排名，同日二轮改为
/// `#a/b/c` 的紧凑写法（`#` 前缀 + 斜杠分隔、斜杠两侧不留空格）。
/// 取不到的排名（≤ 0）写 `—`（教务未给出该维度排名时）。
///
/// 抽成纯函数是为了可单测：胶囊挂在 `dashboard_panel.dart` 的私有
/// `_gradeRankCapsule` 里，整块 DashboardPanel 需要一堆数据 provider 才能 pump。
library;

/// 单个维度排名文案：`1` / `—`。
String gradeRankText(int rank) => rank > 0 ? '$rank' : '—';

/// 排名胶囊文案：`#班级/专业/年级`。
String gradeRankBadge({
  required int classRank,
  required int majorRank,
  required int gradeRank,
}) =>
    '#${gradeRankText(classRank)}/${gradeRankText(majorRank)}/'
    '${gradeRankText(gradeRank)}';

/// 胶囊 tooltip（完整含义，桌面悬停 / 手机长按可见）。
String gradeRankTooltip({
  required int classRank,
  required int majorRank,
  required int gradeRank,
}) =>
    '排名（班级 / 专业 / 年级）：'
    '${gradeRankText(classRank)} / ${gradeRankText(majorRank)} / '
    '${gradeRankText(gradeRank)}';
