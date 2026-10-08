/// 电费页 · 纯辅助件与**只收显式 `context`** 的渲染件（顶层函数）。
///
/// 拆分自 `electricity_screen.dart`（2026-10-08 架构审计第三轮）：那个 State 1146 行、
/// 55 个成员（19 个是字段）。这里放的两类东西**都不碰字段 / `widget` / `setState`**：
/// ① 纯函数（`elMessageOf` / `elBuildingGroupKey` / `elBuildingShortName` /
/// `elCompareBuildingNames` / `elSortBuildingGroup`）；
/// ② 渲染件（`elDialogGroupHeader` / `elDialogChip` / `elBuildRecordRow` / `elCampusPill` /
/// `elSelectCard`）—— 它们的 `BuildContext` **本来就是显式参数**，所以能整块搬。
///
/// ⚠ 仍在 State 里的是**读字段的那批**（`build` / `_buildRecords` / `_buildDormCard` /
/// `_buildResult` / `_buildingBlocks` / `_roomBlocks` 与全部 `_load*` / `_pick*`）——
/// 要么收数据参数、要么留在 State（口径见 AGENTS.md §33.4.4）。
library;

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';

String elMessageOf(Object e) =>
    e is ElectricityApiException ? e.message : e.toString();

// ---------- 楼栋聚合分组 ----------

String elBuildingGroupKey(String name) {
  final match = RegExp(r'^(.*?)([0-9]+|[A-Za-z])栋$').firstMatch(name);
  if (match == null) return name;
  final prefix = match.group(1)!;
  return prefix.isEmpty ? name : prefix;
}

String elBuildingShortName(String name) {
  final match = RegExp(r'^.*?([0-9]+|[A-Za-z])栋$').firstMatch(name);
  if (match == null) return name;
  return '${match.group(1)}栋';
}

List<RoomNode> elSortBuildingGroup(List<RoomNode> group) {
  final sorted = [...group];
  sorted.sort((a, b) => elCompareBuildingNames(a.name, b.name));
  return sorted;
}

int elCompareBuildingNames(String a, String b) {
  String? tailOf(String name) {
    final m = RegExp(r'^.*?([0-9]+|[A-Za-z])栋$').firstMatch(name);
    return m?.group(1);
  }

  final at = tailOf(a);
  final bt = tailOf(b);
  if (at == null || bt == null) {
    if (at != null) return -1;
    if (bt != null) return 1;
    return a.compareTo(b);
  }
  final an = int.tryParse(at);
  final bn = int.tryParse(bt);
  if (an != null && bn != null) return an - bn;
  if (an != null) return -1;
  if (bn != null) return 1;
  return at.compareTo(bt);
}

Widget elDialogGroupHeader(BuildContext context, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
        letterSpacing: 0.2,
      ),
    ),
  );
}

Widget elDialogChip({
  required BuildContext context,
  required Widget child,
  required bool selected,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: selected ? scheme.primary : scheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
          child: child,
        ),
      ),
    ),
  );
}

Widget elBuildRecordRow(BuildContext context, ChargingRecord record) {
  final scheme = Theme.of(context).colorScheme;
  final time = record.paidAt;
  final timeText = time == null
      ? ''
      : '${time.year}-${time.month.toString().padLeft(2, '0')}-'
            '${time.day.toString().padLeft(2, '0')} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}';
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tint(context, scheme.primary, 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.add_card_outlined,
            size: 17,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.remark.isEmpty ? '电费充值' : record.remark,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (record.payTypeName.isNotEmpty) record.payTypeName,
                  if (timeText.isNotEmpty) timeText,
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '+${record.amountYuan.toStringAsFixed(2)} 元',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

Widget elCampusPill(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: selected ? scheme.primary : scheme.surface,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    ),
  );
}

/// App 同源选择卡：白底细描边圆角 8 + 主色浅底图标盒；
/// 选中后主色描边 + 淡底 + 勾选。
Widget elSelectCard({
  required BuildContext context,
  required IconData icon,
  required bool selected,
  required bool loading,
  required String? value,
  required String placeholder,
  VoidCallback? onTap,
}) {
  final scheme = Theme.of(context).colorScheme;
  return AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    decoration: BoxDecoration(
      color: selected
          ? AppColors.tint(context, scheme.primary, 0.05)
          : scheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 1.4 : 1,
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, scheme.primary, 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: loading
                    ? Text(
                        '查询中…',
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        value ?? placeholder,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: value != null ? 14.5 : 15,
                          fontWeight: value != null
                              ? FontWeight.w500
                              : FontWeight.w400,
                          height: 1.3,
                          color: value != null
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onTap == null)
                const SizedBox.shrink()
              else if (selected)
                Icon(Icons.edit_outlined, size: 18, color: scheme.primary)
              else
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
