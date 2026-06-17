import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';

class ImsTabContainer extends StatefulWidget {
  final ImsTab initialTab;

  const ImsTabContainer({super.key, required this.initialTab});

  @override
  State<ImsTabContainer> createState() => _ImsTabContainerState();
}

class _ImsTabContainerState extends State<ImsTabContainer> {
  late PageController _pageController;
  late ImsTab _currentTab;
  int _prevTabIndex = 0;

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
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _prevTabIndex = _currentTab.index;
            _currentTab = ImsTab.values[index];
          });
        },
        children: ImsTab.values.map(_getPage).toList(),
      ),
      bottomNavigationBar: _CustomBottomNavBar(
        currentTab: _currentTab,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  Widget _getPage(ImsTab tab) => switch (tab) {
    .curriculum => CurriculumScreen(showAppBar: false),
    .grade => const Center(child: Text('成绩')),
    .schedule => ScheduleScreen(showAppBar: false),
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
