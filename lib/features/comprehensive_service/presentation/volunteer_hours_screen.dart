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
    return Column(
      children: [
        // 提示信息
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber[200]!),
          ),
          child: const Text(
            '累计时长20小时及以上1分，30小时及以上1.5分，50小时及以上2分，100小时及以上4分',
            style: TextStyle(fontSize: 13, color: Color(0xFF795548)),
          ),
        ),
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
        // 列表
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: activities.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final activity = activities[index];
              return _buildActivityCard(context, activity);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(BuildContext context, VolunteerActivity activity) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${activity.index}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    activity.activityName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 信息行
            _buildInfoRow(context, '发起人', activity.initiator),
            _buildInfoRow(context, '负责人', activity.responsiblePerson),
            _buildInfoRow(context, '所属部门', activity.department),
            _buildInfoRow(context, '活动类别', activity.activityCategory),

            const SizedBox(height: 8),

            // 时长 + 状态
            Row(
              children: [
                // 认定时长
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer, size: 14, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        '${activity.recognizedHours} 小时',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // 申请状态
                _buildStatusChip(activity.applicationStatus),
                const SizedBox(width: 8),
                // 认定状态
                _buildStatusChip(activity.recognitionStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSuccess ? Colors.green[300]! : Colors.grey[300]!,
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isSuccess ? Colors.green[700] : Colors.grey[600],
        ),
      ),
    );
  }
}
