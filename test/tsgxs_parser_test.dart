import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/library_edu/data/anti_corruption/tsgxs_html_parser.dart';

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('首页 /Web/User', () {
    test('解析出 5 个章节与默认皮肤', () {
      final home = parseTsgxsHome(_fixture('tsgxs_home.html'));
      expect(home.chapterIds.length, 5);
      expect(home.chapterIds.first, '7f6d456b-2372-4b80-8e5a-0f6bf8c979c4');
      expect(home.chapterIds.last, '20105737-bde6-4e0a-8c2f-f4f07e0016e8');
      expect(home.themeId, '5d037bb3-12c5-4554-a3c2-d128766dd025');
      // 去重:同一章节不应重复出现
      expect(home.chapterIds.toSet().length, home.chapterIds.length);
    });
  });

  group('章节地图', () {
    test('本馆概况:4 个线索、已看完、考点状态 1', () {
      final ch = parseTsgxsChapter(_fixture('tsgxs_chapter_0.html'),
          '7f6d456b-2372-4b80-8e5a-0f6bf8c979c4');
      expect(ch.title, '本馆概况');
      expect(ch.nodes.length, 4);
      expect(ch.isVisitAll, isTrue);
      expect(ch.examinations, 1);
      expect(ch.canStartExam, isTrue);
      final first = ch.nodes.first;
      expect(first.id, '4ae143eb-b16c-4ad4-bba9-0d27973fe99b');
      expect(first.name, '图书馆概况');
      expect(first.imageUrl, startsWith('/upload/image/'));
    });

    test('图书借还:7 个线索(无 data-intro 时名称为空)', () {
      final ch = parseTsgxsChapter(_fixture('tsgxs_chapter_2.html'),
          '3d45bec2-f8b8-48a6-a168-868db11b43c0');
      expect(ch.title, '图书借还');
      expect(ch.nodes.length, 7);
      expect(ch.nodes.first.name, isNull);
      expect(ch.nodes.first.imageUrl, contains('/upload/image/'));
      expect(ch.isVisitAll, isTrue);
    });
  });

  group('内容页', () {
    test('解析标题/正文图/前后导航/返回章节', () {
      final c = parseTsgxsContent(_fixture('tsgxs_content.html'),
          '4ae143eb-b16c-4ad4-bba9-0d27973fe99b');
      expect(c.title, '图书馆概况');
      expect(c.imageUrls,
          contains('/upload/image/48C778A821F5819FA93B483377210BDA.jpg'));
      expect(c.prevNodeId, '0cb66dd4-d966-4768-a027-3318fddc096b');
      expect(c.nextNodeId, '9605f523-8b0e-416d-a084-6d3930a51468');
      expect(c.chapterId, '7f6d456b-2372-4b80-8e5a-0f6bf8c979c4');
    });
  });

  group('我的成绩', () {
    test('两张表去重后得到一条成绩', () {
      final grades = parseTsgxsGrades(_fixture('tsgxs_grades.html'));
      expect(grades.length, 1);
      expect(grades.first.score, '93.00');
      expect(grades.first.elapsed, '8分59秒');
      expect(grades.first.examTime, '2026/7/1 15:29:33');
    });
  });

  group('排行榜', () {
    test('解析名次/分数/用时并去掉“分”字', () {
      final rank = parseTsgxsRanking(_fixture('tsgxs_top.html'));
      expect(rank.rows, isNotEmpty);
      final me = rank.rows.firstWhere((r) => r.rank == 19905);
      expect(me.score, '93.00');
      expect(me.elapsed, '8分59秒');
      expect(rank.note, contains('未通过考试将不显示在排行榜中'));
    });
  });

  group('个人资料', () {
    test('解析账号/姓名/学院', () {
      final p = parseTsgxsProfile(_fixture('tsgxs_profile.html'));
      expect(p.account, '2000000000');
      expect(p.name, '某同学');
      expect(p.college, contains('计算机与人工智能学院'));
    });
  });
}
