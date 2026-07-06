import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/volunteer_hours_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';

/// SSP Dio 提供者 —— 用于访问综合管理服务平台
final sspDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: 'http://ssp.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
        'Referer': 'http://ssp.jxufe.edu.cn/admin/common/main.html',
        'Cookie': 'JSESSIONID=CBAE06656EA1CDCDE1316DD950A83B7A',
      },
    ),
  );
});

/// 志愿服务时长数据源提供者
final volunteerHoursDataSourceProvider =
    Provider<VolunteerHoursRemoteDataSource>((ref) {
      final dio = ref.watch(sspDioProvider);
      return VolunteerHoursRemoteDataSource(dio);
    });

/// 志愿服务活动列表状态提供者
final volunteerActivitiesProvider = FutureProvider<List<VolunteerActivity>>((
  ref,
) async {
  final dataSource = ref.watch(volunteerHoursDataSourceProvider);
  return dataSource.fetchVolunteerActivities();
});

class VolunteerHoursScreen extends ConsumerWidget {
  const VolunteerHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(volunteerActivitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('学生活动时长统计'), centerTitle: true),
      body: activitiesAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在加载志愿服务数据...'),
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
                  onPressed: () => ref.invalidate(volunteerActivitiesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (activities) {
          if (activities.isEmpty) {
            return const Center(child: Text('暂无志愿活动数据'));
          }
          return _buildActivityList(context, activities);
        },
      ),
    );
  }

  Widget _buildActivityList(
    BuildContext context,
    List<VolunteerActivity> activities,
  ) {
    final totalHours = activities.fold<double>(
      0,
      (sum, a) => sum + (double.tryParse(a.recognizedHours) ?? 0),
    );

    return Column(
      children: [
        // 进度条
        _buildProgressBar(context, totalHours),
        const SizedBox(height: 8),
        // 记录数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '共 ${activities.length} 条记录',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
        // 列表（自适应列数，高度由内容撑开）
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const minCardWidth = 250.0;
              const gap = 4.0;
              final totalWidth = constraints.maxWidth - 12; // padding
              final columnCount = (totalWidth / minCardWidth).floor().clamp(
                1,
                10,
              );
              final cardWidth =
                  (totalWidth - (columnCount - 1) * gap) / columnCount;

              final rows = <List<VolunteerActivity>>[];
              for (var i = 0; i < activities.length; i += columnCount) {
                final end = (i + columnCount).clamp(0, activities.length);
                rows.add(activities.sublist(i, end));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(6),
                itemCount: rows.length,
                itemBuilder: (context, rowIndex) {
                  final row = rows[rowIndex];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var j = 0; j < row.length; j++) ...[
                          SizedBox(
                            width: cardWidth,
                            child: _buildActivityCard(context, row[j]),
                          ),
                          if (j < row.length - 1) const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context, double totalHours) {
    const milestones = [0, 20, 30, 50, 100];
    const scores = ['0分', '1分', '1.5分', '2分', '4分'];
    const maxHours = 100.0;
    final clamped = totalHours.clamp(0, maxHours);
    final progress = clamped / maxHours;
    final currentScore = _getScore(totalHours);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          const SizedBox(height: 14),
          // 进度条主体
          SizedBox(
            height: 80,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 背景轨道
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 已填充进度
                    Positioned(
                      top: 20,
                      left: 0,
                      width: barWidth * progress,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange[400]!,
                              Colors.deepOrange[600]!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 5 个节点
                    for (var i = 0; i < milestones.length; i++)
                      Positioned(
                        left: (milestones[i] / maxHours) * barWidth - 6,
                        top: 1,
                        child: Column(
                          children: [
                            Text(
                              '${milestones[i]}h',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: clamped >= milestones[i]
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: clamped >= milestones[i]
                                    ? Colors.deepOrange[700]
                                    : Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: clamped >= milestones[i]
                                    ? Colors.deepOrange[600]
                                    : Colors.grey[350],
                                border: Border.all(
                                  color: clamped >= milestones[i]
                                      ? Colors.deepOrange[700]!
                                      : Colors.grey[400]!,
                                  width: 2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              scores[i],
                              style: TextStyle(
                                fontSize: 9,
                                color: clamped >= milestones[i]
                                    ? Colors.deepOrange[400]
                                    : Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 当前位置文本标注
                    if (totalHours > 0)
                      Positioned(
                        left: (barWidth * progress) - 16,
                        top: -1,
                        child: SizedBox(
                          width: 32,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${totalHours.toStringAsFixed(0)}h',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[700],
                                ),
                              ),
                              const SizedBox(height: 17),
                              Text(
                                currentScore,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getScore(double hours) {
    if (hours >= 100) return '4分';
    if (hours >= 50) return '2分';
    if (hours >= 30) return '1.5分';
    if (hours >= 20) return '1分';
    return '0分';
  }

  Widget _buildActivityCard(BuildContext context, VolunteerActivity activity) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题行：序号 + 活动名称
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '#${activity.index}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity.activityName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 信息区：一列四排
            _compactInfo(Icons.business_outlined, activity.department),
            _compactInfo(Icons.category_outlined, activity.activityCategory),
            _compactInfo(
              Icons.assignment_ind_outlined,
              '负责人：${activity.responsiblePerson}',
            ),
            _compactInfo(Icons.person_outline, '发起人：${activity.initiator}'),
            const SizedBox(height: 8),
            // 底栏：时长左 + 状态右
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '${activity.recognizedHours} 小时',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                ),
                const Spacer(),
                _buildStatusChip(activity.applicationStatus),
                const SizedBox(width: 3),
                _buildStatusChip(activity.recognitionStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactInfo(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 12),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Icon(icon, size: 11, color: Colors.grey[450]),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final isSuccess =
        status.contains('通过') ||
        status.contains('已认定') ||
        status.contains('成功');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isSuccess ? Colors.green[300]! : Colors.grey[300]!,
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: isSuccess ? Colors.green[700] : Colors.grey[600],
        ),
      ),
    );
  }
}
