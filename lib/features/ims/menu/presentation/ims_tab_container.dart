// lib/features/ims/shared/presentation/ims_tab_container.dart

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';

class ImsTabContainer extends StatefulWidget {
  final ImsTab initialTab;

  const ImsTabContainer({super.key, required this.initialTab});

  @override
  State<ImsTabContainer> createState() => _ImsTabContainerState();
}

class _ImsTabContainerState extends State<ImsTabContainer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = ImsTab.values.indexOf(widget.initialTab);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(ImsTab tab) {
    final newIndex = ImsTab.values.indexOf(tab);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      _pageController.animateToPage(
        newIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: ImsTab.values.map(_getPage).toList(),
      ),
      bottomNavigationBar: _CustomBottomNavBar(
        currentTab: ImsTab.values[_currentIndex],
        onTabSelected: _onTabSelected,
      ),
    );
  }

  Widget _getPage(ImsTab tab) => switch (tab) {
    .curriculum => const CurriculumScreen(),
    .grade => const Text('成绩'),
    .schedule => const Text('课表'),
    .studentInfo => const Text('学生信息'),
  };
}

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
