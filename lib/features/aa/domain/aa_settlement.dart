/// AA 结算引擎（纯函数：无 Flutter、无存储、无 provider）。
///
/// 口径：
/// 1. **平分**：一笔开销由参与人平分，除不尽的分按参与人顺序**依次每人多 1 分**
///    → 份额之和恒等于金额（分毫不差，见 [aaSplitExpense]）；
/// 2. **净额**：每人「垫付合计 − 应分摊合计」= [AaBalance.netCents]，
///    正 = 别人欠他（应收），负 = 他欠别人（应付）；所有人净额之和恒为 0；
/// 3. **最少笔数转账**：最大债权人 ↔ 最大债务人贪心配对（[aaSettleTransfers]）——
///    每轮至少清零一个人，笔数 ≤ 债权人数 + 债务人数 − 1；「一人垫付、众人还」
///    这类真实场景直接出 1 笔。
library;

import 'aa_models.dart';

/// 一笔开销里某位参与人该分摊的份额（**分**）。
class AaShare {
  final String memberId;
  final int cents;

  const AaShare(this.memberId, this.cents);

  @override
  bool operator ==(Object other) =>
      other is AaShare && other.memberId == memberId && other.cents == cents;

  @override
  int get hashCode => Object.hash(memberId, cents);

  @override
  String toString() => 'AaShare($memberId, $cents)';
}

/// 某位成员在整份账里的收支（**全是分**）。
class AaBalance {
  final String memberId;

  /// 垫付合计。
  final int paidCents;

  /// 应分摊合计。
  final int shareCents;

  /// 垫付笔数。
  final int paidCount;

  /// 作为参与人分摊的笔数。
  final int joinCount;

  const AaBalance({
    required this.memberId,
    required this.paidCents,
    required this.shareCents,
    this.paidCount = 0,
    this.joinCount = 0,
  });

  /// 净额：**正 = 应收**（别人欠他），**负 = 应付**（他欠别人）。
  int get netCents => paidCents - shareCents;
}

/// 一笔转账：`fromId` 要付给 `toId` 多少（分）。
class AaTransfer {
  final String fromId;
  final String toId;
  final int cents;

  const AaTransfer({
    required this.fromId,
    required this.toId,
    required this.cents,
  });

  @override
  bool operator ==(Object other) =>
      other is AaTransfer &&
      other.fromId == fromId &&
      other.toId == toId &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(fromId, toId, cents);

  @override
  String toString() => 'AaTransfer($fromId → $toId, $cents)';
}

/// 整份账的结算结果。
class AaSettlement {
  /// 与成员表同序的每人收支。
  final List<AaBalance> balances;

  /// 最少笔数的转账清单。
  final List<AaTransfer> transfers;

  /// 计入结算的开销合计（**分**）。
  final int totalCents;

  /// 计入结算的开销笔数。
  final int expenseCount;

  const AaSettlement({
    required this.balances,
    required this.transfers,
    required this.totalCents,
    required this.expenseCount,
  });

  static const AaSettlement empty = AaSettlement(
    balances: <AaBalance>[],
    transfers: <AaTransfer>[],
    totalCents: 0,
    expenseCount: 0,
  );

  /// 无需任何转账（没账，或净额全为 0）。
  bool get settled => transfers.isEmpty;

  /// 应收的人（净额 > 0）。
  List<AaBalance> get creditors =>
      [for (final b in balances) if (b.netCents > 0) b];

  /// 应付的人（净额 < 0）。
  List<AaBalance> get debtors =>
      [for (final b in balances) if (b.netCents < 0) b];
}

/// 单笔开销在**已知成员**之间的平分明细。
///
/// - 参与的成员 = `expense.participantIds` ∩ `known`，顺序照原样（已去重）；
/// - 余数（除不尽的分）按该顺序**依次每人多 1 分** → 份额之和恒等于金额；
/// - 一个已知参与人都没有，或金额 ≤ 0 → 空（该笔整笔不计入结算）。
List<AaShare> aaSplitExpense(AaExpense e, {required Set<String> known}) {
  final ids = <String>[
    for (final id in e.participantIds)
      if (known.contains(id)) id,
  ];
  final cents = e.amountCents;
  if (ids.isEmpty || cents <= 0) return const <AaShare>[];
  final base = cents ~/ ids.length;
  final rem = cents % ids.length;
  return <AaShare>[
    for (var i = 0; i < ids.length; i++)
      AaShare(ids[i], i < rem ? base + 1 : base),
  ];
}

/// 贪心配对：最大债权人 ↔ 最大债务人，一次抹平较小的一方。
///
/// 「最少转账笔数」的**精确最优是 NP-hard**，贪心是业界通行解法：每轮至少清零一个人
/// → 笔数 ≤ 债权人数 + 债务人数 − 1，且对「一借多还 / 多借一还」已经是 1 笔。
///
/// [order] = 成员顺序，**用于同额时的确定性**（金额相同 → 名单靠前者优先），
/// 否则同样的数据可能给出不同的转账清单。
List<AaTransfer> aaSettleTransfers({
  required List<String> order,
  required Map<String, int> netCents,
}) {
  final creditors = <_AaNode>[];
  final debtors = <_AaNode>[];
  for (var i = 0; i < order.length; i++) {
    final v = netCents[order[i]] ?? 0;
    if (v > 0) {
      creditors.add(_AaNode(order[i], v, i));
    } else if (v < 0) {
      debtors.add(_AaNode(order[i], -v, i));
    }
  }
  creditors.sort(_aaNodeDesc);
  debtors.sort(_aaNodeDesc);

  final out = <AaTransfer>[];
  var i = 0;
  var j = 0;
  while (i < creditors.length && j < debtors.length) {
    final pay = creditors[i].cents < debtors[j].cents
        ? creditors[i].cents
        : debtors[j].cents;
    if (pay > 0) {
      out.add(
        AaTransfer(fromId: debtors[j].id, toId: creditors[i].id, cents: pay),
      );
    }
    creditors[i].cents -= pay;
    debtors[j].cents -= pay;
    if (creditors[i].cents == 0) i++;
    if (debtors[j].cents == 0) j++;
  }
  return out;
}

int _aaNodeDesc(_AaNode a, _AaNode b) =>
    a.cents != b.cents ? b.cents - a.cents : a.index - b.index;

class _AaNode {
  final String id;
  int cents;
  final int index;

  _AaNode(this.id, this.cents, this.index);
}

/// 整份账的结算：每人净额 + 最少笔数转账。
///
/// **只有成员表里存在的人参与结算**——成员被删后就从分摊里消失、其余人重新平分
/// （与成员页删除时的提示一致）；**找不到付款人的开销整笔跳过**（谁垫的都不知道，
/// 计进去只会凭空造出一笔欠款）。这两条保证「所有人净额之和恒为 0」始终成立。
AaSettlement aaSettle({
  required List<AaMember> members,
  required List<AaExpense> expenses,
}) {
  if (members.isEmpty) return AaSettlement.empty;
  final known = <String>{for (final m in members) m.id};
  final paid = <String, int>{for (final m in members) m.id: 0};
  final share = <String, int>{for (final m in members) m.id: 0};
  final paidCount = <String, int>{for (final m in members) m.id: 0};
  final joinCount = <String, int>{for (final m in members) m.id: 0};

  var total = 0;
  var count = 0;
  for (final e in expenses) {
    if (!known.contains(e.payerId)) continue;
    final shares = aaSplitExpense(e, known: known);
    if (shares.isEmpty) continue;
    final cents = e.amountCents;
    paid[e.payerId] = paid[e.payerId]! + cents;
    paidCount[e.payerId] = paidCount[e.payerId]! + 1;
    for (final s in shares) {
      share[s.memberId] = share[s.memberId]! + s.cents;
      joinCount[s.memberId] = joinCount[s.memberId]! + 1;
    }
    total += cents;
    count += 1;
  }

  final balances = <AaBalance>[
    for (final m in members)
      AaBalance(
        memberId: m.id,
        paidCents: paid[m.id]!,
        shareCents: share[m.id]!,
        paidCount: paidCount[m.id]!,
        joinCount: joinCount[m.id]!,
      ),
  ];
  return AaSettlement(
    balances: balances,
    transfers: aaSettleTransfers(
      order: [for (final m in members) m.id],
      netCents: {for (final b in balances) b.memberId: b.netCents},
    ),
    totalCents: total,
    expenseCount: count,
  );
}

/// 页面一次性拿到的整份数据（成员 + 开销 + 结算结果）。
class AaData {
  final List<AaMember> members;
  final List<AaExpense> expenses;
  final AaSettlement settlement;

  const AaData({
    required this.members,
    required this.expenses,
    required this.settlement,
  });

  static const AaData empty = AaData(
    members: <AaMember>[],
    expenses: <AaExpense>[],
    settlement: AaSettlement.empty,
  );

  /// 由成员与开销算出整份数据（**结算的唯一入口**，界面层别自己拼口径）。
  static AaData of({
    required List<AaMember> members,
    required List<AaExpense> expenses,
  }) => AaData(
    members: members,
    expenses: expenses,
    settlement: aaSettle(members: members, expenses: expenses),
  );

  AaMember? memberOf(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 成员显示名；引用已删除的成员时给一个能看懂的占位。
  String nameOf(String id) => memberOf(id)?.name ?? '（已删除）';

  /// 成员的**学号 · 班级**标识行（用户 2026-09-19 五轮「我希望成员可以显示学号
  /// 和班级」）；没填 / 已删除 → 空串（界面据此决定不占位）。
  String detailOf(String id) => memberOf(id)?.detail ?? '';
}
