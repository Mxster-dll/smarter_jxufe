/// 五育占比（总评成绩 = Σ 五育分数 × 各自占比）。
///
/// 用户 2026-09-18：「综测不是直接算平均分，而是有一个总评成绩，这个成绩的占比由
/// 班主任定，应该让用户自行设置」→ 占比**不进规则表**（学校文件里没有比例），
/// 由用户自己填；默认取用户当场拍板的一套 `20 / 35 / 15 / 15 / 15`
/// （德育 20 / 智育 35 / 体育 15 / 美育 15 / 劳育 15）。
///
/// 存储口径（用户同日二选一）：**按学年各存一套** —— 挂在 `ZcManual`（Hive key
/// `manual-<测评学年结束年>`）里，与评议分/体测/志愿时长同一份、同一账号隔离，
/// 因此切学年自动换一套、已评过的学年不会被新比例改写。
///
/// 单位 = **百分数**（`20` 就是 20%），不是 0~1 小数：界面按百分数输入，落盘也按
/// 百分数，避免往返时的精度与显示分歧（`label` 直接可读）。
library;

/// 默认占比（用户 2026-09-18 拍板）：德育 / 智育 / 体育 / 美育 / 劳育。
const List<double> kZcDefaultWeightPercents = [20, 35, 15, 15, 15];

/// 五育名称（顺序与 [ZcWeights.values] 一致）。
const List<String> kZcWeightLabels = ['德育', '智育', '体育', '美育', '劳育'];

/// 合计允许的误差（百分点）：`100 ± 0.5` 视为「合计 100%」。
const double kZcWeightTolerance = 0.5;

/// 百分数文案：整数不带小数点（`20`）、小数最多一位（`12.5`）。
String zcWeightPercentText(double v) {
  final r = (v * 10).roundToDouble() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// 一套五育占比。
class ZcWeights {
  /// 德育占比（百分数）。
  final double d;

  /// 智育占比（百分数）。
  final double z;

  /// 体育占比（百分数）。
  final double t;

  /// 美育占比（百分数）。
  final double m;

  /// 劳育占比（百分数）。
  final double l;

  const ZcWeights({
    this.d = 20,
    this.z = 35,
    this.t = 15,
    this.m = 15,
    this.l = 15,
  });

  /// 默认档（= 用户拍板的 20/35/15/15/15）。
  static const ZcWeights initial = ZcWeights();

  /// 等权档（各 20% = 旧的「五育平均」口径，弹层里的便捷预设）。
  static const ZcWeights even = ZcWeights(d: 20, z: 20, t: 20, m: 20, l: 20);

  /// 五项占比（顺序 = [kZcWeightLabels]）。
  List<double> get values => [d, z, t, m, l];

  /// 合计（百分数；正常应为 100）。
  double get sum => d + z + t + m + l;

  /// 合计是否为 100%（允许 [kZcWeightTolerance] 的误差）。
  bool get isValid => (sum - 100).abs() <= kZcWeightTolerance;

  /// 是否为等权档。
  bool get isEven => values.every((v) => (v - 20).abs() < 0.005);

  /// 展示文案：`20 / 35 / 15 / 15 / 15`。
  String get label => values.map(zcWeightPercentText).join(' / ');

  ZcWeights copyWith({double? d, double? z, double? t, double? m, double? l}) =>
      ZcWeights(
        d: d ?? this.d,
        z: z ?? this.z,
        t: t ?? this.t,
        m: m ?? this.m,
        l: l ?? this.l,
      );

  /// 总评成绩 = Σ 五育分数 × 占比 / 100。
  ///
  /// 未归一（合计 ≠ 100）时**直接按填写值算**（不做隐式归一）：界面会拦住合计
  /// 不为 100 的保存，所以这里只服务「读旧数据」这一种情形，按填写值算最接近
  /// 用户当时的意图。
  double applyTo({
    required double deyu,
    required double zhiyu,
    required double tiyu,
    required double meiyu,
    required double laoyu,
  }) => (deyu * d + zhiyu * z + tiyu * t + meiyu * m + laoyu * l) / 100;

  Map<String, dynamic> toJson() => {'d': d, 'z': z, 't': t, 'm': m, 'l': l};

  /// 容错读取：非 Map / 字段非数 / 越界（不在 0~100）/ 合计不是 100% → 回落默认档。
  ///
  /// ⚠ 不要写成 `as num?`：脏数据（字符串）会抛 `type 'String' is not a subtype
  /// of type 'num?'`（本仓库踩过同款）。另外合计校验放这里，是为了让「旧版本
  /// 写坏的比例」不会在结果卡上算出离谱的总评；越界值**不做 clamp**（把 120
  /// 夹成 100 会静默造出一套「德育 100%」的合法比例，比回落默认档更糟）。
  static ZcWeights fromJson(Object? json) {
    if (json is! Map) return initial;
    final raw = [json['d'], json['z'], json['t'], json['m'], json['l']];
    final values = <double>[];
    for (final v in raw) {
      if (v is! num) return initial;
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite || d < 0 || d > 100) return initial;
      values.add(d);
    }
    final out = ZcWeights(
      d: values[0],
      z: values[1],
      t: values[2],
      m: values[3],
      l: values[4],
    );
    return out.isValid ? out : initial;
  }

  @override
  bool operator ==(Object other) =>
      other is ZcWeights &&
      other.d == d &&
      other.z == z &&
      other.t == t &&
      other.m == m &&
      other.l == l;

  @override
  int get hashCode => Object.hash(d, z, t, m, l);
}
