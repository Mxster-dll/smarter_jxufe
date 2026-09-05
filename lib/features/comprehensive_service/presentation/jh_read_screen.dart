import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/jh_read_record.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/jh_read_providers.dart';

/// 蛟湖阅读情况页。
///
/// 展示当前学生在学工平台（SSP）的蛟湖阅读考核记录；
/// 无记录时给出规则引导（入馆学习 + 借阅达标可获得蛟湖阅读学分）。
class JhReadScreen extends ConsumerWidget {
  const JhReadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(jhReadRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('蛟湖阅读'), centerTitle: true),
      body: recordsAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载蛟湖阅读数据...'),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(jhReadRecordsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return _buildEmptyGuide(context, ref);
          }
          return _buildRecordList(context, records);
        },
      ),
    );
  }

  /// 无记录时的规则引导（区别于「加载出错」，说明数据本身为空的原因）。
  Widget _buildEmptyGuide(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Icon(
          Icons.auto_stories_outlined,
          size: 56,
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          '暂无蛟湖阅读考核记录',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '当前账号在学工平台蛟湖阅读详单中暂无记录',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '蛟湖阅读是什么？',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '「蛟湖阅读」是江西财经大学的阅读素养活动：完成图书馆入馆学习，'
                  '并在规定周期内达到借阅数量要求后，由学院（团总支）认定，'
                  '可获得「蛟湖阅读平台」学分（计入第二课堂成绩单）。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: Colors.orange[800],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '还没有记录？',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '记录为空通常意味着：① 尚未完成图书馆入馆学习；'
                  '② 当前周期借阅数量未达标；③ 学院（团总支）尚未完成录入认定。'
                  '可到图书馆完成入馆学习、增加借阅后再回来查看。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => ref.invalidate(jhReadRecordsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordList(BuildContext context, List<JhReadRecord> records) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '共 ${records.length} 条考核记录',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, i) => _buildRecordCard(context, records[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordCard(BuildContext context, JhReadRecord record) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    record.bonusName.isNotEmpty ? record.bonusName : '蛟湖阅读',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                if (record.credit.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Text(
                      '${record.credit} 学分',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _rowItem(context, Icons.badge_outlined, '学号', record.studentId),
            _rowItem(context, Icons.person_outline, '姓名', record.name),
            _rowItem(context, Icons.school_outlined, '学院', record.college),
            _rowItem(context, Icons.groups_outlined, '班级', record.className),
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                _statusPill(
                  context,
                  Icons.assignment_turned_in_outlined,
                  '入馆学习',
                  record.entryLearning,
                ),
                const SizedBox(width: 8),
                _statusPill(
                  context,
                  Icons.library_books_outlined,
                  '借阅合格',
                  record.borrowQualified,
                ),
              ],
            ),
            if (record.detailId.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.open_in_new, size: 13, color: Colors.blue[400]),
                  const SizedBox(width: 6),
                  Text(
                    '学工平台已生成该记录详单',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Icon(icon, size: 14, color: Colors.grey[450]),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final isOk = value == '是';
    final isNo = value == '否';
    final Color bg;
    final Color fg;
    if (isOk) {
      bg = Colors.green[50]!;
      fg = Colors.green[800]!;
    } else if (isNo) {
      bg = Colors.red[50]!;
      fg = Colors.red[700]!;
    } else {
      bg = Colors.grey[100]!;
      fg = Colors.grey[600]!;
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, color: fg)),
            const SizedBox(width: 4),
            Text(
              value.isEmpty ? '未录入' : value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
