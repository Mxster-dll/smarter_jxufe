/// 推免成绩模块 —— 用户登记的加分项模型。
///
/// 与「目录」(`bonus_catalog.dart`) 分开：目录是**资料库解析出来的可选清单**，
/// 这里是**用户自己勾选/登记的条目**（随账号存 Hive，见 `recommendation_store.dart`）。
/// 条目里冗余保存 [optionLabel] / [tierLabel]，因此资料库更新后旧记录仍能原样显示
/// （只有重新计算分值时才会提示「项目已不在最新标准里」）。
library;

import 'bonus_catalog.dart';

/// 一条加分项。
class RecommendationBonusItem {
  final String id;

  final BonusCategory category;

  /// 目录里的选项 id（`contest#1` 这类）；资料库改版后可能失效。
  final String optionId;

  /// 记录当时的项目名（赛项名称 / 专利级别 / 荣誉名称 / 论文类别）。
  final String optionLabel;

  /// 获奖等级（竞赛类必填；专利类是「级别」文字由 optionLabel 承载）。
  final String? tierLabel;

  /// 竞赛类排名（1 起）；null = 未填，按第 1 名计并给出提示。
  final int? rank;

  /// 获奖 / 取得日期（竞赛类用于 2025-01-01 新旧规则分界）。
  final DateTime? awardDate;

  final String? note;

  const RecommendationBonusItem({
    required this.id,
    required this.category,
    required this.optionId,
    required this.optionLabel,
    this.tierLabel,
    this.rank,
    this.awardDate,
    this.note,
  });

  RecommendationBonusItem copyWith({
    String? optionId,
    String? optionLabel,
    String? tierLabel,
    int? rank,
    DateTime? awardDate,
    bool clearRank = false,
    bool clearAwardDate = false,
    String? note,
  }) => RecommendationBonusItem(
    id: id,
    category: category,
    optionId: optionId ?? this.optionId,
    optionLabel: optionLabel ?? this.optionLabel,
    tierLabel: tierLabel ?? this.tierLabel,
    rank: clearRank ? null : (rank ?? this.rank),
    awardDate: clearAwardDate ? null : (awardDate ?? this.awardDate),
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'optionId': optionId,
    'optionLabel': optionLabel,
    if (tierLabel != null) 'tierLabel': tierLabel,
    if (rank != null) 'rank': rank,
    if (awardDate != null) 'awardDate': awardDate!.toIso8601String(),
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  /// 容错解析：脏数据（类型不对 / 类别名认不出）一律跳过该条，不让旧数据崩页面。
  static RecommendationBonusItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final categoryName = raw['category'];
    final optionId = raw['optionId'];
    if (id is! String || id.isEmpty) return null;
    if (optionId is! String) return null;
    BonusCategory? category;
    for (final c in BonusCategory.values) {
      if (c.name == categoryName) {
        category = c;
        break;
      }
    }
    if (category == null) return null;
    final label = raw['optionLabel'];
    final rankRaw = raw['rank'];
    final dateRaw = raw['awardDate'];
    final note = raw['note'];
    final tierLabel = raw['tierLabel'];
    return RecommendationBonusItem(
      id: id,
      category: category,
      optionId: optionId,
      optionLabel: label is String ? label : '',
      tierLabel: tierLabel is String && tierLabel.isNotEmpty ? tierLabel : null,
      rank: rankRaw is int
          ? rankRaw
          : (rankRaw is num ? rankRaw.toInt() : null),
      awardDate: dateRaw is String ? DateTime.tryParse(dateRaw) : null,
      note: note is String && note.isNotEmpty ? note : null,
    );
  }

  /// 条目摘要（列表副标题用）。
  String get summary {
    final parts = <String>[];
    if (tierLabel != null && tierLabel!.isNotEmpty) parts.add(tierLabel!);
    if (rank != null) parts.add('排名第 $rank');
    if (awardDate != null) parts.add(_fmtDate(awardDate!));
    return parts.isEmpty ? '未填写获奖信息' : parts.join(' · ');
  }

  @override
  String toString() =>
      'RecommendationBonusItem(${category.name}, $optionLabel, '
      'tier=$tierLabel, rank=$rank, date=$awardDate)';
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 生成条目 id（时间戳 + 自增，足够唯一且无需依赖 uuid 包）。
String newRecommendationItemId([DateTime? now]) {
  final t = (now ?? DateTime.now()).microsecondsSinceEpoch;
  return 'rec-$t-${_seq++}';
}

int _seq = 0;
