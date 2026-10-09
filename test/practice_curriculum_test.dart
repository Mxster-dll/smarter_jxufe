import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/practice_curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

/// 培养方案「实践环节」（`pyfa.sjhj.html` / `tableId=2509`）。
///
/// 真实素材 = `test/fixtures/curriculum_practice_2509.html`（2026-10-08 抓包，
/// 2025 级计算机科学与技术）。它证明了一件关键的事：
/// **军事训练只在这张表里**，理论课程表（2508）里没有它。
void main() {
  const parser = PracticeCurriculumHtmlParser();

  late List<PracticeStage> stages;

  setUpAll(() {
    final html = File(
      'test/fixtures/curriculum_practice_2509.html',
    ).readAsStringSync();
    stages = parser.parseHtml(html);
  });

  group('★ 真实抓包台账（学校改表后这条会红，提醒你核对）', () {
    test('4 条实践环节，逐项对上', () {
      expect(stages, hasLength(4));
      final byName = {for (final s in stages) s.name: s};

      expect(byName.keys, {
        '军事训练',
        '创新创业实践活动',
        '毕业实习',
        '毕业设计',
      });
      expect(byName['军事训练']!.code, '1305002302');
      expect(byName['军事训练']!.credit, 2);
      expect(byName['军事训练']!.category, '军训');
      expect(byName['军事训练']!.weeks, 2);
      expect(byName['军事训练']!.semester, '2025-2026学年第一学期');

      expect(byName['创新创业实践活动']!.code, '1302600064');
      expect(byName['创新创业实践活动']!.credit, 4);
      expect(byName['创新创业实践活动']!.category, '科研创新实践');
      expect(byName['毕业实习']!.credit, 4);
      expect(byName['毕业设计']!.credit, 8);
      expect(byName['毕业设计']!.category, '论文设计');
    });

    test('学分合计 = 18（表内为准，不套文件里的「不少于 19」区间）', () {
      final c = PracticeCurriculum(
        year: 2025,
        collegeName: '计算机与人工智能学院',
        majorName: '计算机科学与技术',
        stages: stages,
      );
      expect(c.totalCredits, 18);
      expect(c.codes, {'1305002302', '1302600064', '1314300014', '1314300058'});
    });

    test('考核方式这一列实测恒为「考查」', () {
      expect({for (final s in stages) s.assessment}, {'考查'});
    });

    test('学年学期可以为空（表里后两条就是空的）', () {
      final empty = [for (final s in stages) if (s.semester.isEmpty) s.name];
      expect(empty, ['毕业实习', '毕业设计']);
      // 有学期的那两条照实带出来
      expect(
        {
          for (final s in stages)
            if (s.semester.isNotEmpty) s.name: s.semester,
        },
        {
          '军事训练': '2025-2026学年第一学期',
          '创新创业实践活动': '2028-2029学年第二学期',
        },
      );
    });
  });

  group('解析稳健性', () {
    test('★ 按 name 取列，不按下标（表里夹着隐藏列 hjdm）', () {
      const html = '''
        <table><tbody id="sdTable_tbody">
        <tr>
          <td title="1">1</td>
          <td name="xnxq" style="display:none;">X</td>
          <td name="hj">[999]倒序列测试</td>
          <td name="xf">1.5</td>
          <td name="hjlb">类别</td>
          <td name="khfs">考查</td>
          <td name="zs">3.0</td>
          <td name="bs">标</td>
          <td name="hjdm" style="display:none;">ID</td>
        </tr>
        </tbody></table>
      ''';
      final one = parser.parseHtml(html).single;
      expect(one.code, '999');
      expect(one.name, '倒序列测试');
      expect(one.semester, 'X');
      expect(one.credit, 1.5);
      expect(one.category, '类别');
      expect(one.identification, '标');
      expect(one.detailId, 'ID');
    });

    test('「环节」列没带 [代码] 时整串当名称，不丢行', () {
      const html = '''
        <table><tbody id="sdTable_tbody">
        <tr><td>1</td><td name="hj">无码环节</td><td name="xf">2</td></tr>
        </tbody></table>
      ''';
      final one = parser.parseHtml(html).single;
      expect(one.code, '');
      expect(one.name, '无码环节');
      expect(one.credit, 2);
    });

    test('没有数据表格 → 抛 ImsApiException（不是静默空表）', () {
      expect(
        () => parser.parseHtml('<html><body>nope</body></html>'),
        throwsA(isA<Exception>()),
      );
    });

    test('空 tbody → 空列表', () {
      const html = '<table><tbody id="sdTable_tbody"></tbody></table>';
      expect(parser.parseHtml(html), isEmpty);
    });
  });

  group('PracticeCurriculum 的 JSON 往返（Box<String> 缓存用）', () {
    test('toMap/fromMap 逐字段还原', () {
      final c = PracticeCurriculum(
        year: 2025,
        collegeName: '示例学院',
        majorName: '示例专业',
        lastUpdated: DateTime.parse('2026-10-08T04:00:00.000'),
        stages: stages,
      );
      final back = PracticeCurriculum.fromMap(c.toMap());
      expect(back.year, c.year);
      expect(back.collegeName, c.collegeName);
      expect(back.majorName, c.majorName);
      expect(back.lastUpdated, c.lastUpdated);
      expect(back.stages, hasLength(4));
      expect(back.stages.first.name, '军事训练');
      expect(back.totalCredits, 18);
    });

    test('★ 缺字段 / 类型不对的旧 JSON 不许炸（§3「模型」容错口径）', () {
      final back = PracticeCurriculum.fromMap(const {
        'year': '2025', // 字符串数字
        'stages': [
          'not a map',
          {'name': '只给名字', 'credit': '3'},
        ],
      });
      expect(back.year, 2025);
      expect(back.stages, hasLength(1));
      expect(back.stages.single.name, '只给名字');
      expect(back.stages.single.credit, 3);
      expect(back.collegeName, '');
      expect(back.lastUpdated, isNull);
    });

    test('完全没有 stages 字段 → 空表而不是抛异常', () {
      final back = PracticeCurriculum.fromMap(const {});
      expect(back.stages, isEmpty);
      expect(back.totalCredits, 0);
    });
  });
}
