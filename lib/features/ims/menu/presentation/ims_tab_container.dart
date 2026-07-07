import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_screen.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_viewmodel.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart';

class ImsTabContainer extends ConsumerStatefulWidget {
  final ImsTab initialTab;

  const ImsTabContainer({super.key, required this.initialTab});

  @override
  ConsumerState<ImsTabContainer> createState() => _ImsTabContainerState();
}

class _ImsTabContainerState extends ConsumerState<ImsTabContainer> {
  late PageController _pageController;
  late ImsTab _currentTab;
  int _prevTabIndex = 0;

  bool _showNoUpdateText = false;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    final initialIndex = ImsTab.values.indexOf(_currentTab);
    _pageController = PageController(initialPage: initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _triggerNoUpdateHint() {
    if (!mounted) return;
    setState(() => _showNoUpdateText = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showNoUpdateText = false);
    });
  }

  void _onTabSelected(ImsTab tab) {
    if (tab == _currentTab) return;
    _prevTabIndex = _currentTab.index;
    final targetIndex = ImsTab.values.indexOf(tab);
    _pageController.animateToPage(
      targetIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            final isCurrent =
                (child.key as ValueKey<ImsTab>).value == _currentTab;
            final goingRight = _currentTab.index > _prevTabIndex;
            final sign = (isCurrent == goingRight) ? 1.0 : -1.0;
            final dist = (_currentTab.index - _prevTabIndex).abs().clamp(1, 10);
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, sign * dist * 0.6),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Text(_currentTab.title, key: ValueKey(_currentTab)),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return PageView(
            controller: _pageController,
            physics: isNarrow
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              if (!mounted) return;
              setState(() {
                _prevTabIndex = _currentTab.index;
                _currentTab = ImsTab.values[index];
              });
            },
            children: ImsTab.values.map(_getPage).toList(),
          );
        },
      ),
      bottomNavigationBar: _CustomBottomNavBar(
        currentTab: _currentTab,
        onTabSelected: _onTabSelected,
      ),
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

// 底部栏组件（与之前相同，只是参数类型已是 ImsTab）
class _CustomBottomNavBar extends StatelessWidget {
  final ImsTab currentTab;
  final ValueChanged<ImsTab> onTabSelected;

  const _CustomBottomNavBar({
    required this.currentTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ImsTab.values.map((tab) {
            final isSelected = currentTab == tab;
            return Expanded(
              child: InkWell(
                onTap: () => onTabSelected(tab),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        color: isSelected ? tab.color : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tab.title,
                        style: TextStyle(
                          color: isSelected ? tab.color : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
