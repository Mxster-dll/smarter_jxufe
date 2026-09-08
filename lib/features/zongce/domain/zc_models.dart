/// 综测材料与手动输入模型。
library;

import 'dart:convert';

import 'zc_catalog.dart';
import 'zc_rules.dart';

/// 测评学年（结束年编码）：测评学年 [yearEnd] 覆盖窗口
/// 2025-09-01 ~ 2026-08-31（yearEnd=2026），即对上一教学学年的测评。
bool zcYearWindowContains(DateTime d, int yearEnd) {
  final start = DateTime(yearEnd - 1, 9, 1);
  final end = DateTime(yearEnd, 8, 31, 23, 59, 59);
  return !d.isBefore(start) && !d.isAfter(end);
}

/// 默认测评学年：9 月起对刚结束的学年测评（2026-09 → 2025-2026 即 yearEnd 2026）；
/// 1~8 月（测评季尚未到 9 月）默认最近一个已完成学年。
int zcDefaultYear(DateTime now) => now.month >= 9 ? now.year : now.year - 1;

/// 学年窗口 label，如 「2025-2026 学年」。
String zcYearLabel(int yearEnd) => '${yearEnd - 1}-$yearEnd 学年';

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
        files: files ?? this.files,
        note: note ?? this.note,
      );

  /// 列表展示名。
  String get displayName => name.isEmpty ? spec.label : name;

  /// 行内辅助描述（档位标签）。
  String get optionLabel {
    final s = spec;
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
