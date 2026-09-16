/// 学期码阵列选择器（用户 2026-09-15 口径）。
///
/// 用户原话：「我希望你做一个学期选择器，以阵列显示如下文本
/// `251 261 271 / 252 262 273 / 253 263 273`，其中 xxy 代表 xx-(xx+1) 学年，
/// y=1 第一学期、y=2 第二学期、y=3 第二阶段；故阵列是固定三行，左右延伸，
/// 范围可选。」
///
/// 落到此处：**固定三行**（行 = 学段 1/2/3），**列 = 学年**（左右延伸，范围由
/// 调用方给 `startYear ~ endYear`），格子内即学期码文本本身。
///
/// 与 `academic_year_picker.dart`（左右滑动选学年）并列存在：那个仍然服务桌面端
/// 标题栏的「学年 + 学段」两个选择器；手机端合并成 [SchoolTermCodeButton] +
/// 本选择器。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';

/// 显示学期码的入口（手机端标题栏的「学年 + 学段」合并入口）。
///
/// 用户 2026-09-15 裁定：「此按钮不要显示边框，不要显示下拉 icon，只显示 xxy
/// 学期的字样」→ 因此这里**只有一行纯文字**（无 `OutlinedButton`/无
/// `arrow_drop_down`），点击区域靠 [padding] 撑开，整块仍可点。
/// ⚠ 改字号或内边距时同步 `ScheduleTitleBar.rowNeed` 的宽度计算（它用
/// [fontSizeOf] 与 [padding] 现场量宽）。
class SchoolTermCodeButton extends StatelessWidget {
  const SchoolTermCodeButton({
    super.key,
    required this.code,
    required this.onPressed,
    this.compact = true,
  });

  /// 学期码，如 `261`。
  final String code;
  final VoidCallback onPressed;
  final bool compact;

  /// 单侧水平内边距（点击留白）。
  static const double padding = 6;

  /// 单侧垂直内边距（点击留白）。
  static const double verticalPadding = 6;

  /// 字号（`rowNeed` 量宽必须用同一个值）。
  static double fontSizeOf(bool compact) => compact ? 15 : 16;

  /// 按钮文案 = 学期码 + 「学期」二字（用户 2026-09-15：
  /// 「学期切换按钮后要有『学期』二字」→ 显示 `261 学期`）。
  ///
  /// ⚠ `rowNeed` 必须用本函数量宽，别在那边另写一份拼接。
  static String labelOf(String code) => '$code 学期';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '选择学期',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: padding,
            vertical: verticalPadding,
          ),
          child: Text(
            labelOf(code),
            style: TextStyle(
              fontSize: fontSizeOf(compact),
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// 学期码阵列：固定 3 行（学段）× N 列（学年 `startYear ~ endYear`）。
class SchoolTermGrid extends StatelessWidget {
  const SchoolTermGrid({
    super.key,
    required this.startYear,
    required this.endYear,
    required this.selectedXn,
    required this.selectedXq,
    required this.onSelected,
    this.compact = true,
  });

  final int startYear;
  final int endYear;
  final int selectedXn;
  final int selectedXq;
  final ValueChanged<({int xn, int xq})> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = startYear; y <= endYear; y++) y];
    if (years.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('schoolTermGrid'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var xq = 0; xq < 3; xq++)
          Row(
            key: Key('schoolTermRow-${xq + 1}'),
            mainAxisSize: MainAxisSize.min,
            children: [for (final y in years) _cell(context, y, xq)],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, int xn, int xq) {
    final scheme = Theme.of(context).colorScheme;
    final code = schoolTermCode(xn, xq);
    final selected = xn == selectedXn && xq == selectedXq;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: Key('schoolTermCell-$code'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected((xn: xn, xq: xq)),
            child: SizedBox(
              height: compact ? 40 : 46,
              child: Center(
                child: Text(
                  code,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹出学期选择器；用户取消返回 null。
///
/// 作为 `Future` 返回选中学期，调用方自己决定怎么用（课表页 = 改学年 + 学段）。
Future<({int xn, int xq})?> showSchoolTermPicker(
  BuildContext context, {
  required int startYear,
  required int endYear,
  required int selectedXn,
  required int selectedXq,
  bool compact = true,
}) {
  return showDialog<({int xn, int xq})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.calendar_month_outlined),
      title: const Text('选择学期'),
      // AlertDialog 禁放 viewport 类组件（见 AGENTS §3.1）→ 纯 Column。
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前：${schoolTermLabel(selectedXn, selectedXq)}'
            '（${schoolTermCode(selectedXn, selectedXq)}）',
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SchoolTermGrid(
            startYear: startYear,
            endYear: endYear,
            selectedXn: selectedXn,
            selectedXq: selectedXq,
            compact: compact,
            onSelected: (term) => Navigator.of(dialogContext).pop(term),
          ),
          const SizedBox(height: 10),
          Text(
            'xxy：xx-(xx+1) 学年 · y=1 第一学期 / 2 第二学期 / 3 第二阶段',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
