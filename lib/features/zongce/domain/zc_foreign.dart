/// 外语能力（表 10）证书目录 + **按档位识别**的分值口径。
///
/// 用户 2026-09-17 第一轮：「外语能力不要分成 xxx>aaa/xxx>bbb，直接按证书名字，
/// 然后手动填入分数」→ 候选按证书名目，分值曾由用户手填。
/// 用户 2026-09-17 第二轮（报错）：「四级加分有误，我四级 489 分，导致了加分加了
/// 489，但是实际要按挡位识别，参考综测的相关规章制度」→ 积分不再等于手填数字：
/// 目录内的证书一律**用原始成绩（四级 489、雅思 6.5、托福 90 …）在表 10 里查档位**，
/// 加分 = 档位分值；等级类证书（日语 N1/N2、专八/专四、TOPIK）无需填分，直接取固定分。
///
/// 表 10 原文（`D:\Entrust\JXUFE\2026综测\2026综测计算器.html` 规则点 r44）：
/// 雅思 ≥6.5 / 6≤x<6.5 → 2 / 1；托福 ≥93 / 78≤x<93 → 2 / 1；
/// GRE ≥320 / 310≤x<320 → 2 / 1；日语 N1 / N2 → 2 / 1；英、日专业 八级 / 四级 → 2 / 1；
/// 韩语 TOPIK 六级 / 四级 → 2 / 1；大学英语四六级（艺术体育类 ×1.5）六级≥425 / 四级≥425 → 2 / 1。
/// **上限 4 分；单项取最高**；其他证书由学院确认最终分值（**单项不高于 2 分**）。
library;

/// 表 10 档位：达到 [threshold]（原始成绩）即得 [score] 分；[threshold] 为 null = 等级类。
class ZcForeignBand {
  const ZcForeignBand(this.label, this.score, [this.threshold]);

  /// 档位文案（如 `大学英语四级 ≥425`）。
  final String label;

  /// 该档分值。
  final double score;

  /// 原始成绩门槛（雅思 6.5 / 四级 425 / GRE 320…）；等级类为 null。
  final double? threshold;
}

/// 一张外语证书（同名目只留一条；级别差异已是不同名目，如 日语 N1 / 日语 N2）。
class ZcForeignCert {
  const ZcForeignCert({required this.name, required this.bands, this.unit = ''});

  final String name;

  /// 档位，**按门槛从高到低**排列（查档时取第一个满足的）。
  final List<ZcForeignBand> bands;

  /// 原始成绩的单位/提示（`分` / 空）。
  final String unit;

  /// 是否需要用户填原始成绩（有门槛 = 需要；等级类 = 不需要）。
  bool get needsScore => bands.any((b) => b.threshold != null);

  /// 等级类证书的固定分值（需要填分的证书返回 0）。
  double get fixedScore => needsScore ? 0 : bands.first.score;

  /// 按原始成绩查档位；不够任何门槛 → null。
  ZcForeignBand? bandFor(double? raw) {
    if (raw == null) return null;
    for (final b in bands) {
      final t = b.threshold;
      if (t == null) return b;
      if (raw >= t) return b;
    }
    return null;
  }

  /// 加分 = 档位分值（未达线 = 0）。
  double awardFor(double? raw) {
    if (!needsScore) return fixedScore;
    return bandFor(raw)?.score ?? 0;
  }

  /// 档位说明（表单提示用）：`大学英语四级 ≥425 → 1.0 分`。
  String get bandHint => bands
      .map((b) => '${b.label} → ${_fmtScore(b.score)} 分')
      .join('；');
}

String _fmtScore(double v) =>
    v == v.roundToDouble() ? v.round().toString() : '$v';

/// 外语类加分上限（表 10：「外语类加分上限 4 分；单项取最高」）。
const double kZcForeignTotalCap = 4;

/// 目录外的「其他证书」单项上限（表 10：「由学院确认最终分值（单项不高于 2 分）」）。
const double kZcForeignOtherCap = 2;

/// 外语证书目录（13 条；顺序即选择页展示顺序）。
const List<ZcForeignCert> zcForeignCatalog = [
  ZcForeignCert(
    name: '雅思',
    bands: [
      ZcForeignBand('雅思 ≥6.5', 2, 6.5),
      ZcForeignBand('雅思 6 ≤ x < 6.5', 1, 6),
    ],
  ),
  ZcForeignCert(
    name: '托福',
    bands: [
      ZcForeignBand('托福 ≥93', 2, 93),
      ZcForeignBand('托福 78 ≤ x < 93', 1, 78),
    ],
  ),
  ZcForeignCert(
    name: 'GRE',
    bands: [
      ZcForeignBand('GRE ≥320', 2, 320),
      ZcForeignBand('GRE 310 ≤ x < 320', 1, 310),
    ],
  ),
  ZcForeignCert(
    name: '日语 N1',
    bands: [ZcForeignBand('日语 N1', 2)],
  ),
  ZcForeignCert(
    name: '日语 N2',
    bands: [ZcForeignBand('日语 N2', 1)],
  ),
  ZcForeignCert(
    name: '英/日专业八级',
    bands: [ZcForeignBand('英/日专业八级', 2)],
  ),
  ZcForeignCert(
    name: '英/日专业四级',
    bands: [ZcForeignBand('英/日专业四级', 1)],
  ),
  ZcForeignCert(
    name: '韩语 TOPIK 六级',
    bands: [ZcForeignBand('韩语 TOPIK 六级', 2)],
  ),
  ZcForeignCert(
    name: '韩语 TOPIK 四级',
    bands: [ZcForeignBand('韩语 TOPIK 四级', 1)],
  ),
  ZcForeignCert(
    name: '大学英语六级',
    unit: '分',
    bands: [ZcForeignBand('大学英语六级 ≥425', 2, 425)],
  ),
  ZcForeignCert(
    name: '大学英语四级',
    unit: '分',
    bands: [ZcForeignBand('大学英语四级 ≥425', 1, 425)],
  ),
  ZcForeignCert(
    name: '四六级（艺术体育类）六级',
    unit: '分',
    bands: [ZcForeignBand('四六级（艺术体育类）六级 ≥425', 3, 425)],
  ),
  ZcForeignCert(
    name: '四六级（艺术体育类）四级',
    unit: '分',
    bands: [ZcForeignBand('四六级（艺术体育类）四级 ≥425', 1.5, 425)],
  ),
];

/// 证书名目（选择页候选）。
List<String> get zcForeignCertNames =>
    [for (final c in zcForeignCatalog) c.name];

/// 名称规范化：去空白、半角括号→全角（旧数据里出现过 `四六级(艺术体育类) 六级`）。
String _normalizeCertName(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), '').replaceAll('(', '（').replaceAll(')', '）');

/// 按名称查证书（容错空白与半角括号）；目录外返回 null。
ZcForeignCert? zcForeignCertOf(String name) {
  final key = _normalizeCertName(name);
  if (key.isEmpty) return null;
  for (final c in zcForeignCatalog) {
    if (_normalizeCertName(c.name) == key) return c;
  }
  return null;
}

/// **原文条目名**（表 10 那一行的加分条目名），如 `大学英语四级 ≥425`。
///
/// 用户 2026-09-18：「综测智育外语水平加分条目不能只显示『大学英语四级』这样的
/// 证书名，要显示原文里『大学英语四级>=425』这样的加分条目名」→ 目录内证书取
/// 命中档位的 [ZcForeignBand.label]（等级类证书的 label 就是证书名，两轮口径一致）。
///
/// 返回 null = **认不出的情形，行标题保持证书名**：目录外（其他证书，学院定分）、
/// 需要原始成绩但没填、或填了分却不到任何档位（未达门槛时把 `≥425` 挂上去反而
/// 像已经拿到了那一档）。
String? zcForeignEntryLabel({required String name, double? rawScore}) {
  final cert = zcForeignCertOf(name);
  if (cert == null) return null;
  if (!cert.needsScore) {
    return cert.bands.isEmpty ? null : cert.bands.first.label;
  }
  return cert.bandFor(rawScore)?.label;
}

/// **原始成绩文案**（去尾零：`489` / `6.5`）—— 材料库列表用。
///
/// 用户 2026-09-18：「材料库不是综测的材料库，因此里面的四级证书这样的，不需要
/// 显示『大学英语四级 489 → 1 分』而是直接显示『489』就可以了」→ 综测那边要
/// 分数换算（[zcForeignScoreLabel]），材料库只登记事实（原始成绩）。
/// 没有填分（等级类证书 / 未填）→ 返回空串，调用方据此不出这一枚胶囊。
String zcForeignRawScoreText(double? rawScore) {
  if (rawScore == null) return '';
  return _fmtScore(rawScore);
}

/// 加分口径（唯一实现，`zcMaterialValue` 与表单/行内文案共用）。
///
/// - 目录内证书：需要原始成绩的按档位识别（未达线 = 0）；等级类取固定分。
/// - 目录外（其他证书）：手填分值即分值，**上限 2 分**。
/// - 目录内但没填原始成绩（旧材料只存了档位下标）→ 返回 null，由调用方回退表内档位。
double? zcForeignAward({required String name, double? rawScore}) {
  final cert = zcForeignCertOf(name);
  if (cert != null) {
    if (cert.needsScore && rawScore == null) return null;
    return cert.awardFor(rawScore).clamp(0, kZcForeignTotalCap);
  }
  if (rawScore == null) return null;
  return rawScore.clamp(0, kZcForeignOtherCap);
}

/// 行内/表单文案：`四级 489 分 → 1 分`、`日语 N1 → 2 分`、`其他证书 1.5 分`。
String zcForeignScoreLabel({required String name, double? rawScore}) {
  final cert = zcForeignCertOf(name);
  if (cert == null) {
    if (rawScore == null) return '';
    return '其他证书 ${_fmtScore(rawScore)} 分（上限 ${_fmtScore(kZcForeignOtherCap)} 分）';
  }
  if (!cert.needsScore) return '${cert.name} → ${_fmtScore(cert.fixedScore)} 分';
  if (rawScore == null) return cert.unit.isEmpty ? '待填成绩' : '待填分数';
  final band = cert.bandFor(rawScore);
  final raw = _fmtScore(rawScore);
  if (band == null) {
    return '${cert.name} $raw → 未达表 10 门槛（0 分）';
  }
  return '${cert.name} $raw → ${_fmtScore(band.score)} 分';
}
