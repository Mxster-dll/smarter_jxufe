import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/platform/file_share.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';

class VolunteerHoursScreen extends ConsumerStatefulWidget {
  const VolunteerHoursScreen({super.key});

  @override
  ConsumerState<VolunteerHoursScreen> createState() =>
      _VolunteerHoursScreenState();
}

class _VolunteerHoursScreenState extends ConsumerState<VolunteerHoursScreen> {
  /// 正在下载/分享「时长认定登记表」，期间禁用按钮并显示进度。
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final activitiesAsync = ref.watch(volunteerActivitiesProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('学生活动时长统计'),
        centerTitle: true,
        actions: [_buildExportAction()],
      ),
      body: PaneBody(
        actions: [_buildExportAction()],
        padding: EdgeInsets.zero,
        child: activitiesAsync.when(
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
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.critical(context),
                  ),
                  const SizedBox(height: 16),
                  Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted(context)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () =>
                        ref.invalidate(volunteerActivitiesProvider),
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
      ),
    );
  }

  /// AppBar 上的导出入口：下载中显示进度圈，其余时候是分享图标。
  Widget _buildExportAction() {
    if (_exporting) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: '导出时长认定登记表',
      icon: const Icon(Icons.ios_share),
      onPressed: _exportRecognitionForm,
    );
  }

  /// 下载学校平台的「志愿服务时长认定登记表」（Word 原件）并调起系统分享。
  ///
  /// 口径：**原样搬运学校下发的文件**，App 不改写内容；
  /// Android 交给系统分享面板（微信 / QQ / 邮件），桌面端回退为写入下载目录。
  Future<void> _exportRecognitionForm() async {
    if (_exporting) return;

    final account = ref.read(currentAccountProvider);
    if (account.isEmpty) {
      debugPrint('[volunteer_export] 未登录，跳过导出');
      _snack('请先登录后再导出志愿时长证明');
      return;
    }

    final loaded = ref.read(volunteerActivitiesProvider).valueOrNull;
    if (loaded != null && loaded.isEmpty) {
      debugPrint('[volunteer_export] 记录为空，跳过导出');
      _snack('暂无可导出的志愿时长记录');
      return;
    }

    setState(() => _exporting = true);
    try {
      final repository = await ref.read(
        volunteerHoursRepositoryProvider.future,
      );
      final file = await repository.exportRecognitionForm(account);
      debugPrint(
        '[volunteer_export] 已下载 ${file.fileName}（${file.sizeInBytes} 字节）',
      );
      final result = await FileShare.shareBytes(
        bytes: file.bytes,
        fileName: file.fileName,
        mimeType: file.mimeType,
        subject: file.fileName,
        text: '江西财经大学青年志愿者志愿服务时长认定登记表',
      );
      debugPrint('[volunteer_export] 分享/保存结果: $result');
      if (!mounted) return;

      if (result.shared) {
        _snack('已调起系统分享，选择微信 / QQ 等应用发送即可');
      } else if (result.savedPath != null) {
        final path = result.savedPath!;
        _snack(
          '已导出到 $path',
          action: SnackBarAction(
            label: '打开',
            onPressed: () => FileShare.openFile(path),
          ),
        );
      } else {
        _snack('导出失败：${result.error ?? '未知错误'}');
      }
    } catch (error) {
      debugPrint('[volunteer_export] 导出失败: $error');
      if (mounted) _snack('导出失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _snack(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 5),
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
        // 记录数 + 导出入口（导出的是学校平台那份 Word 原件）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '共 ${activities.length} 条记录',
                style: TextStyle(
                  color: AppColors.textMuted(context),
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _exporting ? null : _exportRecognitionForm,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('导出证明'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
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

                // 计算当前位置
                final currentX = barWidth * progress;
                const halfWidth = 16.0;

                // 反重叠：检测与每个固定节点是否重叠，各自偏移
                double currentShift = 0;
                final nodeShifts = List.filled(milestones.length, 0.0);

                for (var i = 0; i < milestones.length; i++) {
                  final nodeX = (milestones[i] / maxHours) * barWidth;
                  final gap = (currentX - nodeX).abs();
                  final overlap = halfWidth * 2 - gap;
                  if (overlap > 0) {
                    final shift = overlap / 2;
                    if (currentX >= nodeX) {
                      currentShift += shift;
                      nodeShifts[i] = -shift;
                    } else {
                      currentShift -= shift;
                      nodeShifts[i] = shift;
                    }
                  }
                }

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
                          color: AppColors.fillStrong(context),
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
                              AppColors.tone(context, Colors.orange[400]!),
                              AppColors.tone(context, Colors.deepOrange[600]!),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 5 个节点
                    for (var i = 0; i < milestones.length; i++)
                      Positioned(
                        left:
                            (milestones[i] / maxHours) * barWidth -
                            6 +
                            nodeShifts[i],
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
                                    ? AppColors.tone(
                                        context,
                                        Colors.deepOrange[700]!,
                                      )
                                    : AppColors.textMuted(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: clamped >= milestones[i]
                                    ? AppColors.tone(
                                        context,
                                        Colors.deepOrange[600]!,
                                      )
                                    // 原写法 `Colors.grey[350]` 是不存在的档位，
                                    // `MaterialColor[]` 返回 null → 该圆点本就无填充。
                                    // 保留「无填充」语义，避免改变浅色渲染结果。
                                    : null,
                                border: Border.all(
                                  color: clamped >= milestones[i]
                                      ? AppColors.tone(
                                          context,
                                          Colors.deepOrange[700]!,
                                        )
                                      : AppColors.stroke(context),
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
                                    ? AppColors.tone(
                                        context,
                                        Colors.deepOrange[400]!,
                                      )
                                    : AppColors.tone(
                                        context,
                                        Colors.grey[400]!,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 当前位置文本标注
                    if (totalHours > 0)
                      Positioned(
                        left: (barWidth * progress) - 16 + currentShift,
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
                                  color: AppColors.critical(context),
                                ),
                              ),
                              const SizedBox(height: 17),
                              Text(
                                currentScore,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.tone(
                                    context,
                                    Colors.red[400]!,
                                  ),
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
      shape: appCardShape(context),
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
            if (activity.activityTimeText.isNotEmpty)
              _compactInfo(
                Icons.schedule_outlined,
                '活动时间：${activity.activityTimeText}',
              ),
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
                    color: AppColors.cautionFill(context),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppColors.tone(context, Colors.orange[200]!),
                    ),
                  ),
                  child: Text(
                    '${activity.recognizedHours} 小时',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.caution(context),
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
            // 原写法 `Colors.grey[450]` 是不存在的档位 → 得到 null → 该图标
            // 一直走 IconTheme 默认色。删掉 `color` 保持渲染逐像素一致。
            child: Icon(icon, size: 11),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textMuted(context),
              ),
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
        color: isSuccess
            ? AppColors.successFill(context)
            : AppColors.fill(context),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isSuccess
              ? AppColors.tone(context, Colors.green[300]!)
              : AppColors.stroke(context),
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: isSuccess
              ? AppColors.success(context)
              : AppColors.textMuted(context),
        ),
      ),
    );
  }
}
