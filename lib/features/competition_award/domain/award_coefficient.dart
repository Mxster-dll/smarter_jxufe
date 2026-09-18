/// 竞赛奖励 —— 「赛事经验系数」（按赛事手动设置，用于等比缩减）。
///
/// 用户 2026-09-18 原话：「竞赛奖励有一个经验系数，就是有些奖项它拿的人太多，就会
/// 导致奖金被等比例缩小，而这个比例一般是固定的，我希望可以手动设置」。
/// 拍板两条口径（ask_user_question）：
/// - **按赛事设** —— 一个赛事的比例是固定的，配一次即可，该赛事所有记录等比缩减；
/// - **行内明算** —— 记录行显示「6000 元 × 0.6 = 3600 元」，并在「本次统计口径」里
///   说明哪几条被缩减。
///
/// 与办法原文的关系：《学科竞赛管理办法》第九条注 —— Ⅱ / Ⅲ 类「单个赛事总奖励金额
/// 不超过 10 万元（另一版 15 万元），如超过则按『奖励标准 ×（封顶额 / 该赛事总奖励
/// 金额）』计算奖励」。学校实际执行出来的那个比例就是这里的「经验系数」：总额算不出
/// 来时，直接把它固定下来，省得每次估（表里的 `notes` 仍照原样展示，不改）。
///
/// ⚠ 口径：系数乘在**调整后金额**上（`AwardAdjustment` 的 70% 等先算），且**在第十条 /
/// 第九条注的「取最高」之前**乘 —— 学校比的是实际发放金额，先缩后比才与办法一致。
library;

/// 系数取值范围（缩减语义：0 = 全不发，1 = 不缩减）。
const double kAwardCoefficientMin = 0.0;
const double kAwardCoefficientMax = 1.0;

/// 一条「赛事 → 经验系数」。
class AwardCoefficient {
  final String competitionName;

  /// 0~1；1 = 不缩减（UI 里等同没设置，但允许显式写 1）。
  final double factor;

  const AwardCoefficient({required this.competitionName, required this.factor});

  AwardCoefficient copyWith({String? competitionName, double? factor}) =>
      AwardCoefficient(
        competitionName: competitionName ?? this.competitionName,
        factor: factor ?? this.factor,
      );

  Map<String, dynamic> toJson() => {
    'name': competitionName,
    'factor': factor,
  };

  /// 容错解析：名字为空 / 系数认不出 → 跳过该条（不让旧数据崩页面）。
  static AwardCoefficient? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final value = raw['factor'];
    final factor = value is num ? value.toDouble() : null;
    if (factor == null || factor.isNaN) return null;
    return AwardCoefficient(
      competitionName: name.trim(),
      factor: factor.clamp(kAwardCoefficientMin, kAwardCoefficientMax),
    );
  }

  /// 展示用：`×0.6`。
  String get label => '×${fmtAwardCoefficient(factor)}';

  @override
  String toString() => 'AwardCoefficient($competitionName=$factor)';
}

/// 系数展示：`0.6` / `0.85` / `1`（去尾零，最多两位；整数不带小数点）。
String fmtAwardCoefficient(double v) {
  final text = v.toStringAsFixed(2);
  if (!text.contains('.')) return text;
  final trimmed = text
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return trimmed.isEmpty ? '0' : trimmed;
}

/// 解析用户输入的系数：`0.6` / `.6` / `60%` / `6折` / `1` → 0.6 / 0.6 / 0.6 / 0.6 / 1。
///
/// 越界（>1）→ 返回 null（系数是缩减语义，>1 一定是用错了；UI 提示改 0~1）。
/// 认不出 → null。
double? parseAwardCoefficient(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = text.replaceAll('％', '%').replaceAll(RegExp(r'\s+'), '');
  var scale = 1.0;
  if (text.endsWith('%')) {
    scale = 0.01;
    text = text.substring(0, text.length - 1);
  } else if (text.endsWith('折')) {
    scale = 0.1;
    text = text.substring(0, text.length - 1);
  }
  if (text.startsWith('.')) text = '0$text';
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value.isInfinite) return null;
  final factor = value * scale;
  if (factor < kAwardCoefficientMin || factor > kAwardCoefficientMax) {
    return null;
  }
  return factor;
}

/// 赛事名归一（去全部空白 + 小写）——与 `award_calc` 去重、`award_standard` 查表同一套。
String awardCoefficientKey(String competitionName) =>
    competitionName.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 赛事系数表（查询唯一入口）。
class AwardCoefficientTable {
  /// 已设的系数（同名只保留一条；保存时按 [upsert] 覆盖）。
  final List<AwardCoefficient> entries;

  const AwardCoefficientTable(this.entries);

  static const AwardCoefficientTable empty = AwardCoefficientTable([]);

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// 该赛事命中的系数；没设过 → 1.0（不缩减）。
  double factorFor(String competitionName) =>
      entryFor(competitionName)?.factor ?? 1.0;

  AwardCoefficient? entryFor(String competitionName) {
    final key = awardCoefficientKey(competitionName);
    if (key.isEmpty) return null;
    for (final e in entries) {
      if (awardCoefficientKey(e.competitionName) == key) return e;
    }
    return null;
  }

  /// 命中该系数的赛事名（用于「影响 N 条」的展示）。
  bool affects(String competitionName) =>
      awardCoefficientKey(competitionName).isNotEmpty &&
      entryFor(competitionName) != null;

  /// 新增 / 覆盖（同名按归一后的名字判重），返回新表。
  AwardCoefficientTable upsert(AwardCoefficient next) {
    final key = awardCoefficientKey(next.competitionName);
    final kept = [
      for (final e in entries)
        if (awardCoefficientKey(e.competitionName) != key) e,
    ];
    return AwardCoefficientTable([...kept, next]);
  }

  AwardCoefficientTable remove(String competitionName) {
    final key = awardCoefficientKey(competitionName);
    return AwardCoefficientTable([
      for (final e in entries)
        if (awardCoefficientKey(e.competitionName) != key) e,
    ]);
  }
}
