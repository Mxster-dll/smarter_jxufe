import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';

/// 学生个人数据中心（dzj.jxufe.edu.cn）原生聚合页。
///
/// 与网页「个人首页」等价的全量概览：
/// 学籍概要 / 班主任 / 本周课程 / 学业（成绩·绩点·学分）/
/// 基础指标 / 校园卡消费与明细 / 奖助贷勤 / 教材 / 图书借阅 / 门户登录趋势。
class DataCenterScreen extends ConsumerWidget {
  const DataCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(dataCenterOverviewProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('学生个人数据中心'),
        centerTitle: true,
      ),
      body: overviewAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载个人数据中心...'),
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
                  onPressed: () => ref.invalidate(dataCenterOverviewProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (overview) => _buildContent(context, overview),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DataCenterOverview o) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildStudentCard(context, o),
        const SizedBox(height: 12),
        _buildWeekCard(context, o),
        const SizedBox(height: 12),
        _buildAcademicCard(context, o),
        const SizedBox(height: 12),
        _buildPeerCard(context, o),
        const SizedBox(height: 12),
        _buildMetricsCard(context, o),
        const SizedBox(height: 12),
        _buildCardSpendCard(context, o),
        const SizedBox(height: 12),
        _buildTextbookCard(context, o),
        const SizedBox(height: 12),
        _buildBorrowCard(context, o),
        const SizedBox(height: 12),
        _buildAwardCard(context, o),
        const SizedBox(height: 12),
        _buildLoginTrendCard(context, o),
      ],
    );
  }

  // ---- 学籍概要 ----

  Widget _buildStudentCard(BuildContext context, DataCenterOverview o) {
    final name = o.username.isEmpty ? '?' : o.username;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.indigo[100],
              child: Text(
                name.characters.first,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.username,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '校园卡号 ${o.userid}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    o.college,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (o.advisorName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '班主任 ${o.advisorName}${o.advisorPhone.isNotEmpty ? ' · ${o.advisorPhone}' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.blueGrey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 本周课程 ----

  Widget _buildWeekCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note, size: 18, color: Colors.blue[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    o.weekTitle.isEmpty ? '本周课程' : o.weekTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (o.weekDays.isNotEmpty)
                  Text(
                    '今日 ${o.todayClassCount} 节',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
              ],
            ),
            if (o.weekDays.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '暂无课程安排',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: o.weekDays.map((d) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: Text(
                        d.weekday,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 学业情况 ----

  Widget _buildAcademicCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.menu_book, size: 18, color: Colors.deepPurple[500]),
                const SizedBox(width: 6),
                const Text(
                  '学业情况',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '加权平均',
                  value: _fmt(o.weightedScore),
                  unit: '分',
                  color: Colors.deepPurple[600]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '平均绩点',
                  value: _fmt(o.gpa),
                  unit: '',
                  color: Colors.indigo[600]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '修读学分',
                  value: _fmt(o.semesterCredit),
                  unit: '本学年',
                  color: Colors.teal[600]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '已获学分',
                  value: _fmt(o.earnedCredit),
                  unit: '初修',
                  color: Colors.orange[700]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 校内关系（同侪人数）----

  Widget _buildPeerCard(BuildContext context, DataCenterOverview o) {
    // key → 显示标签
    const entries = [
      ('grade', '同年级'),
      ('class', '同班级'),
      ('major', '同年级同专业'),
      ('dorm', '舍友'),
      ('college', '同学院同生日'),
    ];
    final visible = entries.where((e) {
      final v = o.peerCounts[e.$1];
      return v != null && v >= 0;
    }).toList();
    final hasData = visible.isNotEmpty && o.peerCounts.isNotEmpty;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_outline, size: 18, color: Colors.pink[400]),
                const SizedBox(width: 6),
                const Text(
                  '校内关系',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasData)
              Text(
                '暂无关系数据',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visible.map((e) {
                  final value = o.peerCounts[e.$1] ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.pink[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.pink[100]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$value 人',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: value > 0
                                ? Colors.pink[700]
                                : Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          e.$2,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[700],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 基础指标 ----

  Widget _buildMetricsCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.speed, size: 18, color: Colors.blueGrey[600]),
                const SizedBox(width: 6),
                const Text(
                  '基础指标',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '校园卡余额',
                  value: _fmt(o.cardBalance),
                  unit: '元',
                  color: Colors.green[700]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '今日进出校门',
                  value: _fmt(o.gateToday),
                  unit: '次',
                  color: Colors.blue[700]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '今日登录门户',
                  value: _fmt(o.todayLoginCount),
                  unit: '次',
                  color: Colors.orange[700]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '网费余额',
                  value: _fmt(o.networkBalance),
                  unit: '元',
                  color: Colors.cyan[800]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 校园卡消费 ----

  Widget _buildCardSpendCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card, size: 18, color: Colors.red[600]),
                const SizedBox(width: 6),
                const Text(
                  '校园卡消费',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _scoreCell(
                  context,
                  label: '本年消费',
                  value: _fmt(o.spendYear),
                  unit: '元',
                  color: Colors.red[600]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '当月消费',
                  value: _fmt(o.spendMonth),
                  unit: '元',
                  color: Colors.orange[700]!,
                ),
                _scoreDivider(),
                _scoreCell(
                  context,
                  label: '本周消费',
                  value: _fmt(o.spendWeek),
                  unit: '元',
                  color: Colors.amber[800]!,
                ),
              ],
            ),
            if (o.consumeRecords.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '最近消费',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 6),
              ...o.consumeRecords.take(5).map((r) => _buildConsumeTile(r)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConsumeTile(DzjConsumeRecord r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.shopName, style: const TextStyle(fontSize: 12.5)),
                Text(
                  r.time,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '¥${_fmt(r.amount)}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: Colors.red[600],
            ),
          ),
        ],
      ),
    );
  }

  // ---- 教材 ----

  Widget _buildTextbookCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 18, color: Colors.brown[600]),
            const SizedBox(width: 6),
            const Text(
              '本学期教材',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _scoreCell(
              context,
              label: '教材费用',
              value: _fmt(o.textbookFee),
              unit: '元',
              color: Colors.brown[600]!,
            ),
            _scoreDivider(),
            _scoreCell(
              context,
              label: '教材数量',
              value: _fmt(o.textbookCount),
              unit: '本',
              color: Colors.brown[700]!,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 图书借阅 ----

  Widget _buildBorrowCard(BuildContext context, DataCenterOverview o) {
    const order = ['本周', '本月', '本年'];
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_library, size: 18, color: Colors.teal[700]),
                const SizedBox(width: 6),
                const Text(
                  '图书借阅',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: order.map((label) {
                final count = o.borrowCounts[label] ?? 0;
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$count 本',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: count > 0
                              ? Colors.teal[700]
                              : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 奖助贷勤 ----

  Widget _buildAwardCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  size: 18,
                  color: Colors.amber[800],
                ),
                const SizedBox(width: 6),
                const Text(
                  '奖助贷勤',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (o.awards.isEmpty)
              Text(
                '暂无奖助贷勤记录',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              )
            else
              ...o.awards.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.arrow_right,
                        size: 15,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          a,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[800],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 门户登录趋势 ----

  Widget _buildLoginTrendCard(BuildContext context, DataCenterOverview o) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 18, color: Colors.indigo[400]),
                const SizedBox(width: 6),
                const Text(
                  '门户登录趋势（本周）',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (o.loginTrend.isEmpty)
              Text(
                '暂无登录数据',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: o.loginTrend.map((d) {
                  final max = o.loginTrend.fold<int>(
                    1,
                    (m, x) => x.count > m ? x.count : m,
                  );
                  final height = 60.0 * (d.count / max);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Text(
                            '${d.count}',
                            style: TextStyle(
                              fontSize: 10,
                              color: d.count > 0
                                  ? Colors.indigo[700]
                                  : Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: 60,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: height.clamp(2, 60),
                              decoration: BoxDecoration(
                                color: d.count > 0
                                    ? Colors.indigo[400]
                                    : Colors.grey[200],
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            d.weekday.replaceAll('星期', '周'),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 通用小组件 ----

  Widget _scoreCell(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: TextStyle(fontSize: 9.5, color: Colors.grey[500]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreDivider() {
    return Container(width: 1, height: 32, color: Colors.grey[200]);
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
