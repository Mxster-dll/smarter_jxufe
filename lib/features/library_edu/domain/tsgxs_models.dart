/// 新生入馆教育(tsgxs.jxufe.cn)领域模型。
library;

/// 入馆教育皮肤(版本)。登录页提供三种,学习进度为账号级(不分版本)。
class TsgxsTheme {
  final String id;
  final String label;

  const TsgxsTheme(this.id, this.label);
}

/// 三种皮肤(实测 2026-09-10,登录页 radio 值)。
const List<TsgxsTheme> tsgxsThemes = [
  TsgxsTheme('5d037bb3-12c5-4554-a3c2-d128766dd025', '书生版'),
  TsgxsTheme('e3e409c4-7b51-4a75-a58f-92201dd6e660', '战士版'),
  TsgxsTheme('7d11523c-e79c-4b9f-b119-5b40a750b90d', '校园版'),
];

/// 默认皮肤(登录页默认选中书生版)。
const String tsgxsDefaultThemeId = '5d037bb3-12c5-4554-a3c2-d128766dd025';

/// 皮肤 id → 名称(未知返回「其他版本」)。
String tsgxsThemeLabel(String id) {
  for (final t in tsgxsThemes) {
    if (t.id == id) return t.label;
  }
  return '其他版本';
}

/// 章节地图中的一个学习节点(线索)。
class TsgxsNode {
  /// 节点 id(即内容页 `/Web/Chapter/Content/<id>`)。
  final String id;

  /// 节点图标 URL(章节地图上的可点击图标)。
  final String imageUrl;

  /// 节点名称;仅部分章节在 `data-intro` 中提供,否则为 null。
  final String? name;

  const TsgxsNode({required this.id, required this.imageUrl, this.name});
}

/// 章节(含地图节点与考点状态)。
class TsgxsChapter {
  final String id;
  final String title;

  /// 本章所有线索是否已全部学习(服务端下发,决定能否「闯关」)。
  final bool isVisitAll;

  /// 考试状态码(服务端下发):1/4=可闯关,2=链式下一章,0=未知。
  final int examinations;

  final List<TsgxsNode> nodes;

  /// 服务端未解锁:上一章未通过时,本章地图请求会被 302 到 `/html/401.html`
  /// (实测 2026-09-11)。此时只能拿到章节 id,节点/考点状态未知。
  final bool locked;

  const TsgxsChapter({
    required this.id,
    required this.title,
    required this.isVisitAll,
    required this.examinations,
    required this.nodes,
    this.locked = false,
  });

  /// 未解锁占位章(仅有 id)。
  const TsgxsChapter.locked(this.id)
    : title = '',
      isVisitAll = false,
      examinations = 0,
      nodes = const [],
      locked = true;

  /// 展示用标题:未解锁章服务端不下发标题,按序号兜底。
  String displayTitle(int index) =>
      title.isNotEmpty ? title : '第 ${index + 1} 章';

  /// 考试已通过(服务端在 `/Web/Exam?cid=` 返回通过提示;此处为闯关可用性的
  /// 近似:examinations==1 且线索已看完)。
  bool get canStartExam =>
      !locked && isVisitAll && (examinations == 1 || examinations == 4);
}

/// 学习内容页(正文以图片形式下发)。
class TsgxsContent {
  final String nodeId;
  final String title;
  final List<String> imageUrls;
  final String? prevNodeId;
  final String? nextNodeId;

  /// 返回地图的目标章节 id。
  final String? chapterId;

  const TsgxsContent({
    required this.nodeId,
    required this.title,
    required this.imageUrls,
    this.prevNodeId,
    this.nextNodeId,
    this.chapterId,
  });
}

/// 单次考试成绩。
class TsgxsGrade {
  final String examTime;
  final String elapsed;
  final String score;

  const TsgxsGrade({
    required this.examTime,
    required this.elapsed,
    required this.score,
  });

  @override
  bool operator ==(Object other) =>
      other is TsgxsGrade &&
      other.examTime == examTime &&
      other.elapsed == elapsed &&
      other.score == score;

  @override
  int get hashCode => Object.hash(examTime, elapsed, score);
}

/// 排行榜行。
class TsgxsRankRow {
  final int rank;
  final String name;
  final String score;
  final String elapsed;

  const TsgxsRankRow({
    required this.rank,
    required this.name,
    required this.score,
    required this.elapsed,
  });
}

/// 排行榜(我的名次 + 全校榜单)。
class TsgxsRanking {
  final List<TsgxsRankRow> rows;
  final String note;

  const TsgxsRanking({required this.rows, this.note = ''});

  /// 我的名次(榜单中排名最小者视为本人所在行不可判,故由页面独立表提供;
  /// 这里返回榜单首行名次用于「榜首」展示)。
  int? get topRank => rows.isEmpty ? null : rows.first.rank;
}

/// 个人资料。
class TsgxsProfile {
  final String account;
  final String name;
  final String college;

  const TsgxsProfile({
    required this.account,
    required this.name,
    required this.college,
  });
}
