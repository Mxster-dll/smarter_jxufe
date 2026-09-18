/// 学科竞赛目录的**搜索与识别**守卫（用户 2026-09-18 两条要求）。
///
/// 原话：「学科竞赛目录里有很多像『中国高校计算机大赛一①大数据挑战赛、
/// ②团体程序设计天梯 赛、③移动应用创新赛…』这样的比赛，虽然显示为
/// 『中国高校计算机大赛』是正确的，但是搜索应该可以被『大数据挑战赛』
/// 『团体程序设计天梯 赛』这样的比赛识别到，同时修复一个问题，那就是
/// 学科竞赛目录中很多比赛名因为在原文件换行，导致了识别出来有空格，
/// 你要防止这个导致匹配不上」。
///
/// 口径：
/// - 显示/回填一律 `zcCleanName`（只删**中文之间**的换行空白，中英之间的
///   排版空格保留）；
/// - 搜索/识别一律 `zcNameKey`（去全部空白、标点、零宽，小写，全角数字转半角）；
/// - 复合赛事名的子项、以及 `zcContestAliases` 里的别名，都进候选的
///   `keywords` 与目录索引 → 搜索与自动识别都能命中主竞赛。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

void main() {
  group('名称归一化与清洗', () {
    test('zcNameKey 去空白/标点/零宽，全角数字转半角', () {
      expect(zcNameKey('华为 ICT 大赛'), zcNameKey('华为ICT大赛'));
      expect(zcNameKey('《数学建模》竞赛'), '数学建模竞赛');
      expect(zcNameKey('挑战杯  大学生'), '挑战杯大学生');
      expect(zcNameKey('第１届大赛'), '第1届大赛');
      expect(zcNameKey('中国高校计算机大赛①②'), '中国高校计算机大赛');
      expect(zcNameKey('人工智能创意\u200b赛'), '人工智能创意赛');
    });

    test('zcCleanName 只删「中文之间」的空白（换行残留）', () {
      expect(zcCleanName('团体程序设计天梯 赛'), '团体程序设计天梯赛');
      expect(zcCleanName('人工智能创意 赛'), '人工智能创意赛');
      expect(zcCleanName('华为 ICT 大赛'), '华为 ICT 大赛', reason: '中英之间的空格是排版需要');
      expect(zcCleanName('  多余   空白  '), '多余空白', reason: '中文之间的空白折叠后删除');
      expect(zcCleanName('创意\u200b赛'), '创意赛');
    });
  });

  group('复合赛事拆解 zcSplitCompositeContest', () {
    test('①子项形态：拆出主名与全部子项（并清洗换行空白）', () {
      const raw =
          '中国高校计算机大赛一①大数据挑战赛、②团体程序设计天梯 赛、'
          '③移动应用创新赛、④网络技术挑战赛、⑤人工智能创意 赛';
      final r = zcSplitCompositeContest(raw);
      expect(r.main, '中国高校计算机大赛');
      expect(r.subs, [
        '大数据挑战赛',
        '团体程序设计天梯赛',
        '移动应用创新赛',
        '网络技术挑战赛',
        '人工智能创意赛',
      ]);
    });

    test('普通名不拆', () {
      final r = zcSplitCompositeContest('中国高校计算机大赛');
      expect(r.main, '中国高校计算机大赛');
      expect(r.subs, isEmpty);
    });

    test('括号枚举形态', () {
      final r = zcSplitCompositeContest('全国大学生数学建模竞赛（本科组、专科组）');
      expect(r.main, '全国大学生数学建模竞赛');
      expect(r.subs, ['本科组', '专科组']);
    });

    test('子项尾部「等」剥除', () {
      final r = zcSplitCompositeContest('某大赛①甲项目、②乙项目等');
      expect(r.main, '某大赛');
      expect(r.subs, ['甲项目', '乙项目']);
    });
  });

  group('候选与搜索', () {
    final spec = zcTypeSpecOf[ZcTypeId.contest]!;
    final items = zcActivityItems(spec);

    ZcActivityItem titled(String t) =>
        items.firstWhere((it) => it.title == t, orElse: () => throw StateError('候选里没有「$t」'));

    test('竞赛候选名已清洗：中文之间不再有换行空白', () {
      // ⚠ 只看 Ⅰ~Ⅲ 类目录名：Ⅳ 类的候选标题是 `江西省大学生科技创新竞赛 <子项>`，
      // 那个空格是刻意加的层级分隔（子项本身可能是中文开头），不是换行残留。
      final sep = RegExp(r'[\u4e00-\u9fff] [\u4e00-\u9fff]');
      final dirty = [
        for (final entry in zcContests.entries)
          for (final raw in entry.value)
            if (sep.hasMatch(zcCleanName(raw))) zcCleanName(raw),
      ];
      expect(dirty, isEmpty, reason: '原稿换行的空白若留着，用户按正常写法搜索就匹配不上');
      expect(items.any((it) => it.title == '华为 ICT 大赛'), isTrue, reason: '中英之间的空格保留');
    });

    test('中国高校计算机大赛：显示主名 + 类别正确，子项进 keywords', () {
      final it = titled('中国高校计算机大赛');
      expect(it.namePrefill, '中国高校计算机大赛', reason: '回填的仍应是主名');
      expect(it.cat, 'c2');
      for (final sub in const [
        '大数据挑战赛',
        '团体程序设计天梯赛',
        '移动应用创新赛',
        '网络技术挑战赛',
        '人工智能创意赛',
      ]) {
        expect(it.keywords, contains(sub));
        expect(zcActivityMatches(it, sub), isTrue, reason: '搜「$sub」要能命中主竞赛');
      }
    });

    test('子项名的部分输入也能命中（前缀/包含）', () {
      final it = titled('中国高校计算机大赛');
      expect(zcActivityMatches(it, '大数据'), isTrue);
      expect(zcActivityMatches(it, '天梯'), isTrue);
      expect(zcActivityMatches(it, '团体程序设计天梯 赛'), isTrue, reason: '带换行空格的原文也要能搜到');
    });

    test('搜索忽略空白与标点（华为ICT大赛 → 华为 ICT 大赛）', () {
      expect(zcActivityMatches(titled('华为 ICT 大赛'), '华为ICT大赛'), isTrue);
      expect(zcActivityMatches(titled('华为 ICT 大赛'), '华为 ict 大赛'), isTrue);
      expect(
        zcActivityMatches(titled('ACM-ICPC 国际大学生程序设计竞赛'), 'acm-icpc国际大学生程序设计竞赛'),
        isTrue,
      );
    });

    test('空查询返回全部；无关查询不命中', () {
      expect(zcActivityMatches(titled('中国高校计算机大赛'), '   '), isTrue);
      expect(zcActivityMatches(titled('中国高校计算机大赛'), '蓝桥杯'), isFalse);
    });
  });

  group('自动识别 zcMatchContest', () {
    test('子项名识别出主竞赛与类别（含换行空白写法）', () {
      for (final q in const [
        '大数据挑战赛',
        '大数据挑战',
        '团体程序设计天梯赛',
        '团体程序设计天梯 赛',
        '人工智能创意赛',
      ]) {
        final hit = zcMatchContest(q);
        expect(hit?.name, '中国高校计算机大赛', reason: '「$q」应识别为主竞赛');
        expect(hit?.cat, 'c2');
      }
    });

    test('复合全名（原文形态）也识别主竞赛', () {
      final hit = zcMatchContest(
        '中国高校计算机大赛一①大数据挑战赛、②团体程序设计天梯 赛、③移动应用创新赛',
      );
      expect(hit?.name, '中国高校计算机大赛');
      expect(hit?.cat, 'c2');
    });

    test('带空白的目录名可被无空白输入识别', () {
      expect(zcMatchContest('华为ICT大赛')?.name, '华为 ICT 大赛');
      expect(zcMatchContest('中国机器人大赛暨RoboCup机器人世界杯中国赛')?.name, contains('RoboCup'));
    });
  });

  group('源码守卫', () {
    test('搜索口径统一在 zcActivityMatches，材料库不再自建别名匹配', () {
      final src = File(
        'lib/features/materials/presentation/materials_screen.dart',
      ).readAsStringSync();
      expect(src, contains('zcActivityMatches'));
      expect(src.contains('_aliasFor'), isFalse, reason: '别名已并入候选 keywords，别再各写一套');
    });

    test('归一化函数已公开（zcNameKey），不得再退回私有 _zcNorm', () {
      final cat = File('lib/features/zongce/domain/zc_catalog.dart').readAsStringSync();
      expect(cat, contains('String zcNameKey('));
      expect(cat, contains('String zcCleanName('));
      expect(cat, contains('zcSplitCompositeContest('));
      expect(cat.contains('_zcNorm('), isFalse);
    });

    test('候选构造挂上关键词（竞赛目录 + Ⅳ 类子项）', () {
      final act = File('lib/features/zongce/domain/zc_activity.dart').readAsStringSync();
      expect(act, contains('keywords: zcContestKeywords(name)'));
      expect(act, contains('keywords: [s]'));
    });
  });
}
