import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';

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

  /// 原导航栏 actions（只有成绩页有：「无更新」浮标 + 刷新）。
  ///
  /// 整页模式进 `AppBar.actions`；侧栏内嵌模式（面板首路由）由 `PaneBody`
  /// 下沉到内容首行 —— 用户 2026-09-16 裁定：面板顶部不留 chrome（§19）。
  List<Widget> _headerActions(BuildContext context) => [
    if (_currentTab == ImsTab.grade) ...[
      if (_showNoUpdateText)
        GestureDetector(
          onTap: () => setState(() => _showNoUpdateText = false),
          child: AnimatedOpacity(
            opacity: _showNoUpdateText ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      ref.read(refreshRequestedProvider.notifier).state = true;
                      ref.invalidate(gradesProvider(params));
                    },
            ),
          );
        },
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(noUpdateSignalProvider, (prev, next) {
      if (prev != next) _triggerNoUpdateHint();
    });

    return Scaffold(
      // 课表页自带 AppBar（标题栏里是学期/周次选择器，见 schedule_screen.dart），
      // 容器不再叠一层「课表」标题。
      appBar: _currentTab == ImsTab.schedule
          ? null
          : paneAppBar(
              context,
              // 返回按钮只在「真的有上一页」时出现：主页侧栏视图把本页内嵌在
              // 右侧面板时（用户 2026-09-15 裁定第 2 条），本页是该面板路由栈的
              // 首页 → canPop false → 不画返回按钮；从主页宫格 push 进来时照旧显示。
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              centerTitle: true,
              actions: _headerActions(context),
              title: Text(_currentTab.title),
              // 培养方案 / 成绩 / 毕业学分 / 我的 都靠教务会话（课表页自带 AppBar，
              // 它自己声明会话 + 实况窗两节）。
              settingsSections: const [SettingsSection.imsSession],
            ),
      // 内嵌模式（面板首路由）：原导航栏按钮下沉到内容顶部；整页模式不渲染。
      body: PaneBody(
        actions: _headerActions(context),
        padding: EdgeInsets.zero,
        child: _getPage(_currentTab),
      ),
    );
  }

  Widget _getPage(ImsTab tab) => switch (tab) {
    .curriculum => CurriculumScreen(showAppBar: false),
    .grade => GradesScreen(showAppBar: false),
    .schedule => const ScheduleScreen(),
    .graduationRequirements => GraduationRequirementsScreen(showAppBar: false),
    .studentInfo => StudentInfoScreen(showAppBar: false),
  };
}
