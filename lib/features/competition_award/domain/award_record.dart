/// 竞赛奖励模块 —— 用户登记的获奖记录模型。
///
/// 与「目录」(`competition_catalog.dart`) 分开：目录是资料库解析出的**可选清单**，
/// 这里是用户自己登记的获奖（随账号存 Hive，见 `competition_award_store.dart`）。
///
/// [adjustment] 对应办法第九条的两个折减口径（原话）：
/// - 「中国国际大学生创新大赛国际项目按标准的 70% 奖励」；
/// - 「挑战杯主体赛道外的其他赛道项目获奖按Ⅱ类竞赛标准奖励」。
library;

import 'competition_catalog.dart';
import 'award_standard.dart';

/// 奖励折减 / 改口径方式（见文件头）。
enum AwardAdjustment {
  none('按标准'),
  international70('国际项目按 70%'),
  nonMainTrackAsClassII('非主体赛道按Ⅱ类标准');

  const AwardAdjustment(this.label);

  final String label;

  static AwardAdjustment parse(Object? raw) {
    if (raw is! String) return AwardAdjustment.none;
    for (final a in AwardAdjustment.values) {
      if (a.name == raw) return a;
    }
    return AwardAdjustment.none;
  }
}

/// 一条竞赛获奖记录。
class CompetitionAwardRecord {
  final String id;

  /// 竞赛名称（从目录里选，也允许手填）。
  final String competitionName;

  final CompetitionClass klass;

  /// 获奖等次（Ⅰ类 = 特等奖（金奖）/一等奖（银奖）…；Ⅱ/Ⅲ类 = 第一/二/三等次）。
  final String tierLabel;

  final AwardScope scope;

  /// 获奖日期；null = 未填（选了时间范围时不会计入，见 `award_calc.dart`）。
  final DateTime? date;

  /// 第十条条件：「若赛事设特等奖，则特等奖对应一等奖、一等奖对应二等奖并依此类推」——
  /// 该赛事是否设特等奖（Ⅱ/Ⅲ类折算时用）。
  final bool hasSpecialTier;

  final AwardAdjustment adjustment;

  /// 目录版本（登记时的出处，如 `2025-2026 年`）。
  final String? edition;

  final String? note;

  const CompetitionAwardRecord({
    required this.id,
    required this.competitionName,
    required this.klass,
    required this.tierLabel,
    required this.scope,
    this.date,
    this.hasSpecialTier = false,
    this.adjustment = AwardAdjustment.none,
    this.edition,
    this.note,
  });

  CompetitionAwardRecord copyWith({
    String? competitionName,
    CompetitionClass? klass,
    String? tierLabel,
    AwardScope? scope,
    DateTime? date,
    bool clearDate = false,
    bool? hasSpecialTier,
    AwardAdjustment? adjustment,
    String? edition,
    String? note,
  }) => CompetitionAwardRecord(
    id: id,
    competitionName: competitionName ?? this.competitionName,
    klass: klass ?? this.klass,
    tierLabel: tierLabel ?? this.tierLabel,
    scope: scope ?? this.scope,
    date: clearDate ? null : (date ?? this.date),
    hasSpecialTier: hasSpecialTier ?? this.hasSpecialTier,
    adjustment: adjustment ?? this.adjustment,
    edition: edition ?? this.edition,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'competitionName': competitionName,
    'klass': klass.name,
    'tierLabel': tierLabel,
    'scope': scope.name,
    if (date != null) 'date': date!.toIso8601String(),
    'hasSpecialTier': hasSpecialTier,
    'adjustment': adjustment.name,
    if (edition != null) 'edition': edition,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  static CompetitionAwardRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['competitionName'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    CompetitionClass? klass;
    for (final k in CompetitionClass.values) {
      if (k.name == raw['klass']) {
        klass = k;
        break;
      }
    }
    if (klass == null) return null;
    AwardScope? scope;
    for (final s in AwardScope.values) {
      if (s.name == raw['scope']) {
        scope = s;
        break;
      }
    }
    if (scope == null) return null;
    final tier = raw['tierLabel'];
    final edition = raw['edition'];
    final note = raw['note'];
    final dateRaw = raw['date'];
    return CompetitionAwardRecord(
      id: id,
      competitionName: name,
      klass: klass,
      tierLabel: tier is String ? tier : '',
      scope: scope,
      date: dateRaw is String ? DateTime.tryParse(dateRaw) : null,
      hasSpecialTier: raw['hasSpecialTier'] == true,
      adjustment: AwardAdjustment.parse(raw['adjustment']),
      edition: edition is String && edition.isNotEmpty ? edition : null,
      note: note is String && note.isNotEmpty ? note : null,
    );
  }

  /// 明细摘要（列表副标题）。
  String get summary {
    final parts = <String>[
      if (tierLabel.isNotEmpty) tierLabel,
      scope.label,
      if (date != null) fmtAwardDate(date!),
      if (adjustment != AwardAdjustment.none) adjustment.label,
    ];
    return parts.join(' · ');
  }

  /// 第十条「同一年度同一作品在同一竞赛不同级别获奖取最高」用的归一键。
  String get yearKey =>
      '${competitionName.replaceAll(RegExp(r'\s+'), '')}@${date?.year ?? 0}';
}

/// `2026-05-26`。
String fmtAwardDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 生成记录 id（时间戳 + 自增）。
String newAwardRecordId([DateTime? now]) =>
    'award-${(now ?? DateTime.now()).microsecondsSinceEpoch}-${_seq++}';

int _seq = 0;
