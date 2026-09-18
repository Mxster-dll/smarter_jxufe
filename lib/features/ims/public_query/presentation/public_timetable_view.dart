import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

/// 一张对象课表（一个班 / 一位教师 / 一间教室 / 一门课程）的周网格卡片。
///
/// 行 = 大节（行序取自格子里的 `periodIndex`，标签取真实节次区间，
/// 江财当前是 `1-2 / 3-5 / 6-7 / 8-9 / 10-12` 五档），列 = 周一~周日。
class PublicTimetableCard extends StatelessWidget {
  final PublicTimetable timetable;

  /// 默认是否展开网格（教室课表可能一次返回整栋楼的上百间）。
  final bool initiallyExpanded;

  /// 点某个格子。
  final void Function(PublicTimetableCell cell)? onTapCell;

  const PublicTimetableCard({
    super.key,
    required this.timetable,
    this.initiallyExpanded = true,
    this.onTapCell,
  });

  static const _dayNames = ['一', '二', '三', '四', '五', '六', '日'];

  /// 大节序号 → 实际节次区间（从格子自身反推，避免硬编码作息）。
  Map<int, (int start, int end)> get _periodSpans {
    final spans = <int, (int, int)>{};
    for (final c in timetable.cells) {
      spans[c.periodIndex] = (c.startPeriod, c.endPeriod);
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spans = _periodSpans;
    final periods = spans.keys.toList()..sort();

    return Card(
      elevation: 0,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            timetable.owner.isEmpty ? '（未命名）' : timetable.owner,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            timetable.subtitle.isEmpty
                ? '${timetable.cells.length} 个上课格子'
                : timetable.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          children: [
            if (timetable.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_busy_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '该对象本学期没有排课记录。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _header(context),
              for (final p in periods) _row(context, p, spans[p]!),
              if (timetable.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in timetable.notes.take(8))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            note,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          for (final d in _dayNames)
            Expanded(
              child: Center(
                child: Text(
                  '周$d',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    int periodIndex,
    (int start, int end) span,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final label = span.$1 == span.$2 ? '${span.$1}节' : '${span.$1}-${span.$2}节';
    final byCell = <int, PublicTimetableCell>{
      for (final c in timetable.cells)
        if (c.periodIndex == periodIndex) c.weekday: c,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      // ⚠️ 这里**不能**用 `CrossAxisAlignment.stretch`：本卡片挂在滚动页的
      // 无界高度里（ListView 子项），stretch 会给第一个非弹性子项（左侧行标签
      // `SizedBox`）传 `BoxConstraints.tightFor(height: Infinity)` → 触发
      // `BoxConstraints forces an infinite height` → 整张卡片布局失败、网格整片空白
      // （实测：查询成功只显示「查询到 N 个…的课表」，课表画不出来）。
      // 用 `start`：格子按 `minHeight` 自然撑高，行高不再依赖父级有界高度。
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _cell(context, byCell[d]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, PublicTimetableCell? cell) {
    final scheme = Theme.of(context).colorScheme;
    if (cell == null) {
      return Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: AppColors.hairline(context, 0.5),
          ),
        ),
      );
    }
    return Tooltip(
      message: '${cell.slotLabel} · ${cell.weekLabel}\n${cell.text}',
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTapCell == null ? null : () => onTapCell!(cell),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.tint(context, fp(context).cardAccent, 0.10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: fp(context).cardAccent.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _primaryText(cell),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
              Text(
                cell.weekLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 格子首行显示哪一段：跳过纯数字（学分）与纯周次段。
  static String _primaryText(PublicTimetableCell cell) {
    for (final p in cell.parts) {
      if (RegExp(r'^[\d.]+$').hasMatch(p)) continue;
      if (RegExp(r'^\[[\d\-\s]+\]周?').hasMatch(p)) continue;
      if (RegExp(r'^\d+(-\d+)?节$').hasMatch(p)) continue;
      return p;
    }
    return cell.parts.isEmpty ? '有课' : cell.parts.first;
  }
}
