/// 「找空闲教室」的两个结果视图（**纯展示**：数据由页面算好后传进来）。
///
/// - [ClassroomFreeListView] = 模式 A「按时间找教室」的清单（SB11 口径）；
/// - [ClassroomRoomFreeView] = 模式 B「按教室查空闲」的本周空闲 + 整学期固定空闲（SB12 口径）。
///
/// 算法全在 `domain/classroom_free.dart` 里（纯函数，可脱网单测）；
/// 这里只负责画，因此也能在 widget 测试里直接喂假数据。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/section_title.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/classroom_free.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/free_time_view.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 一节 = 一条「周几第几节」的短标签（`周三 3-5 节`）。
String classroomSlotLabel(FreeWindow window) {
  final range = window.startPeriod == window.endPeriod
      ? '${window.startPeriod} 节'
      : '${window.startPeriod}-${window.endPeriod} 节';
  return '${weekdayLabel(window.weekday)} $range';
}

/// 分楼层的组标题（结果清单与选教室弹层共用同一形状：3px 竖条 + `楼名 · N 楼 · M 间`）。
///
/// 用户 2026-09-19：「查找空教室功能，教室应该分楼层显示」。
Widget classroomFloorHeader(
  BuildContext context, {
  required String label,
  required int count,
  String unit = '间',
}) {
  return Padding(
    key: Key('classroomFloorHeader-$label'),
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
    child: Row(
      children: [
        appSectionTitle(
          context,
          text: '$label · $count $unit',
          accent: fp(context).publicQuery,
        ),
      ],
    ),
  );
}

/// 模式 A 结果清单（**按楼房 + 楼层分组**，见 [groupFreeHitsByFloor]）。
class ClassroomFreeListView extends StatefulWidget {
  const ClassroomFreeListView({
    super.key,
    required this.hits,
    required this.totalRooms,
    required this.week,
    required this.weekdays,
    required this.periodLabel,
    this.onPick,
    this.maxShown = 40,
  });

  final List<ClassroomFreeHit> hits;

  /// 该范围内一共有多少间教室（分母；免责说明用）。
  final int totalRooms;

  final int week;
  final List<int> weekdays;

  /// 选中的节次档文案（可能多档：`1-2 节 + 3-5 节`，见 [classroomPeriodBlocksLabel]）。
  final String periodLabel;

  /// 点某一行（页面据此跳到模式 B 看这间教室的整学期空闲）。
  final ValueChanged<ClassroomOccupancy>? onPick;

  final int maxShown;

  @override
  State<ClassroomFreeListView> createState() => _ClassroomFreeListViewState();
}

class _ClassroomFreeListViewState extends State<ClassroomFreeListView> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final hits = widget.hits;
    final shown = _showAll || hits.length <= widget.maxShown
        ? hits
        : hits.sublist(0, widget.maxShown);
    final allFree = hits.where((h) => h.allFree).length;
    // 教学楼 + 楼层分组（只对**当前展示的**那批分组，折叠时组内计数即所见条数）。
    final groups = groupFreeHitsByFloor(shown);
    final dayText = widget.weekdays.map(weekdayLabel).join('、');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: geCardShape(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Icon(
                  hits.isEmpty ? Icons.search_off : Icons.meeting_room_outlined,
                  size: 22,
                  color: hits.isEmpty
                      ? Theme.of(context).colorScheme.error
                      : AppColors.success(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hits.isEmpty
                            ? '这个时段没有空闲教室'
                            : '第 ${widget.week} 周 · $dayText · '
                                  '${widget.periodLabel} · '
                                  '${hits.length} 间空（共 ${widget.totalRooms} 间）',
                        key: const Key('classroomFreeSummary'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hits.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          allFree == hits.length
                              ? '全部这些教室在所选的每一天都空着'
                              : '其中 $allFree 间在所选的每一天都空着，其余只空了一部分',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (hits.isEmpty)
          Card(
            elevation: 0,
            shape: geCardShape(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Text(
                '换一个周次或节次再看看；如果整栋楼都满了，试试不选楼房看整个校区。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
          )
        else
          for (final group in groups) ...[
            classroomFloorHeader(
              context,
              label: group.label,
              count: group.count,
            ),
            // 用户 2026-09-20：「教室列表不要显示为按钮，而是一个个胶囊，并按楼层分组
            // 显示出来」→ 每个楼层一张卡，卡内是**胶囊流**（Wrap），不再是整行按钮。
            Card(
              elevation: 0,
              shape: geCardShape(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final hit in group.items)
                      _FreeRoomPill(hit: hit, onPick: widget.onPick),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        if (hits.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('classroomFreeShowAll'),
                onPressed: () => setState(() => _showAll = true),
                icon: const Icon(Icons.unfold_more, size: 18),
                label: Text('显示其余 ${hits.length - shown.length} 间'),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一间空闲教室 = **一枚胶囊**（用户 2026-09-20：「一个个胶囊」）。
///
/// - `allFree`（所选的每一天都空）→ 实心淡绿 + 绿字，一眼可辨；
/// - 只空了一部分 → 描边胶囊 + 名字前一颗警示点，**具体哪几天空进 tooltip**
///   （原来的两行说明文字塞不进胶囊，而详情点开胶囊就能在模式 B 看全）。
class _FreeRoomPill extends StatelessWidget {
  const _FreeRoomPill({required this.hit, this.onPick});

  final ClassroomFreeHit hit;
  final ValueChanged<ClassroomOccupancy>? onPick;

  @override
  Widget build(BuildContext context) {
    final room = hit.room;
    final ok = AppColors.success(context);
    final meta = [
      if (room.building.isNotEmpty) room.building,
      if (room.capacity > 0) '${room.capacity} 座',
      if (room.kind.isNotEmpty) room.kind,
    ].join(' · ');
    final tip = [
      '${room.name}${hit.allFree ? '：所选的每一天都空' : '：${hit.detail}'}',
      if (meta.isNotEmpty) meta,
      if (onPick != null) '点一下看这间教室的整学期空闲',
    ].join('\n');
    return Tooltip(
      key: Key('classroomFreeRow-${room.name}'),
      message: tip,
      child: Material(
        color: hit.allFree ? AppColors.tint(context, ok, 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: hit.allFree
                ? ok.withValues(alpha: 0.35)
                : AppColors.stroke(context),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPick == null ? null : () => onPick!(room),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hit.allFree) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.caution(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  room.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: hit.allFree ? ok : AppColors.textBase(context),
                  ),
                ),
                if (room.capacity > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${room.capacity} 座',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 模式 B 结果：这间教室**本周**的空闲时段 + **整学期每周都空**的固定时段。
class ClassroomRoomFreeView extends StatelessWidget {
  const ClassroomRoomFreeView({
    super.key,
    required this.room,
    required this.week,
    required this.lastWeek,
    required this.commonWindows,
    this.includeWeekend = true,
    this.minPeriods = 1,
    this.onWeekChanged,
  });

  final ClassroomOccupancy room;
  final int week;
  final int lastWeek;

  /// 整学期（第 1…[lastWeek] 周）每周都空的时段，由页面用
  /// `roomCommonFreeWindows` 算好传进来。
  final List<FreeWindow> commonWindows;

  final bool includeWeekend;
  final int minPeriods;
  final ValueChanged<int>? onWeekChanged;

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).publicQuery;
    final meta = [
      if (room.building.isNotEmpty) room.building,
      if (room.capacity > 0) '${room.capacity} 座',
      if (room.kind.isNotEmpty) room.kind,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: geCardShape(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              key: const Key('classroomRoomHeader'),
              children: [
                Icon(Icons.meeting_room_outlined, size: 22, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        room.slots.isEmpty
                            ? '教务本学期没有给它排课 —— 整学期都空着'
                            : '本学期 ${room.slots.length} 条排课安排'
                                  '${meta.isEmpty ? '' : ' · $meta'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var w = 1; w <= lastWeek; w++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('classroomRoomWeek-$w'),
                    label: Text('第 $w 周'),
                    selected: w == week,
                    onSelected: (_) => onWeekChanged?.call(w),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FreeTimeView(
          columns: [
            PublicScheduleColumn(owner: room.name, slots: room.slots),
          ],
          week: week,
          maxPeriod: 12,
          includeWeekend: includeWeekend,
          minPeriods: minPeriods,
          periodStarts: const {},
        ),
        const SizedBox(height: 20),
        geCardTitle(
          context,
          text: '整学期固定空闲（第 1-$lastWeek 周每周都空）',
          accent: accent,
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          shape: geCardShape(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: commonWindows.isEmpty
                ? Text(
                    room.slots.isEmpty
                        ? '整学期没有任何排课 —— 周一到周日、1-12 节随时可用。'
                        : '没有「每周都空」的时段（这间教室的排课每周不一样）。'
                              '上面按周次翻，能看到单周的完整空闲。',
                    key: const Key('classroomRoomCommonEmpty'),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.textMuted(context),
                    ),
                  )
                : Wrap(
                    key: const Key('classroomRoomCommon'),
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final w in commonWindows)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tint(context, accent, 0.09),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            classroomSlotLabel(w),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
