import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/second_class_credit.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/second_class_credit_providers.dart';

class SecondClassCreditScreen extends ConsumerWidget {
  const SecondClassCreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(secondClassCreditOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('第二课堂学分'), centerTitle: true),
      body: overviewAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载第二课堂数据...'),
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
                  onPressed: () =>
                      ref.invalidate(secondClassCreditOverviewProvider),
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

  Widget _buildContent(BuildContext context, SecondClassOverview overview) {
    final report = overview.report;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildStudentCard(context, report),
        const SizedBox(height: 12),
        _buildScoreOverviewCard(context, overview),
        const SizedBox(height: 12),
        _buildMilestoneCard(context, overview),
        const SizedBox(height: 12),
        _buildBoardCard(context, overview),
        const SizedBox(height: 12),
        _buildPlatformCard(context, report),
        const SizedBox(height: 12),
        _buildRecordsCard(context, report),
      ],
    );
  }

  // ---- 学生信息 ----

  Widget _buildStudentCard(
    BuildContext context,
    SecondClassCreditReport report,
  ) {
    final s = report.student;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.teal[100],
              child: Text(
                s.name.isEmpty ? '?' : s.name.characters.first,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.studentId} · ${s.className}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    '${s.major} · ${s.college}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 总学分 / 有效学分 ----

  Widget _buildScoreOverviewCard(
    BuildContext context,
    SecondClassOverview overview,
  ) {
    final report = overview.report;
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            _scoreCell(
              context,
              label: '总学分',
              value: _fmt(report.totalCredit),
              color: Colors.deepPurple[600]!,
            ),
            _scoreDivider(),
            _scoreCell(
              context,
              label: '有效学分',
              value: _fmt(report.validCredit),
              color: Colors.teal[600]!,
            ),
            _scoreDivider(),
            _scoreCell(
              context,
              label: '达标进度',
              value:
                  '${_fmt(report.totalCredit)}/${_fmt(overview.totalRequired)}',
              color: overview.totalPassed
                  ? Colors.green[600]!
                  : Colors.orange[700]!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreCell(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scoreDivider() {
    return Container(width: 1, height: 36, color: Colors.grey[200]);
  }

  // ---- 阶段要求 ----

  Widget _buildMilestoneCard(
    BuildContext context,
    SecondClassOverview overview,
  ) {
    if (overview.milestones.isEmpty) return const SizedBox.shrink();
    final report = overview.report;
    final progress = (report.totalCredit / overview.totalRequired).clamp(
      0.0,
      1.0,
    );
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
                Icon(Icons.timeline, size: 18, color: Colors.deepPurple[400]),
                const SizedBox(width: 6),
                Text(
                  '毕业前应获 ${_fmt(overview.totalRequired)} 学分',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: overview.totalPassed
                        ? Colors.green[50]
                        : Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: overview.totalPassed
                          ? Colors.green[200]!
                          : Colors.red[200]!,
                    ),
                  ),
                  child: Text(
                    overview.totalPassed ? '已达标' : '未达标',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: overview.totalPassed
                          ? Colors.green[700]
                          : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                  overview.totalPassed
                      ? Colors.green[400]
                      : Colors.deepPurple[400],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '累计 ${_fmt(report.totalCredit)} / ${_fmt(overview.totalRequired)} 学分'
              '（${(progress * 100).toStringAsFixed(0)}%）',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            // 阶段明细
            ...overview.milestones.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right, size: 15, color: Colors.grey[400]),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[700],
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

  // ---- 板块达标预警 ----

  Widget _buildBoardCard(BuildContext context, SecondClassOverview overview) {
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
                  Icons.verified_outlined,
                  size: 18,
                  color: Colors.orange[700],
                ),
                const SizedBox(width: 6),
                const Text(
                  '各板块达标情况',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '未达标板块以红色标记',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            ...overview.boardRows.map((r) => _buildBoardRow(context, r)),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardRow(BuildContext context, CreditBoardRow row) {
    final met = row.hasRequirement && row.passed;
    final hasReq = row.hasRequirement;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              row.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasReq ? FontWeight.w600 : FontWeight.normal,
                color: !hasReq
                    ? Colors.grey[500]
                    : (met ? Colors.grey[800] : Colors.red[700]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hasReq
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (row.required == null || row.required == 0)
                              ? 0
                              : (row.earned / row.required!).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation(
                            met ? Colors.green[400] : Colors.red[400],
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          '已获 ${_fmt(row.earned)}',
                          '应获 ${_fmt(row.required ?? 0)}',
                          if (row.standard != null && row.standard!.isNotEmpty)
                            row.standard!,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: met ? Colors.green[700] : Colors.red[600],
                        ),
                      ),
                    ],
                  )
                : Text(
                    '已获 ${_fmt(row.earned)} 学分',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
          ),
          if (hasReq) ...[
            const SizedBox(width: 6),
            _chip(met ? '达标' : '未达标', met),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ok ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ok ? Colors.green[300]! : Colors.red[300]!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: ok ? Colors.green[700] : Colors.red[700],
        ),
      ),
    );
  }

  // ---- 十二平台汇总 ----

  Widget _buildPlatformCard(
    BuildContext context,
    SecondClassCreditReport report,
  ) {
    if (report.platformCredits.isEmpty) return const SizedBox.shrink();
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
                  Icons.donut_large_outlined,
                  size: 18,
                  color: Colors.teal[600],
                ),
                const SizedBox(width: 6),
                const Text(
                  '平台学分分布',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.1,
              ),
              children: report.platformCredits.entries.map((e) {
                final nonZero = e.value > 0;
                return Container(
                  decoration: BoxDecoration(
                    color: nonZero ? Colors.teal[50] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: nonZero ? Colors.teal[200]! : Colors.grey[200]!,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: nonZero ? Colors.teal[800] : Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmt(e.value),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: nonZero ? Colors.teal[700] : Colors.grey[400],
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

  // ---- 明细记录 ----

  Widget _buildRecordsCard(
    BuildContext context,
    SecondClassCreditReport report,
  ) {
    if (report.records.isEmpty) return const SizedBox.shrink();
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
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: Colors.blueGrey[600],
                ),
                const SizedBox(width: 6),
                Text(
                  '学分记录（${report.records.length} 条）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              report.volunteerHours > 0
                  ? '含志愿服务累计 ${_fmt(report.volunteerHours)} 小时'
                  : '按获奖年份排序',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            ...report.records.map((r) => _buildRecordTile(context, r)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, SecondClassRecord record) {
    final isVolunteerSummary = record.year.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              isVolunteerSummary ? '累计' : record.year,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isVolunteerSummary
                    ? Colors.orange[700]
                    : Colors.blueGrey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.projectName,
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 2),
                Text(
                  record.platform,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${_fmt(record.credit)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: record.credit > 0 ? Colors.teal[700] : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}
