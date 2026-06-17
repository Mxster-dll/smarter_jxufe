import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const ScheduleScreen({super.key, this.showAppBar = true});

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
    final body = _buildBody();

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(title: const Text('课程表'), centerTitle: true),
        body: body,
      );
    }
    return body;
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
    return _buildTable(context, _tableData!);
  }

  Widget _buildTable(BuildContext context, List<List<String>> tableData) {
    final rowCount = tableData.length;
    final colCount = tableData[0].length;
    const headerColor = Color(0xFFC62828); // 深红表头
    const altColor = Color(0xFFFFF5F5); // 极浅红交替行

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: IntrinsicWidth(
          child: Card(
            clipBehavior: Clip.antiAlias,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: SingleChildScrollView(
                child: Table(
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Colors.red.shade100, width: 0.5),
                  ),
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: headerColor),
                      children: [
                        for (int i = 0; i < colCount; i++)
                          TableCell(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Center(
                                child: Text(
                                  _weekdayName(i),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (int i = 0; i < rowCount; i++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: i.isOdd ? altColor : null,
                        ),
                        children: [
                          for (int j = 0; j < colCount; j++)
                            TableCell(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 150,
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  tableData[i][j].isEmpty
                                      ? ' '
                                      : tableData[i][j],
                                  style: const TextStyle(fontSize: 13),
                                  softWrap: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int index) =>
      ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][index];
}
