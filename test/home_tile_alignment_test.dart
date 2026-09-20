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

  test('目录条目齐全（30 条）', () {
    // 25 = 并行工作流新增两项后的 23 + 2026-09-17 新增「推免成绩 / 竞赛奖励」两项；
    // 26 = 2026-09-19 新增「AI 助手」（内置对话式问答，排在第一格）；
    // 27 = 2026-09-19 新增「学习通」（超星课程 / 作业 / 通知只读接入）；
    // 28 = 2026-09-19 新增「AA 算账」（纯本地记账：成员 + 开销 → 两两转账）；
    // 29 = 2026-09-19 新增「找空闲教室」（公共查询 SB11 / SB12 两个子功能独立成磁贴）；
    // 30 = 2026-09-19 新增「网站导航」（137 条全校站点目录 + 星标收藏）。
    expect(entries.length, 30, reason: '增删服务入口请同步本测试与 AGENTS.md §3');
  });

  test('「找空闲教室」在「教务系统」组里，且页面是 ClassroomFreeScreen', () {
    final ims = homeServiceEntriesInGroup(entries, HomeServiceGroup.ims)
        .map((e) => e.title)
        .toList();
    expect(ims, contains('找空闲教室'));
    final free = entries.firstWhere((e) => e.title == '找空闲教室');
    expect(
      free.builder().runtimeType.toString(),
      contains('ClassroomFreeScreen'),
    );
    // 独立的是**找空闲教室**（用户 2026-09-19 二轮纠正）；「找无课时间」不进磁贴，
    // 仍走公共查询页那张入口卡。
    expect(titles, isNot(contains('找无课时间')));
    expect(
      entries.firstWhere((e) => e.title == '公共查询').subtitle,
      contains('多班对照'),
    );
  });

  test('「学习通」在「学习与测评」组里，且页面是 ChaoxingScreen', () {
    final study = homeServiceEntriesInGroup(entries, HomeServiceGroup.study)
        .map((e) => e.title)
        .toList();
    expect(study, contains('学习通'));
    final chaoxing = entries.firstWhere((e) => e.title == '学习通');
    expect(chaoxing.builder().runtimeType.toString(), contains('ChaoxingScreen'));
    expect(chaoxing.accent, isNotNull);
  });

  test('「网站导航」在「数据与信息」组里，且页面是 SiteNavScreen', () {
    final info = homeServiceEntriesInGroup(entries, HomeServiceGroup.info)
        .map((e) => e.title)
        .toList();
    expect(info, contains('网站导航'));
    final nav = entries.firstWhere((e) => e.title == '网站导航');
    expect(nav.builder().runtimeType.toString(), contains('SiteNavScreen'));
    expect(nav.subtitle, contains('学院'));
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
