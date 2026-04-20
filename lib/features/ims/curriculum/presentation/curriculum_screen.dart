import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_viewmodel_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table.dart';

class CurriculumScreen extends ConsumerWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(curriculumViewModelProvider);
    final viewModel = ref.read(curriculumViewModelProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('培养方案查询')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildYearDropdown(state, viewModel)),
                const SizedBox(width: 16),
                Expanded(child: _buildCollegeDropdown(state, viewModel)),
                const SizedBox(width: 16),
                Expanded(child: _buildMajorDropdown(state, viewModel)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildTable(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildYearDropdown(
    CurriculumState state,
    CurriculumViewModel viewModel,
  ) {
    return DropdownButtonFormField<int>(
      initialValue: state.selectedYear,
      hint: const Text('选择年份'),
      items: state.years
          .map((year) => DropdownMenuItem(value: year, child: Text('$year年')))
          .toList(),
      onChanged: viewModel.onYearChanged,
    );
  }

  Widget _buildCollegeDropdown(
    CurriculumState state,
    CurriculumViewModel viewModel,
  ) {
    if (state.isLoadingColleges) {
      return const Center(child: CircularProgressIndicator());
    }
    return DropdownButtonFormField<College>(
      initialValue: state.selectedCollege,
      hint: const Text('选择学院'),
      items: state.colleges
          .map(
            (college) => DropdownMenuItem(
              value: college,
              child: Text(college.standardName),
            ),
          )
          .toList(),
      onChanged: viewModel.onCollegeChanged,
    );
  }

  Widget _buildMajorDropdown(
    CurriculumState state,
    CurriculumViewModel viewModel,
  ) {
    final enabled = state.selectedCollege != null && state.selectedYear != null;
    if (!enabled) {
      return DropdownButtonFormField<Major>(
        hint: const Text('请先选择学院和年份'),
        items: const [],
        onChanged: null,
      );
    }
    if (state.isLoadingMajors) {
      return const Center(child: CircularProgressIndicator());
    }
    return DropdownButtonFormField<Major>(
      initialValue: null,
      hint: const Text('选择专业'),
      items: state.majors
          .map(
            (major) =>
                DropdownMenuItem(value: major, child: Text(major.standardName)),
          )
          .toList(),
      onChanged: viewModel.onMajorChanged,
    );
  }

  Widget _buildTable(CurriculumState state) {
    if (state.isLoadingTable) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return Center(child: Text(state.errorMessage!));
    }
    if (state.curriculum == null) {
      return const Center(child: Text('请选择专业查看培养方案'));
    }

    final colMapper = <String, String Function(Course)>{
      '课程代码': (c) => c.code,
      '课程名称': (c) => c.name,
      '学分': (c) => c.credit.toStringAsFixed(1),
      '课程大类': (c) => c.mainCategory,
      '二级分类': (c) => c.subCategory,
      '三级分类': (c) => c.tertiaryCategory ?? '',
      '课程地位': (c) => c.requirement.name,
      '课程性质': (c) => c.importance == .core ? c.importance.name : '',
      '考核方式': (c) => c.assessmentMethod.name,
      '总学时': (c) => c.creditHour.total.toString(),
      '讲授学时': (c) => c.creditHour.lecture.toString(),
      '实验学时': (c) => c.creditHour.lab.toString(),
      '实践学时': (c) => c.creditHour.practice.toString(),
      '其他学时': (c) => c.creditHour.other.toString(),
      '周学时': (c) => c.creditHour.weekly.toStringAsFixed(1),
      '标识': (c) => c.identification,
    };

    final colHeaders = colMapper.keys.toList();
    final courses = state.curriculum!.courses;
    final cells = List.generate(
      courses.length,
      (rowIndex) => colHeaders
          .map((col) => Text(colMapper[col]!(courses[rowIndex])))
          .toList(),
    );

    const cellWidth = 100.0;
    const cellHeight = 40.0;

    return ReorderableTable(
      fixedRowHeaders: true,
      colHeaders: colHeaders,
      rowHeaders: List.generate(cells.length, (i) => i.toString()),
      cells: cells,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      enableRowHeaderCollapse: true,
      rowHeadersCollapsed: true,
    );
  }
}
