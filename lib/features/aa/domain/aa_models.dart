/// AA 算账 · 领域模型（纯 Dart，不依赖 Flutter）。
///
/// 立项口径（2026-09-19 · 用户原话「我希望增加一个算账的工具，用于aa。我们可以手动
/// 添加一些开销，每个开销包括名称、金额、需要aa的人员；然后自动计算出每两个人之间的
/// 转钱情况」）：
///
/// - **成员表**（[AaMember]）是一份手工维护的名单，开销只引用成员 `id`
///   → 改名不会断开已有记录；
/// - **每笔开销**（[AaExpense]）= 名称 + 金额 + **付款人（垫付人）** + 参与 AA 的人
///   + 日期；参与人**平分**该笔金额（见 `aa_settlement.dart`）；
/// - 金额一律折成**分**（`int`）参与计算（[aaCentsOf] / [aaMoney]）：浮点累加会在
///   结算里滚出「0.0000001 的欠款」，分账必须分毫不差。
///
/// 容错口径（照 `lib/features/zongce/data/zc_store.dart`）：所有 `fromJson` 一律
/// 「脏数据丢弃 / 缺字段回落默认值」，**绝不让旧数据把页面打崩**。
library;

import 'dart:convert';

/// 取数（容错）：数字 / 数字字符串 → double，其余 → [fallback]。
///
/// ⚠ 不要直接写 `as num?`：脏数据（`"300"`）会抛
/// `type 'String' is not a subtype of type 'num?'`（分数估计模块实测踩过）。
double aaNumOf(Object? v, {double fallback = 0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}

/// 取数（容错）：任意值 → 字符串。
String aaStrOf(Object? v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

/// 取数（容错）：列表 → **去重、去空白**的字符串列表（顺序保留）。
///
/// 去重是必需的：参与人重复会让同一个人被扣两次钱。
List<String> aaStrListOf(Object? v) {
  if (v is! List) return const <String>[];
  final out = <String>[];
  for (final x in v) {
    final s = aaStrOf(x).trim();
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

/// 元 → 分（四舍五入）。
int aaCentsOf(double yuan) => (yuan * 100).round();

/// 分 → 元。
double aaYuanOf(int cents) => cents / 100;

/// 分的显示：`¥12.34`、负的写 `-¥12.34`（不经过浮点拼字符串）。
String aaMoney(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign¥${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// 日期 → `2026-09-19`（AA 记账只到天，不需要时刻）。
String aaDateText(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 去掉时分秒（同一天的记录恒等，便于比较）。
DateTime aaDay(DateTime d) => DateTime(d.year, d.month, d.day);

Object? _aaDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

/// 一位参与 AA 的人。
///
/// [studentNo] / [className]（2026-09-19 五轮加）是**纯展示**用的附加标识：
/// 用户原话「我希望成员可以显示学号和班级」—— 一屋子人里重名的不少（AA 名单只按
/// 姓名去重），把学号/班级写在名字下面就再也认不错人。它们**不参与任何计算，
/// 也不是去重键**（去重仍然只按姓名，见 `aa_import.dart`），老数据没有这两个字段
/// → 空串，界面按「没有就不显示」处理。
class AaMember {
  final String id;

  /// 显示名（可改，引用只认 [id]）。
  final String name;

  /// 学号（= 数据中心名单里的「校园卡号」/ `ykth`）。空串 = 没填。
  final String studentNo;

  /// 班级（如「25计算机2班」）。空串 = 没填。
  final String className;

  const AaMember({
    required this.id,
    required this.name,
    this.studentNo = '',
    this.className = '',
  });

  /// 附加标识行：`2202500004 · 25计算机2班`（两者都没有 → 空串）。
  String get detail =>
      [studentNo, className].where((s) => s.isNotEmpty).join(' · ');

  AaMember copyWith({
    String? id,
    String? name,
    String? studentNo,
    String? className,
  }) => AaMember(
    id: id ?? this.id,
    name: name ?? this.name,
    studentNo: studentNo ?? this.studentNo,
    className: className ?? this.className,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (studentNo.isNotEmpty) 'studentNo': studentNo,
    if (className.isNotEmpty) 'className': className,
  };

  /// 容错：非 Map / 无 id → null（整条丢弃）；学号/班级脏数据 → 空串。
  static AaMember? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = aaStrOf(raw['id']).trim();
    if (id.isEmpty) return null;
    final name = aaStrOf(raw['name']).trim();
    return AaMember(
      id: id,
      name: name.isEmpty ? '未命名' : name,
      studentNo: aaStrOf(raw['studentNo']).trim(),
      className: aaStrOf(raw['className']).trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AaMember &&
      other.id == id &&
      other.name == name &&
      other.studentNo == studentNo &&
      other.className == className;

  @override
  int get hashCode => Object.hash(id, name, studentNo, className);

  @override
  String toString() => 'AaMember($id, $name, $studentNo, $className)';
}

/// 一笔开销。
class AaExpense {
  final String id;

  /// 名称（如「聚餐」「打车」）。
  final String title;

  /// 金额（**元**；参与计算时一律走 [amountCents]）。
  final double amount;

  /// 付款人（垫付人）的成员 id。
  final String payerId;

  /// 参与 AA 的成员 id（**平分**这笔金额）。
  final List<String> participantIds;

  /// 记账日期（只到天）。
  final DateTime date;

  /// 创建时刻（同一天内排序用）。
  final DateTime createdAt;

  const AaExpense({
    required this.id,
    required this.title,
    required this.amount,
    required this.payerId,
    required this.participantIds,
    required this.date,
    required this.createdAt,
  });

  /// 金额（分）—— 一切结算口径都用它。
  int get amountCents => aaCentsOf(amount);

  AaExpense copyWith({
    String? id,
    String? title,
    double? amount,
    String? payerId,
    List<String>? participantIds,
    DateTime? date,
    DateTime? createdAt,
  }) => AaExpense(
    id: id ?? this.id,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    payerId: payerId ?? this.payerId,
    participantIds: participantIds ?? this.participantIds,
    date: date ?? this.date,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'payerId': payerId,
    'participantIds': participantIds,
    'date': aaDateText(date),
    'createdAt': createdAt.toIso8601String(),
  };

  /// 容错：非 Map / 无 id → null；金额非数或 ≤ 0 → 0（该笔不产生任何分摊）；
  /// 日期坏了 → 今天；参与人不是列表 → 空。
  static AaExpense? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = aaStrOf(raw['id']).trim();
    if (id.isEmpty) return null;
    final title = aaStrOf(raw['title']).trim();
    final amount = aaNumOf(raw['amount']);
    final date = DateTime.tryParse(aaStrOf(raw['date'])) ?? DateTime.now();
    return AaExpense(
      id: id,
      title: title.isEmpty ? '未命名开销' : title,
      amount: amount.isFinite && amount > 0 ? amount : 0,
      payerId: aaStrOf(raw['payerId']).trim(),
      participantIds: aaStrListOf(raw['participantIds']),
      date: aaDay(date),
      createdAt: DateTime.tryParse(aaStrOf(raw['createdAt'])) ?? date,
    );
  }
}

/// 整表序列化：成员。
String aaMembersJson(List<AaMember> list) =>
    jsonEncode([for (final m in list) m.toJson()]);

/// 整表反序列化：成员（坏数据整体 → 空表，单条坏 → 丢那一条）。
List<AaMember> aaMembersFromJson(String raw) {
  final decoded = _aaDecode(raw);
  if (decoded is! List) return const <AaMember>[];
  final out = <AaMember>[];
  for (final x in decoded) {
    final m = AaMember.fromJson(x);
    if (m != null) out.add(m);
  }
  return out;
}

/// 整表序列化：开销。
String aaExpensesJson(List<AaExpense> list) =>
    jsonEncode([for (final e in list) e.toJson()]);

/// 整表反序列化：开销。
List<AaExpense> aaExpensesFromJson(String raw) {
  final decoded = _aaDecode(raw);
  if (decoded is! List) return const <AaExpense>[];
  final out = <AaExpense>[];
  for (final x in decoded) {
    final e = AaExpense.fromJson(x);
    if (e != null) out.add(e);
  }
  return out;
}

/// 开销列表的展示顺序：**日期倒序 → 创建时刻倒序 → id 升序兜底**（`List.sort`
/// 不稳定，同键时不加兜底会出现「每次刷新顺序都不一样」）。
List<AaExpense> aaSortedExpenses(List<AaExpense> list) {
  final out = [...list];
  out.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final byCreated = b.createdAt.compareTo(a.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  });
  return out;
}
