import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';

/// 单项教务功能容器：进入即全屏展示 [initialTab] 对应的功能页，
/// 仅保留返回与（成绩页）刷新能力。不再提供五功能底部切换栏、
/// 顶部标题切换动画或宽屏横向翻页 —— 五个功能各自独立显示，
/// 需要切换时退回主页/菜单重新进入。
class ImsTabContainer extends ConsumerStatefulWidget {
  final ImsTab initialTab;

  const ImsTabContainer({super.key, required this.initialTab});

  @override
  ConsumerState<ImsTabContainer> createState() => _ImsTabContainerState();
}

class _ImsTabContainerState extends ConsumerState<ImsTabContainer> {
  late ImsTab _currentTab;
  bool _showNoUpdateText = false;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  void _triggerNoUpdateHint() {
    if (!mounted) return;
    setState(() => _showNoUpdateText = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showNoUpdateText = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(noUpdateSignalProvider, (prev, next) {
      if (prev != next) _triggerNoUpdateHint();
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        actions: [
          if (_currentTab == ImsTab.grade) ...[
            if (_showNoUpdateText)
              GestureDetector(
                onTap: () => setState(() => _showNoUpdateText = false),
                child: AnimatedOpacity(
                  opacity: _showNoUpdateText ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '无更新',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final params = ref.read(gradesViewModelProvider).params;
                final isLoading = ref.watch(gradesProvider(params)).isLoading;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    icon: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: '',
                    onPressed: isLoading
                        ? null
                        : () {
                            ref.read(refreshRequestedProvider.notifier).state =
                                true;
                            ref.invalidate(gradesProvider(params));
                          },
                  ),
                );
              },
            ),
          ],
        ],
        title: Text(_currentTab.title),
      ),
      body: _getPage(_currentTab),
    );
  }

  Widget _getPage(ImsTab tab) => switch (tab) {
    .curriculum => CurriculumScreen(showAppBar: false),
    .grade => GradesScreen(showAppBar: false),
    .schedule => ScheduleScreen(showAppBar: false),
    .graduationRequirements => GraduationRequirementsScreen(showAppBar: false),
    .studentInfo => StudentInfoScreen(showAppBar: false),
  };
}
