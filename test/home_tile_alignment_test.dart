import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 首页服务目录守卫。
///
/// **历史**：条目原先写在 `home_screen.dart` 的私有 `_items(context)` 里，强调色存在
/// 顶层 `const _tileColors`，两者按**索引**对齐 —— 本文件当时守的就是「条目数 == 色数」。
/// 2026-09-15 起（用户裁定第 1 条：主页要能切「左侧导航栏视图」）宫格与侧栏共用
/// `home_service_catalog.dart`，**强调色随条目定义**（`HomeServiceEntry.accent`），
/// 索引对齐这条约定作废（侧栏按分组重排，索引本来就会变）。
/// 现在守的是：目录完整性、标题唯一、分组覆盖、以及「别再退回索引取色」。
void main() {
  final entries = homeServiceEntries(push: (_) {});
  final titles = entries.map((e) => e.title).toList();

  test('目录条目齐全（26 条）', () {
    // 25 = 并行工作流新增两项后的 23 + 2026-09-17 新增「推免成绩 / 竞赛奖励」两项；
    // 26 = 2026-09-19 新增「AI 助手」（内置对话式问答，排在第一格）。
    expect(entries.length, 26, reason: '增删服务入口请同步本测试与 AGENTS.md §3');
  });

  test('AI 助手排在第一位，且它的页面是 AiChatScreen', () {
    expect(entries.first.title, 'AI 助手');
    expect(entries.first.builder().runtimeType.toString(), contains('AiChatScreen'));
  });

  test('两个新功能入口都在「学习与测评」组里', () {
    final study = homeServiceEntriesInGroup(entries, HomeServiceGroup.study)
        .map((e) => e.title)
        .toList();
    expect(study, contains('推免成绩'));
    expect(study, contains('竞赛奖励'));
  });

  test('标题唯一（同一入口不会出现两次）', () {
    expect(titles.toSet().length, titles.length, reason: '$titles');
  });

  test('每条都有图标与分组，且分组并集 = 全目录', () {
    for (final e in entries) {
      expect(e.subtitle, isNotNull);
      expect(e.accent, isNotNull);
    }
    final grouped = [
      for (final group in HomeServiceGroup.values)
        ...homeServiceEntriesInGroup(entries, group),
    ];
    expect(grouped.length, entries.length, reason: '有条目没归入任何分组 → 侧栏视图会漏掉它');
    expect(grouped.map((e) => e.title).toSet(), titles.toSet());
  });

  test('「上课实况窗」已从主页目录移除（2026-09-15 迁到设置页）', () {
    expect(titles, isNot(contains('上课实况窗')));
  });

  test('「我的」不在目录里（入口 = 顶栏右上角头像，2026-09-11 裁定）', () {
    expect(titles, isNot(contains('我的')));
  });

  test('home_screen.dart 不再按索引取色（强调色随条目走）', () {
    final file = File('lib/features/home/presentation/home_screen.dart');
    expect(file.existsSync(), isTrue, reason: '找不到 ${file.path}');
    final source = file.readAsStringSync();
    expect(
      source.contains('_tileColors'),
      isFalse,
      reason: '索引对齐的色表已废除：强调色定义在 HomeServiceEntry.accent',
    );
    expect(source.contains('homeServiceEntries('), isTrue);
    expect(source.contains('HomeServiceGrid('), isTrue);
    expect(source.contains('HomeSidebar('), isTrue);
  });
}
