/// 数据中心的**补充模块**：学校个人数据中心还有几块没进 App 的信息。
///
/// 用户 2026-09-19 三轮原话：「学生数据中心还有很多信息没有加入，比如：基本信息 关联同学
/// 指导教师 学业信息 奖助贷勤 校内活动 住宿信息 校园消费 图书服务 数字活动 我希望可以把
/// 基本信息并入「我的」页 其他的，都显示在数据中心内」。
///
/// 落地口径（2026-09-19 用真会话逐个探过组件，见 `reverse_engineering/数据中台名单接口.md`）：
/// - **基本信息**（姓名 / 校园卡号 / 学院）→ 「我的」页（学籍缓存，零网络）；
/// - **指导教师**（班主任姓名 + 手机）→ 首屏概览早已有（`DataCenterOverview.advisorName`）；
/// - **关联同学** → 两张名单卡（[DzjPeerDimension.relationDims] / [relatedDims]）；
/// - **校园消费 / 图书服务（借阅）/ 奖助贷勤（奖学金）/ 学业（加权·绩点·学分）** → 已有卡；
/// - **本文件补的三块** = 本学期选修课程 / 图书馆座位预约 / 助学金与勤工助学；
/// - **校内活动（最近轨迹）+ 数字活动（上网记录、门禁记录）没能落地**：学校那三个组件
///   服务端坏了 —— `u:69f9503c1ace`、`u:5a778b17683d` 的 SQL 是占位符
///   `select * from t_sys_user`（真调时回整个系统用户表 / 50000 系统异常），
///   `u:e53ab835fd30`（上网记录）`data/get` 与 `data/search` 都回空 —— 客户端**编不出数据**，
///   所以不给假卡片（宁可少一块，也不要在页面上摆一块永远空着的「数字活动」）。
library;

import 'package:flutter/material.dart';

/// 补充模块（决定卡片标题、图标与空态文案）。
enum DzjExtraModule {
  /// 本学期选修课程（组件 `u:94cf8d7765b0`：`data/get` 出门数、`data/search` 出课程清单）。
  courses(
    'courses',
    '本学期课程',
    Icons.menu_book_outlined,
    Colors.teal,
    '本学期没有读到选课记录。',
  ),

  /// 图书馆座位预约（组件 `u:9b48c5bf91ad`，实测本年 52 条）。
  seat(
    'seat',
    '图书馆座位预约',
    Icons.event_seat_outlined,
    Colors.indigo,
    '本年没有座位预约记录。',
  ),

  /// 奖助贷勤：助学金（`u:631a812c461d`）+ 勤工助学（`u:b54d6f93ff2e`）。
  /// 奖学金（`u:2573d62e3214`）已在首屏「奖助学金」卡里。
  aid(
    'aid',
    '助学金与勤工助学',
    Icons.volunteer_activism_outlined,
    Colors.orange,
    '没有助学金 / 勤工助学记录。',
  );

  const DzjExtraModule(this.key, this.title, this.icon, this.accent, this.emptyText);

  final String key;
  final String title;
  final IconData icon;

  /// 卡片主色（由界面层过 `AppColors.tone`）。
  final MaterialColor accent;

  final String emptyText;

  static DzjExtraModule? fromKey(String key) {
    for (final m in values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// 一条信息：左边一句说明、右边一个值、可选一行小字。
///
/// 刻意做成「标签 / 值 / 说明」三元组：三个模块的服务端列名各不相同
/// （`kcmc`+`kcxf`、`ndkh`+`mc`+`khnd`、`zxjlb`+`shzt`），但落到界面都是同一行样式，
/// 解析时各自映射到这三个字段即可 —— 界面层不需要认识任何一个服务端列名。
class DzjInfoItem {
  final String label;
  final String value;
  final String detail;

  const DzjInfoItem({required this.label, this.value = '', this.detail = ''});

  bool get isEmpty => label.isEmpty && value.isEmpty && detail.isEmpty;
}

/// 一个模块的结果：条目 + 说明（空态文案 / 总条数）。
class DzjExtraBlock {
  final DzjExtraModule module;
  final List<DzjInfoItem> items;

  /// 服务端总数（可能大于 [items] 的条数 —— 界面按页取前 N 条）。
  final int total;

  const DzjExtraBlock({
    required this.module,
    required this.items,
    this.total = 0,
  });

  bool get isEmpty => items.isEmpty;
}

/// 整份补充信息：模块 key → 结果块（**只含成功的模块**；失败的模块直接缺席）。
class DzjExtraInfo {
  final Map<String, DzjExtraBlock> blocks;

  const DzjExtraInfo({this.blocks = const {}});

  static const DzjExtraInfo empty = DzjExtraInfo();

  DzjExtraBlock? block(DzjExtraModule module) => blocks[module.key];

  bool get isEmpty => blocks.isEmpty;
}

// ---- 行解析（服务端列名 → DzjInfoItem）----

/// 取字符串（容错：任意值 → 字符串，空值 → 空串）。
String dzjText(Object? v) {
  if (v == null) return '';
  final s = v.toString().trim();
  return s == 'null' ? '' : s;
}

/// 数字（容错）：数字 / 数字字符串 → 去掉多余的 `.0`；其余原样。
String dzjNumText(Object? v) {
  final s = dzjText(v);
  final n = double.tryParse(s);
  if (n == null) return s;
  return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

/// 本学期选修课程行 → 条目（`kcmc` 课程名 / `kcxf` 学分 / `kclb` 类别 / `khfs` 考核方式）。
DzjInfoItem? dzjCourseItem(Map<String, dynamic> row) {
  final name = dzjText(row['kcmc']);
  if (name.isEmpty) return null;
  final credit = dzjNumText(row['kcxf']);
  final kind = dzjText(row['kclb']);
  final exam = dzjText(row['khfs']);
  return DzjInfoItem(
    label: name,
    value: credit.isEmpty ? '' : '$credit 学分',
    detail: [kind, exam].where((s) => s.isNotEmpty).join(' · '),
  );
}

/// 座位预约行 → 条目（`ndkh` 馆-楼层 / `mc` 状态 / `khnd` 时间段）。
DzjInfoItem? dzjSeatItem(Map<String, dynamic> row) {
  final place = dzjText(row['ndkh']);
  final status = dzjText(row['mc']);
  final span = dzjText(row['khnd']);
  if (place.isEmpty && status.isEmpty && span.isEmpty) return null;
  return DzjInfoItem(
    label: place.isEmpty ? '图书馆座位' : place,
    value: status,
    detail: span,
  );
}

/// 助学金行 → 条目（`zxjlb` 类别 / `hdnf` 年份 / `shzt` 审核状态(金额)）。
DzjInfoItem? dzjGrantItem(Map<String, dynamic> row) {
  final kind = dzjText(row['zxjlb']);
  if (kind.isEmpty) return null;
  return DzjInfoItem(
    label: kind,
    value: dzjText(row['shzt']),
    detail: dzjText(row['hdnf']),
  );
}

/// 勤工助学行 → 条目（`gwmc` 岗位 / `gwssdw` 单位 / `sgnf` 上岗年份）。
DzjInfoItem? dzjWorkStudyItem(Map<String, dynamic> row) {
  final post = dzjText(row['gwmc']);
  if (post.isEmpty) return null;
  return DzjInfoItem(
    label: post,
    value: dzjText(row['gwssdw']),
    detail: dzjText(row['sgnf']),
  );
}

/// 行集 → 条目集（丢掉解析不出来的行，保持服务端顺序）。
List<DzjInfoItem> dzjItemsOf(
  Iterable<Map<String, dynamic>> rows,
  DzjInfoItem? Function(Map<String, dynamic>) parse,
) {
  final out = <DzjInfoItem>[];
  for (final r in rows) {
    final item = parse(r);
    if (item != null && !item.isEmpty) out.add(item);
  }
  return out;
}
