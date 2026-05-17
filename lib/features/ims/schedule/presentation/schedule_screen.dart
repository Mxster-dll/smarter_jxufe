import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  List<List<String>>? _tableData;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 第一步：异步获取仓库实例
      final repository = await ref.read(scheduleRepositoryProvider.future);
      // 第二步：异步获取课表数据
      final data = await repository.getSchedule();
      setState(() {
        _tableData = data;
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
    return Scaffold(
      appBar: AppBar(title: const Text('课程表')),
      body: _buildBody(),
    );
  }

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
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_tableData == null || _tableData!.isEmpty) {
      return const Center(child: Text('暂无课表数据'));
    }
    return _buildTable(_tableData!);
  }

  Widget _buildTable(List<List<String>> tableData) {
    final rowCount = tableData.length;
    final colCount = tableData[0].length; // 应该是7

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Table(
          border: TableBorder.all(),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            // 表头（无节次列）
            TableRow(
              decoration: const BoxDecoration(color: Colors.grey),
              children: [
                for (int i = 0; i < colCount; i++)
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          _weekdayName(i),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // 数据行（无节次列）
            for (int i = 0; i < rowCount; i++)
              TableRow(
                children: [
                  for (int j = 0; j < colCount; j++)
                    TableCell(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 150),
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          tableData[i][j].isEmpty ? ' ' : tableData[i][j],
                          style: const TextStyle(fontSize: 12),
                          softWrap: true,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _weekdayName(int index) =>
      ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][index];
}
