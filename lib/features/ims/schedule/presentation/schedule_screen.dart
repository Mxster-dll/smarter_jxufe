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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        // 计算每行高度，使表格填满页面
        final availHeight = constraints.maxHeight - 24; // 减去外边距
        final headerH = isNarrow ? 28.0 : 44.0;
        final rowH = rowCount > 0
            ? ((availHeight - headerH) / rowCount).clamp(28.0, 200.0)
            : 60.0;

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
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    child: Table(
                      border: TableBorder.symmetric(
                        inside: BorderSide(
                          color: Colors.red.shade100,
                          width: 0.5,
                        ),
                      ),
                      defaultColumnWidth: isNarrow
                          ? const FixedColumnWidth(36)
                          : const IntrinsicColumnWidth(),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: headerColor),
                          children: [
                            for (int i = 0; i < colCount; i++)
                              TableCell(
                                child: SizedBox(
                                  height: headerH,
                                  child: Center(
                                    child: Text(
                                      _weekdayName(i, compact: isNarrow),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: isNarrow ? 10 : 14,
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
                                  child: SizedBox(
                                    height: rowH,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: isNarrow ? 36 : 150,
                                      ),
                                      padding: EdgeInsets.all(
                                        isNarrow ? 2 : 10,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _cellText(
                                          tableData[i][j],
                                          compact: isNarrow,
                                        ),
                                        style: TextStyle(
                                          fontSize: isNarrow ? 10 : 13,
                                        ),
                                        softWrap: true,
                                        textAlign: TextAlign.center,
                                      ),
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
      },
    );
  }

  /// 提取单元格显示文本：窄屏显示课程名+教师+教室，宽屏显示全部。
  String _cellText(String raw, {required bool compact}) {
    if (raw.isEmpty) return ' ';
    if (!compact) return raw;
    // 按行拆分，取前3行：课程名、教师、教室
    final lines = raw
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return ' ';
    // 取前3行，用换行连接
    final display = lines.take(3).join('\n');
    return display.isEmpty ? ' ' : display;
  }

  String _weekdayName(int index, {bool compact = false}) {
    const full = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    const compactList = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return compact ? compactList[index] : full[index];
  }
}
