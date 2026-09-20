/// 「找空闲教室」（公共查询里的两个子功能）的**纯领域模型与算法**。
///
/// 两个子功能对应原网页「公共查询」菜单里的 SB11 / SB12：
/// - **SB11 分周次/节次查看空闲教室**：给定教学周 + 星期 + 节次 → 有多少间教室是空的；
/// - **SB12 分教室查看空闲周次/节次**：给定一间教室 → 它在哪些周次/节次是空的。
///
/// ## 为什么不用原网页那两个端点（2026-09-19 实测，别再试）
///
/// 实测（真实会话，探针直接打教务端点）：
/// - `GET /kbbp/dykb.fzcjcckkxjsi_data.jsp`（SB11）**恒回 721 字节的
///   `没有检索到记录!`**：给了 `xnxq/xn/xq_m/pkts` 与 `zc/jc/zcd/selZC/hidJC/
///   xqdm/week/period/skzc/kxjs…` 共 44 组参数组合（无效值当探针）**全部无差别**，
///   说明它**不从请求参数取过滤条件**（页面大概把它们存进了 session）→ 直接调用拿不到数据。
/// - `GET /kbbp/dykb.fjsickkxzcjc_data.jsp`（SB12）**只要 `xnxq` 就能出数，但一次回
///   整个学校**：`?xnxq=2026,0&xn=2026&xq_m=0` → **94 810 139 字节 / 487 张表**；
///   再加 `xqdm/selXQ/lf_m/hidFJBH/zc` 都一样大（参数被忽略）→ 移动端不可用。
/// - 两个 `.html` 页面本身（`/kbbp/dykb.fzcjcckkxjsi.html` 等）**一律回凭证失效页**
///   （连 SB03 也一样，而同一会话打 `.jsp` 数据端点是好的）→ 也读不到页面 JS。
///
/// 所以本模块**自己在客户端算**，数据只用一个**已经跑通**的端点：
/// **教室课表报表**（`PublicQueryKind.classroom`，一次请求 = 整个校区/整栋楼的全部教室课表）。
/// 口径上与网页一致（两者都是「排课占用」的同一份数据），而且能离线重算。
///
/// ## 口径（改动前先读）
/// - 周次 / 星期 / 节次一律 **1 起**，星期 1 = 周一，与 [ScheduleSlot] 一致。
/// - 「空闲」= 该格**没有任何课**（含单双周判定：`[1-16]周(单)` 在第 2 周就是空的）。
/// - **一次请求覆盖整个范围**：换周次/星期/节次只在本模块里重算，不再发请求。
/// - 教室里**整学期都没有排课**的（报表里没有它）也算空闲 —— 补进候选靠的是
///   教室下拉清单（`MsSchoolArea_LF_JS`），见 [classroomOccupanciesOf] 的 `rooms`。
library;

import 'free_time.dart';
import 'public_query.dart';
import 'public_query_defaults.dart';
import 'public_timetable.dart';
import '../../schedule/domain/period_time.dart';
import '../../schedule/domain/schedule_gap_rows.dart';

/// 一个学期按 **20 个教学周** 展示（与公共查询页「多班对照」的周次下拉同口径：
/// 江财一学期 18–20 周，周次选择器一律给到 20）。
const int kClassroomFreeWeeks = 20;

/// 节次的**大节档**（与教务课表行标签一致：`1-2 / 3-5 / 6-7 / 8-9 / 10-12 节`）。
///
/// 见 `reverse_engineering/公共查询接口.md` §7「大节 → 实际节次用行标签还原，
/// 江财当前是五档」——**别硬编码「每大节 2 小节」**。
///
/// ⚠ **2026-09-19 二轮起页面不再用它**：用户要求节次 1-12 每节独立勾选
/// （见 `classroom_free_screen.dart` 的 `classroomFreePeriod-<n>`）。保留这张表只为
/// 记录「教务课表行标签是这五档」，别再拿它当选择项。
const List<(String label, int start, int end)> kClassroomFreePeriodPresets = [
  ('1-2 节', 1, 2),
  ('3-5 节', 3, 5),
  ('6-7 节', 6, 7),
  ('8-9 节', 8, 9),
  ('10-12 节', 10, 12),
];

/// 教室类型/名称里带这些词的不是**实体教室**：教务把「线上教学」「不排教室」
/// 这类虚拟条目也塞进了教室清单（实测麦庐园 405 条里就有「线上教学 1000 座 ·
/// 不排教室」）。「找空闲教室」里直接跳过，免得推荐一间上不了的「教室」。
const List<String> kNonPhysicalClassroomKinds = ['不排教室', '线上教学'];

/// 是不是可以真的去上课的教室（见 [kNonPhysicalClassroomKinds]）。
bool isPhysicalClassroom(ClassroomInfo info) => !kNonPhysicalClassroomKinds.any(
  (k) => info.kind.contains(k) || info.name.contains(k),
);

/// 按名称在教室清单里找同一间教室。
///
/// 先比**归一化后的全等名**（`蛟北区G301` ↔ `蛟北区G301[69][公共实验室]`），
/// 再退化为**互相包含**（报表与清单偶尔差一个后缀/前缀）。
/// 找不到返回 null —— 调用方据此给「换一间」的提示，**不要**拿名字去当教室码发请求。
ClassroomInfo? classroomInfoNamed(
  Iterable<ClassroomInfo> rooms,
  String name,
) {
  final key = normalizePublicQueryName(name);
  if (key.isEmpty) return null;
  for (final room in rooms) {
    if (room.matchKey == key) return room;
  }
  for (final room in rooms) {
    final other = room.matchKey;
    if (other.isEmpty) continue;
    if (other.contains(key) || key.contains(other)) return room;
  }
  return null;
}

/// 教室名称里的元信息：`蛟三教3101[40][一般教室]` → 名称 / 容量 / 类型。
///
/// 教务下拉（`MsSchoolArea_LF_JS`）给的就是这个格式；缺段（如只有 `[一般教室]`）
/// 也要能解析，`[` 之后按顺序认「纯数字 = 容量、其余 = 类型」。
({String name, int capacity, String kind}) parseClassroomName(String raw) {
  final trimmed = raw.trim();
  final start = trimmed.indexOf('[');
  if (start <= 0) return (name: trimmed, capacity: 0, kind: '');
  final name = trimmed.substring(0, start).trim();
  final groups = RegExp(
    r'\[([^\]]*)\]',
  ).allMatches(trimmed.substring(start)).map((m) => m.group(1)!.trim());
  var capacity = 0;
  final kinds = <String>[];
  for (final g in groups) {
    if (g.isEmpty) continue;
    final digits = g.replaceAll(RegExp(r'[^0-9]'), '');
    final n = digits.isEmpty ? null : int.tryParse(digits);
    if (capacity == 0 && n != null && n > 0) {
      capacity = n;
    } else {
      kinds.add(g);
    }
  }
  return (name: name, capacity: capacity, kind: kinds.join(' · '));
}

/// 一间教室的静态信息（教务教室下拉的一项）。
class ClassroomInfo {
  final String code;
  final String name;

  /// 容量（`[40]`）；解析不到 = 0（界面不显示）。
  final int capacity;

  /// 教室类型（`[一般教室]`）；解析不到 = 空串。
  final String kind;

  const ClassroomInfo({
    required this.code,
    required this.name,
    this.capacity = 0,
    this.kind = '',
  });

  /// 与课表报表里的教室名对齐用的键（去空白、全角括号转半角、小写）。
  String get matchKey => normalizePublicQueryName(name);

  /// `蛟三教3101 · 40 座 · 一般教室`。
  String get label => [
    name,
    if (capacity > 0) '$capacity 座',
    if (kind.isNotEmpty) kind,
  ].join(' · ');

  @override
  String toString() => 'ClassroomInfo($code, $name)';
}

/// 教务教室下拉的一项 → [ClassroomInfo]（名称为空时返回 `null`）。
ClassroomInfo? parseClassroomInfo(PublicQueryOption option) {
  final parsed = parseClassroomName(option.displayName);
  if (parsed.name.isEmpty) return null;
  return ClassroomInfo(
    code: option.code,
    name: parsed.name,
    capacity: parsed.capacity,
    kind: parsed.kind,
  );
}

/// 教务教室下拉 → 教室清单（**保序、去重**，名称相同的只留第一条）。
List<ClassroomInfo> parseClassroomInfos(Iterable<PublicQueryOption> options) {
  final seen = <String>{};
  final result = <ClassroomInfo>[];
  for (final o in options) {
    final info = parseClassroomInfo(o);
    if (info == null) continue;
    if (!seen.add(info.matchKey)) continue;
    result.add(info);
  }
  return result;
}

/// 一间教室的**整学期占用**（槽来自教室课表报表）。
///
/// `slots` 为空 = 整学期都没排课（一直空闲）。
class ClassroomOccupancy {
  /// 教室码（来自下拉清单；只出现在报表里的教室为 `''`）。
  final String code;

  /// 教室名（与报表描述块的 `教室：xxx` 同字面）。
  final String name;

  /// 楼房名（报表的 `楼房` 字段优先，其次为空）。
  final String building;

  /// 教室类型（报表的 `教室类型` 字段优先，其次取下拉名里的 `[...]`）。
  final String kind;

  /// 容量（只有下拉清单里有；0 = 未知）。
  final int capacity;

  final List<ScheduleSlot> slots;

  const ClassroomOccupancy({
    this.code = '',
    required this.name,
    this.building = '',
    this.kind = '',
    this.capacity = 0,
    this.slots = const [],
  });

  String get matchKey => normalizePublicQueryName(name);

  /// `蛟北区G301 · 69 座 · 公共实验室`。
  String get label => [
    name,
    if (capacity > 0) '$capacity 座',
    if (kind.isNotEmpty) kind,
  ].join(' · ');

  /// 第 [period] 节是否被占（含单双周与周次区间判定）。
  bool busyAt({
    required int week,
    required int weekday,
    required int period,
  }) {
    for (final s in slots) {
      if (s.occupies(weekday, period, week: week)) return true;
    }
    return false;
  }

  /// `[startPeriod, endPeriod]` 整段是否**全部**空闲（任一节被占即 false）。
  bool freeIn({
    required int week,
    required int weekday,
    required int startPeriod,
    required int endPeriod,
  }) {
    for (var p = startPeriod; p <= endPeriod; p++) {
      if (busyAt(week: week, weekday: weekday, period: p)) return false;
    }
    return true;
  }

  /// 占用某格的课程名（用于「为什么这间不行」）。
  String occupyingCourse({
    required int week,
    required int weekday,
    required int period,
  }) {
    for (final s in slots) {
      if (s.occupies(weekday, period, week: week)) return s.courseName;
    }
    return '';
  }

  @override
  String toString() => 'ClassroomOccupancy($name, ${slots.length} 槽)';
}

/// 课表报表 + 教室清单 → 每间教室的占用。
///
/// - [timetables]：教室课表报表（一次请求可含整栋楼/整个校区的教室）；
/// - [rooms]：教室下拉清单结果；**在报表里没出现的教室按「整学期空闲」补进来**
///   （教务报表只列有排课的教室，从没排过课的教室只能靠清单补）。
///
/// ⚠ 选了**单个楼房**时不要把整校区的清单灌进来（清单接口的 `lf_m` 不生效，
/// 它给的是全校区教室），否则会把别的楼的教室算成「空闲」。此时传 `rooms: const []`，
/// 只用报表里那份（该楼有排课的教室）——界面里已写明这条限制。
List<ClassroomOccupancy> classroomOccupanciesOf({
  required List<PublicTimetable> timetables,
  Iterable<ClassroomInfo> rooms = const [],
}) {
  final slotsByKey = <String, List<ScheduleSlot>>{};
  final nameByKey = <String, String>{};
  final buildingByKey = <String, String>{};
  final kindByKey = <String, String>{};
  for (final t in timetables) {
    final key = normalizePublicQueryName(t.owner);
    if (key.isEmpty) continue;
    nameByKey.putIfAbsent(key, () => t.owner);
    slotsByKey.putIfAbsent(key, () => <ScheduleSlot>[]).addAll(
      slotsOfTimetables([t], ownerOf: (_) => t.owner),
    );
    final building = t.fieldOf('楼房');
    if (building.isNotEmpty) buildingByKey[key] = building;
    final kind = t.fieldOf('教室类型');
    if (kind.isNotEmpty) kindByKey[key] = kind;
  }

  final result = <ClassroomOccupancy>[];
  final used = <String>{};
  for (final info in rooms) {
    if (!isPhysicalClassroom(info)) continue;
    final key = info.matchKey;
    if (key.isEmpty || !used.add(key)) continue;
    final reportKind = kindByKey[key] ?? '';
    result.add(
      ClassroomOccupancy(
        code: info.code,
        name: info.name,
        building: buildingByKey[key] ?? '',
        kind: reportKind.isEmpty ? info.kind : reportKind,
        capacity: info.capacity,
        slots: slotsByKey[key] ?? const [],
      ),
    );
  }
  for (final key in slotsByKey.keys) {
    if (used.contains(key)) continue;
    result.add(
      ClassroomOccupancy(
        name: nameByKey[key] ?? key,
        building: buildingByKey[key] ?? '',
        kind: kindByKey[key] ?? '',
        slots: slotsByKey[key]!,
      ),
    );
  }
  result.sort((a, b) {
    final byBuilding = a.building.compareTo(b.building);
    if (byBuilding != 0) return byBuilding;
    return a.name.compareTo(b.name);
  });
  return result;
}

/// 该批教室涉及的教学周数（取所有占用槽的最大 `endWeek`）。
///
/// ⚠ 解析不出 `[x-y]周` 的格子会给 `endWeek = 30`（`PublicTimetableCell` 的兜底），
/// 所以只认 `1..20` 以内的值，全都越界就回落 [fallback]。
int classroomTermWeeksOf(
  Iterable<ClassroomOccupancy> rooms, {
  int fallback = 20,
}) {
  var weeks = 0;
  for (final r in rooms) {
    for (final s in r.slots) {
      if (s.endWeek >= 1 && s.endWeek <= 20 && s.endWeek > weeks) {
        weeks = s.endWeek;
      }
    }
  }
  return weeks == 0 ? fallback : weeks;
}

/// 模式 A（SB11）的一行：某间教室在「选定星期 + 节次」下的空闲情况。
class ClassroomFreeHit {
  final ClassroomOccupancy room;

  /// 选中的星期里**空的**那些（升序）。
  final List<int> freeWeekdays;

  /// 选中的星期里**被占**的那些（升序）。
  final List<int> busyWeekdays;

  /// 被占的星期 → 占用它的课程名（用于行内说明）。
  final Map<int, String> busyCourses;

  const ClassroomFreeHit({
    required this.room,
    required this.freeWeekdays,
    required this.busyWeekdays,
    this.busyCourses = const {},
  });

  /// 选中的星期全都空。
  bool get allFree => busyWeekdays.isEmpty;

  int get freeCount => freeWeekdays.length;

  /// `周三、周五` / `周三（周四被「高等数学」占用）`。
  String get detail {
    final free = freeWeekdays.map(weekdayLabel).join('、');
    if (allFree) return '${free.isEmpty ? '全部' : free} 都空';
    final busy = busyWeekdays
        .map((d) {
          final course = busyCourses[d] ?? '';
          return course.isEmpty ? weekdayLabel(d) : '${weekdayLabel(d)}（$course）';
        })
        .join('、');
    return '${free.isEmpty ? '没有空闲' : '$free 空'} · $busy有课';
  }

  @override
  String toString() => 'ClassroomFreeHit(${room.name}, $detail)';
}

/// `周一`…`周日`（1 = 周一）。
String weekdayLabel(int weekday) =>
    weekday >= 1 && weekday <= 7 ? '周${'一二三四五六日'[weekday - 1]}' : '周?';

/// 模式 A（SB11）：第 [week] 周、[weekdays] 里的星期、[startPeriod]-[endPeriod] 节
/// **有空**的教室。
///
/// 只返回「至少有一天是空的」教室；选多天时**全空**的排在最前（默认想找能一直用的）。
/// 排序：全空 → 空的天数多 → 容量大 → 楼房 → 名称（同输入必然同顺序）。
///
/// [periodBlocks] 是 2026-09-19 用户要的**节次多选**（「时间我希望可以多选」）：
/// 传了非空列表时以它为准（`[startPeriod, endPeriod]` 只作兼容旧调用方的兜底），
/// 语义与「星期多选」一致 —— **每一个选中的时段都空**才算这间教室可用。
List<ClassroomFreeHit> freeClassroomsAt({
  required Iterable<ClassroomOccupancy> rooms,
  required int week,
  required Iterable<int> weekdays,
  required int startPeriod,
  required int endPeriod,
  Iterable<(int, int)> periodBlocks = const [],
}) {
  final days = weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
  final ranges = <(int, int)>[
    for (final (s, e) in periodBlocks)
      if (e >= s) (s, e),
  ];
  if (ranges.isEmpty) {
    if (endPeriod < startPeriod) return const [];
    ranges.add((startPeriod, endPeriod));
  }
  if (days.isEmpty) return const [];
  final hits = <ClassroomFreeHit>[];
  for (final room in rooms) {
    final free = <int>[];
    final busy = <int>[];
    final courses = <int, String>{};
    for (final d in days) {
      // 被占的原因取**第一个占住它的时段**的起始节（多选时用户就是按档勾的）。
      var busyPeriod = -1;
      for (final (s, e) in ranges) {
        if (!room.freeIn(
          week: week,
          weekday: d,
          startPeriod: s,
          endPeriod: e,
        )) {
          busyPeriod = s;
          break;
        }
      }
      if (busyPeriod < 0) {
        free.add(d);
      } else {
        busy.add(d);
        final course = room.occupyingCourse(
          week: week,
          weekday: d,
          period: busyPeriod,
        );
        if (course.isNotEmpty) courses[d] = course;
      }
    }
    if (free.isEmpty) continue;
    hits.add(
      ClassroomFreeHit(
        room: room,
        freeWeekdays: free,
        busyWeekdays: busy,
        busyCourses: courses,
      ),
    );
  }
  hits.sort((a, b) {
    if (a.allFree != b.allFree) return a.allFree ? -1 : 1;
    if (a.freeCount != b.freeCount) return b.freeCount.compareTo(a.freeCount);
    if (a.room.capacity != b.room.capacity) {
      return b.room.capacity.compareTo(a.room.capacity);
    }
    final byBuilding = a.room.building.compareTo(b.room.building);
    if (byBuilding != 0) return byBuilding;
    return a.room.name.compareTo(b.room.name);
  });
  return hits;
}

/// 模式 B（SB12）：某间教室在第 [week] 周的空闲时段（半日块内连续，跨块不并）。
///
/// 直接复用「多班对照」那套引擎（[findFreeWindows]），只是对照对象只有这一间教室。
List<FreeWindow> roomFreeWindows({
  required ClassroomOccupancy room,
  required int week,
  int maxPeriod = 12,
  bool includeWeekend = true,
  List<PeriodBlock> blocks = kDefaultPeriodBlocks,
  int minPeriods = 1,
}) => findFreeWindows(
  slots: room.slots,
  week: week,
  maxPeriod: maxPeriod,
  blocks: blocks,
  weekdays: includeWeekend ? const {1, 2, 3, 4, 5, 6, 7} : const {1, 2, 3, 4, 5},
  minPeriods: minPeriods,
);

/// 模式 B（SB12）：某间教室在 [weeks] **每一周都空**的时段 = 整学期固定空闲。
///
/// 这是「这间教室什么时候长期可用」的答案，比逐周翻页有用得多。
///
/// ⚠ **不能**直接用 `free_time.dart` 的 `commonFreeWindows`：它按「窗口完全同名」
/// 取交集 —— 第 1 周周一上午整段空（一节窗口 `1-5`）、第 2 周只剩 `1-2` 空，
/// 两者被判成不同窗口 → 结果把「周一 1-2 节每周都空」也丢掉。
/// 正确口径 = **逐格取交集**（每个 (星期, 节次) 在每一周都空闲才算数），再按半日块切窗口。
List<FreeWindow> roomCommonFreeWindows({
  required ClassroomOccupancy room,
  required Iterable<int> weeks,
  int maxPeriod = 12,
  bool includeWeekend = true,
  List<PeriodBlock> blocks = kDefaultPeriodBlocks,
  int minPeriods = 1,
}) {
  final weekList = weeks.where((w) => w >= 1).toList()..sort();
  if (weekList.isEmpty) return const [];
  final days = [
    for (var d = 1; d <= 7; d++)
      if (includeWeekend || d <= 5) d,
  ];
  if (days.isEmpty) return const [];

  final free = {
    for (final d in days) d: List<bool>.filled(maxPeriod + 1, true),
  };
  for (final w in weekList) {
    final grid = buildOccupancyGrid(
      slots: room.slots,
      week: w,
      maxPeriod: maxPeriod,
    );
    for (final d in days) {
      final row = free[d]!;
      for (var p = 1; p <= maxPeriod; p++) {
        if (row[p] && grid[d][p] != 0) row[p] = false;
      }
    }
  }

  final result = <FreeWindow>[];
  for (final d in days) {
    final row = free[d]!;
    for (final (blockStart, blockEnd) in blocks) {
      final from = blockStart < 1 ? 1 : blockStart;
      final to = blockEnd > maxPeriod ? maxPeriod : blockEnd;
      var runStart = -1;
      for (var p = from; p <= to + 1; p++) {
        final isFree = p <= to && row[p];
        if (isFree && runStart < 0) {
          runStart = p;
        } else if (!isFree && runStart >= 0) {
          if (p - runStart >= minPeriods) {
            result.add(
              FreeWindow(
                weekday: d,
                startPeriod: runStart,
                endPeriod: p - 1,
                // 「每周都成立」，不属于某一周 → 0。
                week: 0,
              ),
            );
          }
          runStart = -1;
        }
      }
    }
  }
  return result;
}

// ---------------- 楼层（用户 2026-09-19：「教室应该分楼层显示」） ----------------

/// 从教室名推断楼层：**房号（末尾那串数字）的首位就是楼层**。
///
/// 实测命名（2026-09-19，麦庐园 / 蛟桥园真实教室清单）：
/// `麦一教1101`→1、`麦一教1302`→1、`麦二教2402`→2、`蛟三教3101`→3、
/// `麦群庐Q202`→2、`蛟北区G301`→3、`麦萃庐C222`→2 —— 楼名里那个「一/二/三」
/// 与房号首位**未必一致**（`麦一教1302` 在 1 楼、`蛟三教3101` 在 3 楼），
/// 所以一律以**房号首位**为准，不看楼名。
///
/// 房号不足 3 位（如 `博雅艺术中心B01`）视为**没有楼层信息** → null（归「其它」组）；
/// 首位是 0 同样返回 null（`0123` 这种不是常规编号，不猜）。
int? classroomFloorOf(String name) {
  final match = RegExp(r'(\d+)\s*$').firstMatch(name.trim());
  if (match == null) return null;
  final digits = match.group(1)!;
  if (digits.length < 3) return null;
  final floor = int.tryParse(digits[0]);
  if (floor == null || floor <= 0 || floor > 9) return null;
  return floor;
}

/// 从教室名取**楼名前缀**：末尾 `字母 + 数字`（房号）之前的那一段。
///
/// `麦一教1101`→`麦一教`、`麦群庐Q202`→`麦群庐`、`蛟北区G301`→`蛟北区`、
/// `博雅艺术中心B01`→`博雅艺术中心`；名字里没有房号时返回**空串**（调用方该退回
/// 报表给的楼房名）。
String classroomBuildingOf(String name) {
  final trimmed = name.trim();
  final match = RegExp(r'[A-Za-z]*\d+\s*$').firstMatch(trimmed);
  if (match == null) return '';
  return trimmed.substring(0, match.start).trim();
}

/// 楼层分组的标题：`3 楼` / `其它`（没有楼层信息的那批）。
String classroomFloorLabel(int? floor) =>
    floor == null ? '其它' : '$floor 楼';

/// 节次段：被「大间隔节点」切开后的一段连续节次（含首尾）。
///
/// 判据与课表矮行**完全相同** —— [scheduleGapThresholdMinutes]（= 60 分钟）：
/// 相邻两节的间隔**严格超过 1 小时**才算一个「节点」
/// （用户 2026-09-19 二轮原话：「到下一个节点（间隔超过1h的）前的最后一节课」）。
///
/// 内置作息表 → `[(1, 5), (6, 9), (10, 12)]`（5→6 午休 100 分、9→10 晚饭 70 分）。
/// ⚠ 不要改用 `free_time.dart` 的 `periodBlocksFromTimes`：它默认 `gapMinutes = 45`，
/// 与「节点」口径不一致。
List<(int start, int end)> classroomPeriodSegments(PeriodTable? table) {
  if (table == null) return const [];
  final segments = <(int, int)>[];
  var start = 1;
  for (var p = 1; p < schedulePeriodCount; p++) {
    final minutes = scheduleBreakMinutes(table, p);
    if (minutes != null && minutes > scheduleGapThresholdMinutes) {
      segments.add((start, p));
      start = p + 1;
    }
  }
  segments.add((start, schedulePeriodCount));
  return segments;
}

/// 按「现在」自动选出的节次范围（用户 2026-09-19 二轮）。
///
/// 口径 =「**从当前节数**（如果当前不在上课时间就**从下节课开始**）**到下一个节点前的
/// 最后一节课**」：
/// - 起点 = 正在上的那一节；此刻不在上课时间 → 第一节还没开始的课；
/// - 终点 = 起点所在 [classroomPeriodSegments] 段的最后一节；
/// - 当天节次已全部结束（晚于最后一节下课）→ 退回**最后一段**；
/// - 表为空 / 段为空 → null（页面保持用户手选）。
({int start, int end})? classroomAutoPeriodRange({
  required PeriodTable? table,
  required DateTime now,
}) {
  final t = table;
  if (t == null) return null;
  final segments = classroomPeriodSegments(t);
  if (segments.isEmpty) return null;
  final minutes = now.hour * 60 + now.minute;

  int? current;
  for (var p = 1; p <= schedulePeriodCount; p++) {
    final period = t.periodOf(p);
    if (period == null) continue;
    if (period.startMinutes <= minutes && minutes <= period.endMinutes) {
      current = p;
      break;
    }
  }
  if (current == null) {
    for (var p = 1; p <= schedulePeriodCount; p++) {
      final period = t.periodOf(p);
      if (period == null) continue;
      if (period.startMinutes > minutes) {
        current = p;
        break;
      }
    }
  }
  final last = segments.last;
  if (current == null) return (start: last.$1, end: last.$2);
  for (final (start, end) in segments) {
    if (current >= start && current <= end) return (start: current, end: end);
  }
  return (start: last.$1, end: last.$2);
}

/// 把「勾中的节次」并成连续区间：`{1,2,3,4,5}` → `[(1,5)]`、`{1,3}` → `[(1,1),(3,3)]`。
///
/// 1-12 每节独立勾选之后（2026-09-19 二轮），展示与领域入参都走这里 —— 否则摘要会印成
/// `1 节 + 2 节 + 3 节 + 4 节 + 5 节`。
List<(int start, int end)> classroomPeriodRanges(Iterable<int> periods) {
  final sorted = periods
      .where((p) => p >= 1 && p <= schedulePeriodCount)
      .toSet()
      .toList()
    ..sort();
  final ranges = <(int, int)>[];
  for (final p in sorted) {
    if (ranges.isNotEmpty && ranges.last.$2 + 1 == p) {
      ranges[ranges.length - 1] = (ranges.last.$1, p);
    } else {
      ranges.add((p, p));
    }
  }
  return ranges;
}

/// 把 1..12 切成视图的「绘画单元」：**连续勾中的节次合成一段**（视觉上是一张卡片，
/// 内部仍逐格可点），没勾中的各自独立成段。
///
/// 用户 2026-09-19 三轮：「我希望连续被选择的节次视觉上是一个卡片，但是仍然可以
/// 独立点击」——所以合并只发生在**选中态且相邻**的节次之间，返回的每段都是升序连续
/// 的下标（长度 1 = 独立的一格）。
///
/// 纯分组口径，页面只负责画：`{3,4,5}` → `[[1],[2],[3,4,5],[6]…[12]]`。
List<List<int>> classroomPeriodRuns(
  Iterable<int> periods, {
  int count = schedulePeriodCount,
}) {
  final on = periods.where((p) => p >= 1 && p <= count).toSet();
  final runs = <List<int>>[];
  List<int>? current;
  for (var p = 1; p <= count; p++) {
    if (on.contains(p)) {
      (current ??= <int>[]).add(p);
      continue;
    }
    if (current != null) {
      runs.add(current);
      current = null;
    }
    runs.add(<int>[p]);
  }
  if (current != null) runs.add(current);
  return runs;
}

/// 节次「连接 / 断开」过渡的**分段**：只把「两态都勾中」的连续节次合成一段，
/// 其余（两态都没选、或正好在两态之间变了态的）各自独立成段。
///
/// 用户 2026-09-20 九轮：「我希望为查无课时间功能内的节数选择器添加动画，
/// 尤其是两段连续选中的段被连接时，以及单一连续段被分开时」——过渡里**几何一格都不动**
/// （见 `kClassroomChipGap` 的总宽不变式），变的只是「哪一块红连着哪一块」，
/// 于是把不变的部分照原样成段、把变了态的那些格拆成单格，同一个分段就同时画得出
/// 两个端点：
///
/// - `classroomPeriodJointSegments(a, a)` ≡ `classroomPeriodRuns(a)`；
/// - `classroomPeriodJointSegments(b, b)` ≡ `classroomPeriodRuns(b)`。
///
/// 两条恒等式意味着动画的**第一帧与按下前的画面、最后一帧与按下后的画面逐段相同**
/// （守卫见 `test/classroom_free_test.dart`），所以起止都不会「跳一下」。
List<List<int>> classroomPeriodJointSegments(
  Iterable<int> from,
  Iterable<int> to, {
  int count = schedulePeriodCount,
}) {
  final stable = from
      .where((p) => p >= 1 && p <= count)
      .toSet()
      .intersection(to.where((p) => p >= 1 && p <= count).toSet());
  final segments = <List<int>>[];
  for (var p = 1; p <= count; p++) {
    // 连续**且两态都选中**才并进上一段 —— 这就是上面两条恒等式成立的原因。
    final previous = segments.isEmpty ? null : segments.last.last;
    if (stable.contains(p) && previous == p - 1 && stable.contains(p - 1)) {
      segments.last.add(p);
    } else {
      segments.add(<int>[p]);
    }
  }
  return segments;
}

/// 过渡里一条「缝」：两侧的节次 + 它在两态下**是不是同一块红的一部分**（1 / 0）。
///
/// 值只有 1 和 0（不是插值），调用方按进度取：`fromRed + (toRed - fromRed) * t`
/// —— t = 0 / 1 时浮点上正好落回端点值，收尾不会差一点点。
typedef ClassroomPeriodJoint = ({int left, int right, double fromRed, double toRed});

/// 逐条缝地算「这块红要不要连过去」，只在 [segments] 的**相邻两段之间**才有缝。
///
/// 两态一致的缝（本来就段内、或本来就没连上）**不返回** —— 它们没有动画可做。
List<ClassroomPeriodJoint> classroomPeriodJoints(
  Iterable<int> from,
  Iterable<int> to,
  List<List<int>> segments,
) {
  final on = from.toSet();
  final target = to.toSet();
  final joints = <ClassroomPeriodJoint>[];
  for (var i = 0; i + 1 < segments.length; i++) {
    final left = segments[i].last;
    final right = segments[i + 1].first;
    final fromRed = on.contains(left) && on.contains(right) ? 1.0 : 0.0;
    final toRed = target.contains(left) && target.contains(right) ? 1.0 : 0.0;
    if (fromRed == toRed) continue;
    joints.add((left: left, right: right, fromRed: fromRed, toRed: toRed));
  }
  return joints;
}

/// 节次区间的展示文案：`1-5 节` / 单节 `3 节` / 多段 `1 节 + 3 节`（空列表 → `—`）。
///
/// 大节档（`1-2 节` 这种）只是它的特例，见 [kClassroomFreePeriodPresets]。
String classroomPeriodBlocksLabel(Iterable<(int, int)> blocks) {
  final labels = <String>[];
  for (final (start, end) in blocks) {
    labels.add(start == end ? '$start 节' : '$start-$end 节');
  }
  return labels.isEmpty ? '—' : labels.join(' + ');
}

/// 同一「楼房 + 楼层」的一组（[floor] 为 null = 房号里读不出楼层）。
class ClassroomFloorGroup<T> {
  /// 楼名（取教室名的前缀；名字里读不出时可能为空）。
  final String building;

  /// 楼层；`null` = 读不出。
  final int? floor;

  /// 该组的条目（保持传入顺序）。
  final List<T> items;

  const ClassroomFloorGroup({
    required this.building,
    required this.floor,
    required this.items,
  });

  /// 组标题：`麦一教 · 3 楼`（楼名读不出时只有 `3 楼`）。
  String get label {
    final floorText = classroomFloorLabel(floor);
    return building.isEmpty ? floorText : '$building · $floorText';
  }

  /// 组内条目数（标题里带出来：`麦一教 · 3 楼 · 12 间`）。
  int get count => items.length;

  @override
  String toString() => 'ClassroomFloorGroup($label, $count)';
}

/// 按「楼房 + 楼层」分组：**楼名升序 → 楼层升序，读不出楼层的排在该楼最后**；
/// 组内保持传入顺序。**不会丢条目** —— 每一条都恰好落进一个组（守卫有条数不变式）。
List<ClassroomFloorGroup<T>> groupByClassroomFloor<T>(
  Iterable<T> items,
  String Function(T) nameOf,
) {
  final buckets = <String, Map<int?, List<T>>>{};
  for (final item in items) {
    final name = nameOf(item);
    final building = classroomBuildingOf(name);
    final byFloor = buckets.putIfAbsent(building, () => <int?, List<T>>{});
    byFloor.putIfAbsent(classroomFloorOf(name), () => <T>[]).add(item);
  }
  final buildings = buckets.keys.toList()..sort();
  final groups = <ClassroomFloorGroup<T>>[];
  for (final building in buildings) {
    final byFloor = buckets[building]!;
    final floors = byFloor.keys.whereType<int>().toList()..sort();
    for (final f in floors) {
      groups.add(
        ClassroomFloorGroup<T>(
          building: building,
          floor: f,
          items: List<T>.unmodifiable(byFloor[f]!),
        ),
      );
    }
    if (byFloor.containsKey(null)) {
      groups.add(
        ClassroomFloorGroup<T>(
          building: building,
          floor: null,
          items: List<T>.unmodifiable(byFloor[null]!),
        ),
      );
    }
  }
  return groups;
}

/// 模式 A 结果按「楼房 + 楼层」分组。
List<ClassroomFloorGroup<ClassroomFreeHit>> groupFreeHitsByFloor(
  List<ClassroomFreeHit> hits,
) => groupByClassroomFloor(hits, (h) => h.room.name);

/// 教室清单（选教室弹层）按「楼房 + 楼层」分组。
List<ClassroomFloorGroup<ClassroomInfo>> groupClassroomsByFloor(
  List<ClassroomInfo> rooms,
) => groupByClassroomFloor(rooms, (r) => r.name);
