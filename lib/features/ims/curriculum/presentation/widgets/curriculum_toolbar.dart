/// 培养方案页的**顶部两块交互区**：范围选择器（年级 / 学院 / 专业）与工具条
/// （搜索 + 分组形态 + 快筛 + 命中计数）。
///
/// 两者都只收**显式参数与回调**，不持有状态、不碰 `WidgetRef`（§3「零件」口径）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_common.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 输入框的 Fluent 描边（控件圆角 4、1px 描边；聚焦时换 accent）。
OutlineInputBorder _fieldBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: FluentRadius.controlAll,
      borderSide: BorderSide(color: color, width: width),
    );

InputDecoration _fieldDecoration(BuildContext context, {String? hint}) {
  final p = fluent(context);
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: p.controlDefault,
    hintText: hint,
    hintStyle: FluentType.body.copyWith(color: p.textTertiary),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: FluentSpacing.md,
      vertical: FluentSpacing.md,
    ),
    border: _fieldBorder(p.strokeControlDefault),
    enabledBorder: _fieldBorder(p.strokeControlDefault),
    focusedBorder: _fieldBorder(p.accent, 1.5),
    disabledBorder: _fieldBorder(p.strokeControlDefault),
  );
}

Widget _labeledField(BuildContext context, String label, Widget field) {
  final p = fluent(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: FluentType.caption.copyWith(color: p.textSecondary)),
      const SizedBox(height: FluentSpacing.xs),
      field,
    ],
  );
}

/// 培养方案范围：年级 / 学院 / 专业。
///
/// 三个下拉都是**真实控件**（`DropdownButtonFormField`），只是换成 Fluent 的
/// 填充与 4px 圆角 —— Flutter 没有 Fluent 版下拉，不为它自己造一个（§13 的取舍）。
class CurriculumSelectorCard extends StatelessWidget {
  const CurriculumSelectorCard({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onYearChanged,
    required this.colleges,
    required this.selectedCollege,
    required this.onCollegeChanged,
    required this.isLoadingColleges,
    required this.majors,
    required this.selectedMajor,
    required this.onMajorChanged,
    required this.isLoadingMajors,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onYearChanged;
  final List<College> colleges;
  final College? selectedCollege;
  final ValueChanged<College?> onCollegeChanged;
  final bool isLoadingColleges;
  final List<Major> majors;
  final Major? selectedMajor;
  final ValueChanged<Major?> onMajorChanged;
  final bool isLoadingMajors;

  @override
  Widget build(BuildContext context) {
    final majorEnabled = selectedCollege != null && selectedYear != null;

    final yearField = _labeledField(
      context,
      '年级',
      DropdownButtonFormField<int>(
        initialValue: selectedYear,
        hint: const Text('选择年份'),
        isExpanded: true,
        decoration: _fieldDecoration(context),
        items: [
          for (final year in years)
            DropdownMenuItem(value: year, child: Text('$year 级')),
        ],
        onChanged: onYearChanged,
      ),
    );

    final collegeField = _labeledField(
      context,
      '学院',
      DropdownButtonFormField<College>(
        initialValue: selectedCollege,
        hint: Text(isLoadingColleges ? '正在加载学院列表…' : '选择学院'),
        isExpanded: true,
        decoration: _fieldDecoration(context),
        items: [
          for (final college in colleges)
            DropdownMenuItem(value: college, child: Text(college.name)),
        ],
        onChanged: isLoadingColleges ? null : onCollegeChanged,
      ),
    );

    final majorField = _labeledField(
      context,
      '专业',
      DropdownButtonFormField<Major>(
        initialValue: selectedMajor,
        hint: Text(
          !majorEnabled
              ? '请先选择学院和年级'
              : (isLoadingMajors ? '正在加载专业列表…' : '选择专业'),
        ),
        isExpanded: true,
        decoration: _fieldDecoration(context),
        items: [
          for (final major in majors)
            DropdownMenuItem(value: major, child: Text(major.name)),
        ],
        onChanged: majorEnabled && !isLoadingMajors ? onMajorChanged : null,
      ),
    );

    return FluentCard(
      padding: const EdgeInsets.all(FluentSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < Breakpoints.narrow) {
            return Column(
              children: [
                yearField,
                const SizedBox(height: FluentSpacing.md),
                collegeField,
                const SizedBox(height: FluentSpacing.md),
                majorField,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: yearField),
              const SizedBox(width: FluentSpacing.md),
              Expanded(flex: 2, child: collegeField),
              const SizedBox(width: FluentSpacing.md),
              Expanded(flex: 2, child: majorField),
            ],
          );
        },
      ),
    );
  }
}

/// 工具条：搜索 + 分组形态 + 快筛 + 命中计数。
class CurriculumToolbar extends StatelessWidget {
  const CurriculumToolbar({
    super.key,
    required this.searchController,
    required this.onQueryChanged,
    required this.mode,
    required this.onModeChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.matchedCount,
    required this.matchedCredits,
    required this.totalCount,
    required this.totalCredits,
    required this.filtered,
    required this.refreshing,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final CurriculumGroupMode mode;
  final ValueChanged<CurriculumGroupMode> onModeChanged;
  final CurriculumQuickFilter filter;
  final ValueChanged<CurriculumQuickFilter> onFilterChanged;
  final int matchedCount;
  final double matchedCredits;
  final int totalCount;
  final double totalCredits;
  final bool filtered;

  /// 正在重取（「刷新必须看得见」，§3）：计数行前面挂一句「正在更新…」。
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    final countText = filtered
        ? '命中 $matchedCount 门 · ${crCreditText(matchedCredits)} 学分'
              '（共 $totalCount 门 · ${crCreditText(totalCredits)} 学分）'
        : '共 $totalCount 门 · ${crCreditText(totalCredits)} 学分';
    final search = TextField(
      controller: searchController,
      onChanged: onQueryChanged,
      style: FluentType.body.copyWith(color: p.textPrimary),
      decoration: _fieldDecoration(context, hint: '搜索课程名 / 课程代码 / 课程类别').copyWith(
        prefixIcon: Icon(Icons.search, size: 18, color: p.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: searchController.text.isEmpty
            ? null
            : FluentIconButton(
                icon: Icons.close,
                tooltip: '清空搜索',
                size: 28,
                iconSize: 16,
                onPressed: () {
                  searchController.clear();
                  onQueryChanged('');
                },
              ),
      ),
    );

    final modes = SegmentedButton<CurriculumGroupMode>(
      segments: [
        for (final value in CurriculumGroupMode.values)
          ButtonSegment(value: value, label: Text(value.label)),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onModeChanged(selection.first),
      style: const ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: FluentRadius.controlAll),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );

    return FluentCard(
      padding: const EdgeInsets.all(FluentSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= Breakpoints.wide;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: FluentSpacing.md),
                    modes,
                  ],
                )
              else ...[
                search,
                const SizedBox(height: FluentSpacing.md),
                // 分段控件在窄屏独占一行、靠左（三档文字最长约 240px，360 宽够放）。
                Align(alignment: Alignment.centerLeft, child: modes),
              ],
              const SizedBox(height: FluentSpacing.md),
              Wrap(
                spacing: FluentSpacing.sm,
                runSpacing: FluentSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final value in CurriculumQuickFilter.values)
                    FluentButton(
                      label: value.label,
                      dense: true,
                      accent: value == filter,
                      onPressed: () => onFilterChanged(value),
                    ),
                ],
              ),
              const SizedBox(height: FluentSpacing.sm),
              Text(
                '${refreshing ? '正在更新… ｜ ' : ''}$countText',
                style: FluentType.caption.copyWith(color: p.textSecondary),
              ),
            ],
          );
        },
      ),
    );
  }
}
