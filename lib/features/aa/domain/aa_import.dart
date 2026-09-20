/// 从数据中心名单导入 AA 成员（纯函数：不碰网络、不碰存储，便于单测）。
///
/// 立项口径（2026-09-19 · 用户原话「支持上述查询后，aa功能添加成员允许直接添加
/// 所有舍友」）：导入**按姓名去重** —— 名单里的人名与已有成员同名就跳过。
/// AA 成员表只有「名字」这一个自然键（`id` 是内部 uuid，见 `aa_models.dart`），
/// 而舍友完全可能早就被手动加进账本了，一键导入不能把人加两遍
/// （加两遍会让同一个人被扣两次钱）。
///
/// 范围口径（同日三轮 · 用户原话「我们只要添加自己、添加室友、其他范围的同学
/// 不允许批量添加」）：**只有舍友可以整批导入**，见 [aaRoommateDimension]；
/// 且「添加全部舍友」**会连我自己一起加进来**（同日四轮原话「点击添加全部舍友时
/// 应该一起把自己添加了」）—— 见 [aaImportRoommates]。
library;

import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/features/aa/domain/aa_models.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 唯一允许**整批**导入 AA 的名单维度 = 舍友。
///
/// 用户 2026-09-19 三轮原话：「我们只要添加自己、添加室友、其他范围的同学不允许
/// 批量添加」—— 同班（48 人）/ 同专业（201 人）/ 同年级（7905 人）这类范围整批
/// 塞进账本毫无意义（AA 天然是三五个人之间的事），入口一律不给；要看名单请去
/// 数据中心的「校内关系」卡（那边只是看，不落库）。
///
/// 守卫 = `test/aa_test.dart`「只允许批量导入舍友」组（`features/aa/` 下**除本行
/// 之外**不得再出现别的维度取值）。
const DzjPeerDimension aaRoommateDimension = DzjPeerDimension.dorm;

/// 「补全学号 / 班级」用来取**班级**的第二份名单 = 同班同学。
///
/// ⚠ 这一维**不进账本**（区别于 [aaRoommateDimension]）：全班 48 人一个都不加，
/// 只是拿它当一张「姓名 → 班级」的对照表，给**已经在账本里**的成员补齐班级
/// （见 [aaBackfillMembers]）。舍友名单里只有学号/校区，没有班级 —— 所以两张表都要读。
const DzjPeerDimension aaClassDimension = DzjPeerDimension.classGroup;

/// 取不到自己的姓名时的提示（账号显示名与学籍姓名都为空）。
const String aaSelfNameMissingHint = '读不到你的姓名，请点「添加成员」手动填写';

/// 「添加我自己」的提示文案。
String aaSelfImportMessage({required String name, required bool added}) =>
    added ? '已添加你自己「$name」' : '「$name」已在名单里';

/// 一次「添加全部舍友」的结果（我自己与舍友**分开记账**）。
///
/// 为什么要分开：文案必须把「你自己」与舍友分开说，否则「已添加 3 位舍友」里
/// 混着一个自己，用户会以为名单串进了陌生人。
class AaRoommateImport {
  /// 合并后的完整成员表：**我自己在最前**，其后按舍友名单顺序追加。
  final List<AaMember> members;

  /// 取到的我自己姓名（空串 = 读不到，这时只加了舍友）。
  final String selfName;

  /// 我自己这次有没有真的加进去。
  final bool selfAdded;

  /// 真的新加进来的舍友数。
  final int roommateAdded;

  /// 因同名 / 空名跳过的舍友数。
  final int roommateSkipped;

  const AaRoommateImport({
    required this.members,
    required this.selfName,
    required this.selfAdded,
    required this.roommateAdded,
    required this.roommateSkipped,
  });

  bool get changed => selfAdded || roommateAdded > 0;

  /// 提示文案（见类注释的三态）。
  String get summary {
    final tail = <String>[
      if (changed && roommateSkipped > 0) '$roommateSkipped 位舍友已在名单里',
      if (selfName.isEmpty) aaSelfNameMissingHint,
    ];
    final String head;
    if (selfAdded && roommateAdded > 0) {
      head = '已添加你自己 + $roommateAdded 位舍友';
    } else if (selfAdded) {
      head = '已添加你自己';
    } else if (roommateAdded > 0) {
      head = '已添加 $roommateAdded 位舍友';
    } else {
      final who = selfName.isEmpty ? '舍友' : '你和舍友';
      head = roommateSkipped > 0 ? '没有新成员：$who都已在名单里' : '没有取到舍友';
    }
    return tail.isEmpty ? head : '$head（${tail.join(' · ')}）';
  }
}

/// 舍友名单 + **我自己** → 一次导入（我自己排在最前）。
///
/// 用户 2026-09-19 四轮原话：「点击添加全部舍友时应该一起把自己添加了」——
/// AA 语境里的「舍友」就是「我这一屋的人」，只加另外几位会漏掉发起人。
///
/// 顺序上**自己在最前**：成员顺序 = 开销编辑器里「谁垫付」的默认值，而 AA 里最常见
/// 的情形就是「我先垫的钱」。姓名读不到（[selfName] 为空 / 全是空白）时只加舍友，
/// 提示里另行说明（见 [AaRoommateImport.summary]）。
///
/// [newId] 可注入（测试要确定性 id）；缺省 uuid v4。
AaRoommateImport aaImportRoommates({
  required List<AaMember> existing,
  required String selfName,
  required List<AaImportPerson> roommates,
  String selfStudentNo = '',
  String selfClassName = '',
  String Function()? newId,
}) {
  final self = aaImportMembers(
    existing: existing,
    people: [
      if (selfName.trim().isNotEmpty)
        AaImportPerson(
          selfName,
          studentNo: selfStudentNo,
          className: selfClassName,
        ),
    ],
    newId: newId,
  );
  final room = aaImportMembers(
    existing: self.members,
    people: roommates,
    newId: newId,
  );
  return AaRoommateImport(
    members: room.members,
    selfName: selfName.trim(),
    selfAdded: self.added > 0,
    roommateAdded: room.added,
    roommateSkipped: room.skipped,
  );
}

/// 一次导入的结果。
class AaImportResult {
  /// 合并后的**完整**成员表（原成员在前，新成员按名单顺序追加）。
  final List<AaMember> members;

  /// 真的加进来的条数。
  final int added;

  /// 因为同名 / 空名而跳过的条数。
  final int skipped;

  const AaImportResult({
    required this.members,
    required this.added,
    required this.skipped,
  });

  bool get changed => added > 0;

  /// 提示文案：「已添加 3 位舍友（跳过 1 位已在名单里）」。
  String summary(String what) {
    if (added == 0) {
      return skipped > 0 ? '没有新成员：$what都已在名单里' : '没有取到$what';
    }
    final tail = skipped > 0 ? '（跳过 $skipped 位已在名单里）' : '';
    return '已添加 $added 位$what$tail';
  }
}

/// 去重键：去空白 + 忽略大小写（「张三 」与「张三」是同一个人）。
String aaMemberNameKey(String name) => name.trim().toLowerCase();

/// 待导入的人：姓名 + 可选**学号 / 班级**（后两者只作展示，见 [AaMember]）。
///
/// 用户 2026-09-19 五轮原话「我希望成员可以显示学号和班级」—— 名单里的人自带
/// 学号/班级（数据中心名单的「校园卡号」= `DzjPeer.userId`、班级 = `DzjPeer.className`），
/// 导入时一起带进账本，之后成员列表与开销编辑器都能认人。手工添加的成员允许留空。
class AaImportPerson {
  final String name;
  final String studentNo;
  final String className;

  const AaImportPerson(this.name, {this.studentNo = '', this.className = ''});

  /// 数据中心名单的一行 → 待导入的人。
  factory AaImportPerson.fromPeer(DzjPeer peer) => AaImportPerson(
    peer.name,
    studentNo: peer.userId,
    className: peer.className,
  );

  /// 只有名字（手工输入 / 测试）。
  static List<AaImportPerson> names(Iterable<String> raw) => [
    for (final n in raw) AaImportPerson(n),
  ];
}

/// 人名单 → 成员表（[existing] 原样保留并保持顺序）。
///
/// 去重只看**姓名**（[aaMemberNameKey]）：账本里从没出现过同名的人，导入就不该
/// 再添一个（添两个会让同一个人被扣两次钱）；学号/班级不同也照样跳过。
///
/// [newId] 可注入（测试要确定性 id）；缺省 uuid v4。
AaImportResult aaImportMembers({
  required List<AaMember> existing,
  required List<AaImportPerson> people,
  String Function()? newId,
}) {
  final idOf = newId ?? _uuid;
  final taken = {for (final m in existing) aaMemberNameKey(m.name)};
  final members = [...existing];
  var added = 0;
  var skipped = 0;
  for (final raw in people) {
    final name = raw.name.trim();
    final key = aaMemberNameKey(name);
    // `taken.add` 顺带把本批内的重名也挡掉（名单里同一个人出现两次）。
    if (key.isEmpty || !taken.add(key)) {
      skipped++;
      continue;
    }
    members.add(
      AaMember(
        id: idOf(),
        name: name,
        studentNo: raw.studentNo.trim(),
        className: raw.className.trim(),
      ),
    );
    added++;
  }
  return AaImportResult(
    members: members,
    added: added,
    skipped: skipped,
  );
}

/// 一次「补全学号 / 班级」的结果。
class AaBackfillResult {
  /// 补全后的完整成员表（顺序与 id 全不变 —— 已有开销的引用不断开）。
  final List<AaMember> members;

  /// 被补到东西的成员数。
  final int filled;

  const AaBackfillResult({required this.members, required this.filled});

  bool get changed => filled > 0;

  String get summary => filled == 0
      ? '名单里没有能对上的学号 / 班级'
      : '已补全 $filled 位成员的学号 / 班级';
}

/// 给**已经在账本里**的成员补上缺失的学号 / 班级（按姓名对名单）。
///
/// 为什么需要它：学号 / 班级是五轮才加的字段（用户原话「我希望成员可以显示学号和班级」），
/// 之前手打的成员（以及更早版本导入的）身上一个标识都没有 —— 而舍友名单里本来就有学号、
/// 同班名单里有班级，白白取一次就能把老成员补全。
///
/// 口径：
/// - **只补空字段，绝不覆盖**（用户手改过的值优先，改名不改人）；
/// - 按姓名匹配（去空白 + 忽略大小写，与导入同一把尺子）；
/// - 多人同名时**取第一个**给了值的（名单本身按姓名排序，结果稳定）；
/// - `id` / `name` / 顺序一个都不动。
AaBackfillResult aaBackfillMembers({
  required List<AaMember> existing,
  required List<AaImportPerson> people,
}) {
  final no = <String, String>{};
  final cls = <String, String>{};
  for (final p in people) {
    final key = aaMemberNameKey(p.name);
    if (key.isEmpty) continue;
    final n = p.studentNo.trim();
    final c = p.className.trim();
    if (n.isNotEmpty) no.putIfAbsent(key, () => n);
    if (c.isNotEmpty) cls.putIfAbsent(key, () => c);
  }

  var filled = 0;
  final members = <AaMember>[];
  for (final m in existing) {
    final key = aaMemberNameKey(m.name);
    final n = m.studentNo.isEmpty ? (no[key] ?? '') : m.studentNo;
    final c = m.className.isEmpty ? (cls[key] ?? '') : m.className;
    if (n == m.studentNo && c == m.className) {
      members.add(m);
      continue;
    }
    filled++;
    members.add(m.copyWith(studentNo: n, className: c));
  }
  return AaBackfillResult(members: members, filled: filled);
}

String _uuid() => const Uuid().v4();
