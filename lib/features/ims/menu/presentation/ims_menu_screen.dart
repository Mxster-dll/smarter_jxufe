import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_tab_container.dart';
import 'package:smarter_jxufe/features/platform/presentation/platform_selection_screen.dart';

class ImsMenuScreen extends ConsumerWidget {
  const ImsMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const PlatformSelectionScreen(),
              ),
            );
          },
        ),
        title: const Text('教学信息服务'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ImsTab.values.map((tab) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _buildMenuButton(
                  context,
                  icon: tab.icon,
                  label: tab.title,
                  color: tab.color, // 使用枚举定义的颜色
                  tab: tab,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required ImsTab tab,
  }) {
    return SizedBox(
      width: 200,
      height: 80,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImsTabContainer(initialTab: tab),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
