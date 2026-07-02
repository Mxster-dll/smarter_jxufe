import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ScheduleScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  List<ScheduleEntry>? _entries;
  String? _error;
  bool _isLoading = true;
  bool _isHorizontal = false;

  int _selectedYear = 2025;
  String _selectedSemester = '0';
  String _serialNo = '';

  @override
  void initState() {
    super.initState();
    _initFromStudentInfo();
  }

  Future<void> _initFromStudentInfo() async {
    try {
      final studentInfoRepo = await ref.read(
        studentInfoRepositoryProvider.future,
      );
      StudentInfo? info;
      studentInfoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      if (info == null) return;
      final si = info!;

      _serialNo = si.serialNo;
      _selectedYear = int.tryParse(si.enrollYear) ?? DateTime.now().year;
      final now = DateTime.now();
      _selectedSemester = now.month >= 3 && now.month <= 8 ? '1' : '0';
    } catch (_) {}
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_serialNo.isEmpty) throw Exception('未获取到学籍信息');

      final repository = await ref.read(scheduleRepositoryProvider.future);
      final data = await repository.getSchedule(
        year: _selectedYear.toString(),
        semester: _selectedSemester,
        studentId: _serialNo,
      );
      setState(() {
        _entries = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        _buildFilters(context),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('课程表'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _loadData,
            ),
          ],
        ),
        body: body,
      );
    }
    return body;
  }

  Widget _buildFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AcademicYearPicker(
            startYear: 2018,
            endYear: 2030,
            initialYear: _selectedYear,
            onChanged: (y) {
              setState(() => _selectedYear = y);
              _loadData();
            },
          ),
          _semesterDropdown(context),
        ],
      ),
    );
  }

  Widget _semesterDropdown(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedSemester,
        isDense: true,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: const [
          DropdownMenuItem(value: '0', child: Text('第一学期')),
          DropdownMenuItem(value: '1', child: Text('第二学期')),
          DropdownMenuItem(value: '2', child: Text('第二阶段')),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() => _selectedSemester = v);
            _loadData();
          }
        },
      ),
    );
  }

  void _toggleView() => setState(() => _isHorizontal = !_isHorizontal);

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text('加载失败: $_error', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_entries == null || _entries!.isEmpty) {
      return const Center(child: Text('暂无课表数据'));
    }

    // 切换按钮内置在课表左上角格子中
    return _isHorizontal
        ? ScheduleHorizontalView(
            entries: _entries!,
            onToggle: _toggleView,
            isHorizontal: _isHorizontal,
          )
        : ScheduleGridView(
            entries: _entries!,
            onToggle: _toggleView,
            isHorizontal: _isHorizontal,
          );
  }
}
