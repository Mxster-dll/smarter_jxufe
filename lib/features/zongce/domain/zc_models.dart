/// 综测材料与手动输入模型。
library;

import 'dart:convert';

import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart'
    show schoolYearFallback, schoolYearStartOf;

import 'zc_catalog.dart';
import 'zc_foreign.dart';
import 'zc_rules.dart';
import 'zc_weights.dart';

/// 测评学年（结束年编码）：测评学年 [yearEnd] 覆盖窗口
/// `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`（yearEnd=2026），即对上一教学学年的测评。
///
/// ⚠ 2026-09-27 起**唯一实现在 `school_calendar/domain/school_time.dart`**
/// （`schoolYearFallback(yearEnd - 1)`）—— 本函数只是转发别名，别再往这里加日期算法。
/// 综测引擎是纯函数、拿不到校历数据，所以固定用兜底窗口；需要真实学年末
/// （`[xn+1]` 学年首日 − 1 天）的调用方请传 `SchoolTimeTable`。
bool zcYearWindowContains(DateTime d, int yearEnd) =>
    schoolYearFallback(yearEnd - 1).contains(d);

/// 默认测评学年：9 月起对刚结束的学年测评（2026-09 → 2025-2026 即 yearEnd 2026）；
/// 1~8 月（测评季尚未到 9 月）默认最近一个已完成学年。
///
/// ⚠ 2026-09-27 起算术在 `school_calendar/domain/school_time.dart` 的
/// `schoolYearStartOf`（本函数 = 转发别名）。
int zcDefaultYear(DateTime now) => schoolYearStartOf(now);

/// 学年窗口 label，如 「2025-2026 学年」。
String zcYearLabel(int yearEnd) => '${yearEnd - 1}-$yearEnd 学年';

/// 「测评学年（结束年）」→ 「学年选择器（`AcademicYearPicker`）三元组参数」的换算。
///
/// ⚠ **两套年份语义的换算只此一处**：
/// - 选择器（以及课表 / 成绩页）的年份 = 学年的**开始**年 —— 高亮对渲染成
///   `initialYear - initialYear + 1`，且 `academic_year_picker.dart` 的
///   `_maxOffset => _offsetOf(endYear - 1)` 要求 `initialYear ≤ endYear - 1`；
/// - 综测内部一律用学年的**结束**年（[zcYearLabel]、`manual-<结束年>`、
///   `zcAutoXxxProvider(yearEnd)`）。
///
/// 此前 `zongce_screen.dart` 直接把结束年当选择器年份传，于是：高亮对的右半边
/// （`+1`）落在 `endYear` 之外、**列表里根本没有那一项**，尺寸也越过了
/// `_maxOffset`（用户 2026-09-27 报：「综测页顶部的学年选择范围有误，今年是
/// 2026-2027 学年，但是顶部只显示到了 2026，实际应该显示到 2027 的文本」）。
///
/// [latestEnd] = 最新可选测评学年的结束年（= [zcDefaultYear]）；
/// [yearEnd] = 当前选中的测评学年（结束年）；
/// [window] = 往前可回溯的学年数（默认 5）。
/// 返回的 `endYear` 比最新学年多一格，**配对才有右半边**（如 2026-2027）。
({int startYear, int endYear, int initialYear}) zcYearPickerRange({
  required int latestEnd,
  required int yearEnd,
  int window = 5,
}) {
  final startYear = latestEnd - window;
  return (
    startYear: startYear,
    endYear: latestEnd + 1,
    initialYear: (yearEnd - 1).clamp(startYear, latestEnd),
  );
}

/// 一条加分证明材料。
class ZcMaterial {
  final String id;
  final ZcTypeId typeId;

  /// 名称（竞赛/论文/荣誉称号名等）。
  final String name;

  /// 发生日期 yyyy-MM-dd（证书盖章时间，决定归属学年）。
  final String dateIso;

  /// 发证/组织单位。
  final String org;

  /// 竞赛类别 c1~c4（needCat 类型自动识别结果；可手动改）。
  final String cat;

  /// 下拉一索引（级别/档位/类型）。
  final int level;

  /// 下拉二索引（奖次/作者序/考核/角色）。
  final int opt;

  /// 次数型（思想教育参与度）。
  final double qty;

  /// 手动填写的得分（用户 2026-09-17：外语按证书名目 + 手填分数）。
  /// 仅 [ZcTypeSpec.manualScore] 为真的类型使用；null = 回退表内档位（旧数据兼容）。
  final double? manualScore;

  /// 附件相对文件名列表（存于应用材料目录）。
  final List<String> files;

  final String note;

  const ZcMaterial({
    required this.id,
    required this.typeId,
    this.name = '',
    this.dateIso = '',
    this.org = '',
    this.cat = '',
    this.level = 0,
    this.opt = 0,
    this.qty = 0,
    this.manualScore,
    this.files = const [],
    this.note = '',
  });

  /// 材料是否落在测评学年窗口内（空日期视为不属于任何学年 → 归入用户当前所选学年由调用方处理）。
  DateTime? get date {
    if (dateIso.isEmpty) return null;
    return DateTime.tryParse(dateIso);
  }

  ZcTypeSpec get spec => zcTypeSpecOf[typeId]!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'typeId': typeId.name,
        'name': name,
        'dateIso': dateIso,
        'org': org,
        'cat': cat,
        'level': level,
        'opt': opt,
        'qty': qty,
        'manualScore': manualScore,
        'files': files,
        'note': note,
      };

  factory ZcMaterial.fromJson(Map<String, dynamic> json) => ZcMaterial(
        id: json['id'] as String? ?? '',
        typeId: ZcTypeId.values.asNameMap()[json['typeId']] ??
            ZcTypeId.contest,
        name: json['name'] as String? ?? '',
        dateIso: json['dateIso'] as String? ?? '',
        org: json['org'] as String? ?? '',
        cat: json['cat'] as String? ?? '',
        level: json['level'] as int? ?? 0,
        opt: json['opt'] as int? ?? 0,
        qty: (json['qty'] as num?)?.toDouble() ?? 0,
        manualScore: (json['manualScore'] as num?)?.toDouble(),
        files: [for (final f in (json['files'] as List?) ?? const []) '$f'],
        note: json['note'] as String? ?? '',
      );

  ZcMaterial copyWith({
    String? id,
    ZcTypeId? typeId,
    String? name,
    String? dateIso,
    String? org,
    String? cat,
    int? level,
    int? opt,
    double? qty,
    /// 传函数才能把值改回 null（`copyWith(manualScore: () => null)`）。
    double? Function()? manualScore,
    List<String>? files,
    String? note,
  }) =>
      ZcMaterial(
        id: id ?? this.id,
        typeId: typeId ?? this.typeId,
        name: name ?? this.name,
        dateIso: dateIso ?? this.dateIso,
        org: org ?? this.org,
        cat: cat ?? this.cat,
        level: level ?? this.level,
        opt: opt ?? this.opt,
        qty: qty ?? this.qty,
        manualScore: manualScore == null ? this.manualScore : manualScore(),
        files: files ?? this.files,
        note: note ?? this.note,
      );

  /// 列表展示名。
  String get displayName => name.isEmpty ? spec.label : name;

  /// 行内辅助描述（档位标签；外语按证书 + 表 10 档位显示，如 `大学英语四级 489 → 1 分`）。
  String get optionLabel {
    final s = spec;
    if (s.id == ZcTypeId.foreign) {
      return zcForeignScoreLabel(name: name, rawScore: manualScore);
    }
    final lvl = s.levels.isNotEmpty && level >= 0 && level < s.levels.length
        ? s.levels[level]
        : '';
    final op = s.opts.isNotEmpty && opt >= 0 && opt < s.opts.length
        ? s.opts[opt]
        : '';
    return [lvl, op].where((x) => x.isNotEmpty).join(' · ');
  }
}

/// 学期输入区手动项（评议/体测/扣分/排名等班级评议相关；自动可取的项留 null 用自动值）。
class ZcManual {
  // ---- 德育 ----
  final double deyuPingyi; // 民主评议 0~20（预估）
  final int kouQk; // 无故缺课 节（×2）
  final int kouHd; // 缺席重大集体活动 次（×1）
  final int kouCf; // 违纪处分档位 0=无 1=学院通报(2) 2=学校警告(5) 3=严重警告(10)
  final bool vetoD; // 德育一票否决
  // ---- 智育 ----
  final double? weight; // 加权成绩覆盖（null=用自动加权）
  final int kouZhiyu; // 无故不参加实习实训/课外学术创新 次（×3）
  final bool tuixue; // 受退学警告/毕业未获资格
  final bool guaKe; // 测评年度有挂科
  // ---- 体育 ----
  final bool tMian; // 体测免测
  final double tScore; // 体测成绩 0~100（免测时按 60）
  final int tKou1; // 体育活动中当众扰乱秩序 次（×5）
  final int tKou2; // 参赛无故弃权/退场 次（×2）
  // ---- 美育 ----
  final double meiyuPingyi; // 民主评议 0~20
  final int mKou1; // 文艺活动扰乱秩序 次（×1）
  final int mKou2; // 艺术团未满服务期退团（×2，一次性）
  final int mKou3; // 文艺比赛弃权/退场 次（×5）
  // ---- 劳育 ----
  final double laoyuPingyi; // 民主评议 0~20
  final int lKou1; // 未参加劳育活动 次（×1）
  final bool lKou2; // 大学期间未参加实习实训（×2）
  final bool lKou3; // 寝室卫生通报·院级（×2）
  final bool lKou4; // 寝室卫生通报·校级（×4）
  final double? volunteerHours; // 本学年志愿时长覆盖（null=用第二课堂自动累计）
  // ---- 排名（五育各自档位，班级评议后填） ----
  final ZcRank rankD, rankZ, rankT, rankM, rankL;

  /// 五育占比（总评成绩口径；用户 2026-09-18 拍板「占比由班主任定，让用户自行
  /// 设置」）——**按学年各存一套**（本对象就是按学年落盘的 `manual-<yearEnd>`），
  /// 默认 `20/35/15/15/15`。明细见 `zc_weights.dart`。
  final ZcWeights weights;

  /// 「放开所有累加」开关（用户 2026-09-27：「我们希望增加一个综测开关
  /// 『是否放开所有累加』的按钮」）——口径照学校《评优评先综测计算器》与标准版
  /// 在累加上的差别：**所有「就高一次」改多项叠加、所有附加分封顶取消**
  /// （附加合计 20 / 荣誉合计 10 / 院级媒体 10 / 竞赛 5 / 论文单篇 1.5 与合计 5 /
  /// 参与度 2）；**民主评议仍封顶 20、扣分项照旧、等次评定与一票否决不变**。
  /// 与占比一样**按学年各存一套**（本对象即 `manual-<测评学年结束年>`）。
  final bool openAccumulate;

  const ZcManual({
    this.deyuPingyi = 0,
    this.kouQk = 0,
    this.kouHd = 0,
    this.kouCf = 0,
    this.vetoD = false,
    this.weight,
    this.kouZhiyu = 0,
    this.tuixue = false,
    this.guaKe = false,
    this.tMian = false,
    this.tScore = 60,
    this.tKou1 = 0,
    this.tKou2 = 0,
    this.meiyuPingyi = 0,
    this.mKou1 = 0,
    this.mKou2 = 0,
    this.mKou3 = 0,
    this.laoyuPingyi = 0,
    this.lKou1 = 0,
    this.lKou2 = false,
    this.lKou3 = false,
    this.lKou4 = false,
    this.volunteerHours,
    this.rankD = ZcRank.unknown,
    this.rankZ = ZcRank.unknown,
    this.rankT = ZcRank.unknown,
    this.rankM = ZcRank.unknown,
    this.rankL = ZcRank.unknown,
    this.weights = ZcWeights.initial,
    this.openAccumulate = false,
  });

  Map<String, dynamic> toJson() => {
        'deyuPingyi': deyuPingyi,
        'kouQk': kouQk,
        'kouHd': kouHd,
        'kouCf': kouCf,
        'vetoD': vetoD,
        'weight': weight,
        'kouZhiyu': kouZhiyu,
        'tuixue': tuixue,
        'guaKe': guaKe,
        'tMian': tMian,
        'tScore': tScore,
        'tKou1': tKou1,
        'tKou2': tKou2,
        'meiyuPingyi': meiyuPingyi,
        'mKou1': mKou1,
        'mKou2': mKou2,
        'mKou3': mKou3,
        'laoyuPingyi': laoyuPingyi,
        'lKou1': lKou1,
        'lKou2': lKou2,
        'lKou3': lKou3,
        'lKou4': lKou4,
        'volunteerHours': volunteerHours,
        'rankD': rankD.name,
        'rankZ': rankZ.name,
        'rankT': rankT.name,
        'rankM': rankM.name,
        'rankL': rankL.name,
        'weights': weights.toJson(),
        'openAccumulate': openAccumulate,
      };

  factory ZcManual.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ZcManual();
    ZcRank rank(String k) =>
        ZcRank.values.asNameMap()[json[k]] ?? ZcRank.unknown;
    return ZcManual(
      deyuPingyi: (json['deyuPingyi'] as num?)?.toDouble() ?? 0,
      kouQk: json['kouQk'] as int? ?? 0,
      kouHd: json['kouHd'] as int? ?? 0,
      kouCf: json['kouCf'] as int? ?? 0,
      vetoD: json['vetoD'] as bool? ?? false,
      weight: (json['weight'] as num?)?.toDouble(),
      kouZhiyu: json['kouZhiyu'] as int? ?? 0,
      tuixue: json['tuixue'] as bool? ?? false,
      guaKe: json['guaKe'] as bool? ?? false,
      tMian: json['tMian'] as bool? ?? false,
      tScore: (json['tScore'] as num?)?.toDouble() ?? 60,
      tKou1: json['tKou1'] as int? ?? 0,
      tKou2: json['tKou2'] as int? ?? 0,
      meiyuPingyi: (json['meiyuPingyi'] as num?)?.toDouble() ?? 0,
      mKou1: json['mKou1'] as int? ?? 0,
      mKou2: json['mKou2'] as int? ?? 0,
      mKou3: json['mKou3'] as int? ?? 0,
      laoyuPingyi: (json['laoyuPingyi'] as num?)?.toDouble() ?? 0,
      lKou1: json['lKou1'] as int? ?? 0,
      lKou2: json['lKou2'] as bool? ?? false,
      lKou3: json['lKou3'] as bool? ?? false,
      lKou4: json['lKou4'] as bool? ?? false,
      volunteerHours: (json['volunteerHours'] as num?)?.toDouble(),
      rankD: rank('rankD'),
      rankZ: rank('rankZ'),
      rankT: rank('rankT'),
      rankM: rank('rankM'),
      rankL: rank('rankL'),
      // 旧数据没有这一项 → 回落默认档（20/35/15/15/15）。
      weights: ZcWeights.fromJson(json['weights']),
      // 旧数据没有这一项 → 标准档（不放开累加）。
      openAccumulate: json['openAccumulate'] as bool? ?? false,
    );
  }

  ZcManual copyWith({
    double? deyuPingyi,
    int? kouQk,
    int? kouHd,
    int? kouCf,
    bool? vetoD,
    double? Function()? weight,
    int? kouZhiyu,
    bool? tuixue,
    bool? guaKe,
    bool? tMian,
    double? tScore,
    int? tKou1,
    int? tKou2,
    double? meiyuPingyi,
    int? mKou1,
    int? mKou2,
    int? mKou3,
    double? laoyuPingyi,
    int? lKou1,
    bool? lKou2,
    bool? lKou3,
    bool? lKou4,
    double? Function()? volunteerHours,
    ZcRank? rankD,
    ZcRank? rankZ,
    ZcRank? rankT,
    ZcRank? rankM,
    ZcRank? rankL,
    ZcWeights? weights,
    bool? openAccumulate,
  }) =>
      ZcManual(
        deyuPingyi: deyuPingyi ?? this.deyuPingyi,
        kouQk: kouQk ?? this.kouQk,
        kouHd: kouHd ?? this.kouHd,
        kouCf: kouCf ?? this.kouCf,
        vetoD: vetoD ?? this.vetoD,
        weight: weight != null ? weight() : this.weight,
        kouZhiyu: kouZhiyu ?? this.kouZhiyu,
        tuixue: tuixue ?? this.tuixue,
        guaKe: guaKe ?? this.guaKe,
        tMian: tMian ?? this.tMian,
        tScore: tScore ?? this.tScore,
        tKou1: tKou1 ?? this.tKou1,
        tKou2: tKou2 ?? this.tKou2,
        meiyuPingyi: meiyuPingyi ?? this.meiyuPingyi,
        mKou1: mKou1 ?? this.mKou1,
        mKou2: mKou2 ?? this.mKou2,
        mKou3: mKou3 ?? this.mKou3,
        laoyuPingyi: laoyuPingyi ?? this.laoyuPingyi,
        lKou1: lKou1 ?? this.lKou1,
        lKou2: lKou2 ?? this.lKou2,
        lKou3: lKou3 ?? this.lKou3,
        lKou4: lKou4 ?? this.lKou4,
        volunteerHours:
            volunteerHours != null ? volunteerHours() : this.volunteerHours,
        rankD: rankD ?? this.rankD,
        rankZ: rankZ ?? this.rankZ,
        rankT: rankT ?? this.rankT,
        rankM: rankM ?? this.rankM,
        rankL: rankL ?? this.rankL,
        weights: weights ?? this.weights,
        openAccumulate: openAccumulate ?? this.openAccumulate,
      );
}

/// 材料清单序列化。
String zcMaterialsJson(List<ZcMaterial> list) =>
    jsonEncode([for (final m in list) m.toJson()]);

List<ZcMaterial> zcMaterialsFromJson(String? s) {
  if (s == null || s.isEmpty) return [];
  final raw = jsonDecode(s);
  if (raw is! List) return [];
  return [
    for (final e in raw)
      if (e is Map<String, dynamic>) ZcMaterial.fromJson(e),
  ];
}
