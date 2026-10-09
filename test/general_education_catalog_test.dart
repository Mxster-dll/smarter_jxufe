import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/graduation_requirements/data/anti_corruption/general_education_catalog_parser.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/general_education_catalog_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('canonicalCategoryKey：把四种写法归一到同一个键', () {
    // 表的左边 = 真实数据里出现过的原文，右边 = 必须归到同一个键。
    // 来源：教务「毕业学分要求」7 项（§13 实测）、课程库「模块」列、
    // 培养方案「课程类别」二级分类（真实 curriculums.hive）。
    const ledger = <String, String>{
      // 教务要求项（tableId=6033 实测原文）
      '2024公共外语选修课': '公共外语课',
      '2024美育选修2学分': '美育',
      '2024科学、技术与方法选修2学分': '科学技术与方法',
      '2024历史、政治与社会选修2学分': '历史政治与社会',
      '2024哲学、思维与语言选修2学分': '哲学思维与语言',
      '2024学科开放选修课': '学科开放课',
      '2024专业方向选修课': '专业方向课',
      // 课程库「模块」列（三张 sheet 的全部取值）
      '历史、政治与社会（经典阅读）': '历史政治与社会',
      '哲学、思维与语言': '哲学思维与语言',
      '科学技术与方法': '科学技术与方法',
      '美育': '美育',
      '发展指导课': '发展指导课',
      // 培养方案二级分类（真实 curriculums.hive）
      '公共外语课': '公共外语课',
      '学科开放课': '学科开放课',
      '专业方向课': '专业方向课',
      '专业限选课': '专业限选课',
      '专业必修课': '专业必修课',
      '学科基础课': '学科基础课',
      '公共数学课': '公共数学课',
      '思想政治理论课': '思想政治理论课',
      '哲学、思维与语言模块': '哲学思维与语言',
      '科学、技术与方法模块': '科学技术与方法',
      '历史、政治与社会模块': '历史政治与社会',
      '美育模块': '美育',
    };

    ledger.forEach((raw, want) {
      test('「$raw」→「$want」', () {
        expect(canonicalCategoryKey(raw), want);
      });
    });

    test('★ 要求项与培养方案/课程库的写法必须落到同一个键', () {
      // 左边是教务要求项，右边是「课程库里能顶它的那些课」的类别写法。
      const pairs = <String, List<String>>{
        '2024公共外语选修课': ['公共外语课'],
        '2024学科开放选修课': ['学科开放课'],
        '2024专业方向选修课': ['专业方向课'],
        '2024美育选修2学分': ['美育', '美育模块'],
        '2024科学、技术与方法选修2学分': ['科学技术与方法', '科学、技术与方法模块'],
        '2024历史、政治与社会选修2学分': [
          '历史、政治与社会（经典阅读）',
          '历史、政治与社会模块',
        ],
        '2024哲学、思维与语言选修2学分': ['哲学、思维与语言', '哲学、思维与语言模块'],
      };
      pairs.forEach((requirement, sources) {
        final want = canonicalCategoryKey(requirement);
        for (final s in sources) {
          expect(canonicalCategoryKey(s), want, reason: '「$s」应归到「$requirement」');
        }
      });
    });

    test('★ 「专业必修课 / 专业限选课 / 专业方向课」不许塌成同一个键', () {
      // 2026-10-08 的实测回归：早先把「课/必修/限选」也当噪音剥，
      // 三者会一路塌成「专业」，必修与限选混成一类。
      final keys = {
        canonicalCategoryKey('专业必修课'),
        canonicalCategoryKey('专业限选课'),
        canonicalCategoryKey('专业方向课'),
      };
      expect(keys, hasLength(3), reason: '三个类别必须是三个键，实际：$keys');
    });

    test('空串与纯噪音归一成空串', () {
      expect(canonicalCategoryKey(''), '');
      expect(canonicalCategoryKey('   '), '');
      expect(canonicalCategoryKey('2024'), '');
      expect(canonicalCategoryKey('（2024）'), '');
    });
  });

  group('generalEducationModuleOf：认得出四个模块，认不出返回 null', () {
    test('课程库模块名', () {
      expect(
        generalEducationModuleOf('历史、政治与社会（经典阅读）'),
        GeneralEducationModule.historyPoliticsSociety,
      );
      expect(
        generalEducationModuleOf('科学技术与方法'),
        GeneralEducationModule.scienceTechnologyMethod,
      );
      expect(
        generalEducationModuleOf('发展指导课'),
        GeneralEducationModule.developmentGuidance,
      );
    });

    test('教务要求项名也能直接落到模块上', () {
      expect(
        generalEducationModuleOf('2024科学、技术与方法选修2学分'),
        GeneralEducationModule.scienceTechnologyMethod,
      );
      expect(
        generalEducationModuleOf('2024美育选修2学分'),
        GeneralEducationModule.aesthetic,
      );
    });

    test('「公共外语」不是通识模块（它是培养方案里的类别）', () {
      expect(generalEducationModuleOf('2024公共外语选修课'), isNull);
      expect(generalEducationModuleOf('学科开放课'), isNull);
    });

    test('不认识的原样返回 null，不瞎猜', () {
      expect(generalEducationModuleOf('劳动教育'), isNull);
      expect(generalEducationModuleOf('创新创业'), isNull);
      expect(generalEducationModuleOf('美'), isNull, reason: '一个字不许蒙「美育」');
    });
  });

  group('自定义表也要能解析（asset 之外的写法）', () {
    const parser = GeneralEducationCatalogParser();

    test('空 JSON → 空目录，不抛', () {
      final c = parser.parse(const {});
      expect(c.sheets, isEmpty);
      expect(c.revision, '');
    });

    test('字段缺失 / 类型不对一律容错', () {
      final c = parser.parse(const {
        'revision': 20260623, // 不是 String
        'sheets': [
          'not a map',
          {'title': 'T', 'courses': 'not a list'},
          {
            'title': 'T2',
            'cohortFrom': '2024', // 字符串数字
            'courses': [
              'nope',
              {'name': '', 'code': ''}, // 全空 → 丢
              {'name': '只有名字'},
              {'code': '1', 'name': 'X', 'credit': '1.5', 'module': '美育'},
            ],
          },
        ],
      });
      expect(c.revision, '');
      expect(c.sheets, hasLength(1));
      final sheet = c.sheets.single;
      expect(sheet.cohortFrom, 2024);
      expect(sheet.courses.map((e) => e.name), ['只有名字', 'X']);
      expect(sheet.courses.last.credit, 1.5);
      expect(sheet.courses.last.module, GeneralEducationModule.aesthetic);
    });
  });

  group('★ 真实 asset 台账（学校改版后重跑工具，这几条会提醒你核对）', () {
    late GeneralEducationCatalog catalog;

    setUpAll(() async {
      final raw = await rootBundle.loadString(kGeneralEducationCatalogAsset);
      catalog = const GeneralEducationCatalogParser().parse(
        json.decode(raw) as Map<String, dynamic>,
      );
    });

    test('三张 sheet 的规模与适用年级', () {
      expect(catalog.sheets, hasLength(3));
      final s1 = catalog.sheets[0];
      final s2 = catalog.sheets[1];
      final s3 = catalog.sheets[2];
      expect((s1.cohortFrom, s1.cohortTo), (2021, 2023));
      expect(s1.courses, hasLength(275));
      expect((s2.cohortFrom, s2.cohortTo), (2024, 2025));
      expect(s2.courses, hasLength(295));
      expect(s3.allCohorts, isTrue);
      expect(s3.courses, hasLength(162));
      expect(catalog.revision, '2026-06-23');
    });

    test('2021-2023 那张表开头 89 门在源表里没有模块标签（真实缺口，别当成 bug 修）', () {
      final s1 = catalog.sheets[0];
      final noModule = [
        for (final c in s1.courses)
          if (c.module == null) c,
      ];
      expect(noModule, hasLength(89));
      expect(noModule.first.name, '管理学通论');
      expect(noModule.last.name, '战后日本经济与社会');
    });

    test('模块分布（合并单元格回填正确的话就是这个数）', () {
      Map<GeneralEducationModule?, int> dist(GeneralEducationSheet s) {
        final m = <GeneralEducationModule?, int>{};
        for (final c in s.courses) {
          m[c.module] = (m[c.module] ?? 0) + 1;
        }
        return m;
      }

      final s2 = dist(catalog.sheets[1]);
      expect(s2[GeneralEducationModule.historyPoliticsSociety], 100);
      expect(s2[GeneralEducationModule.philosophyThinkingLanguage], 37);
      expect(s2[GeneralEducationModule.scienceTechnologyMethod], 51);
      expect(s2[GeneralEducationModule.aesthetic], 107);
      expect(s2[GeneralEducationModule.developmentGuidance], isNull);
    });

    test('按 2025 级查表 = 2024-2025 表 + 各年级表', () {
      final scope = catalog.scopeFor(2025);
      expect(scope.exactCohortMatch, isTrue);
      expect(scope.sheets, hasLength(2));
      expect(scope.sheets.first.cohortFrom, 2024);
      expect(scope.sheets.last.allCohorts, isTrue);
    });

    test('按 2022 级查表 = 2021-2023 表 + 各年级表', () {
      final scope = catalog.scopeFor(2022);
      expect(scope.exactCohortMatch, isTrue);
      expect(scope.sheets, hasLength(2));
      expect(scope.sheets.first.cohortTo, 2023);
    });

    test('学校还没下发该年级的表 → 退到最新一张，并把 exactCohortMatch 置 false', () {
      for (final cohort in [2026, 2030, null]) {
        final scope = catalog.scopeFor(cohort);
        expect(scope.exactCohortMatch, isFalse, reason: 'cohort=$cohort');
        expect(scope.sheets, hasLength(2));
        expect(scope.sheets.first.cohortTo, 2025, reason: '退到 cohortTo 最大的那张');
        expect(scope.sheets.last.allCohorts, isTrue);
      }
    });

    test('代码 / 并列码 / 旧码 / 课程名 四路都能查到', () {
      final index = catalog.indexFor(2025);
      // 主码
      expect(index.byCode('1004507622')?.name, '管理学通论');
      // 旧码（备注里的「原代码」）→ 同一门课
      expect(index.byCode('1004505521')?.name, '管理学通论');
      // 一排并列码（军事与艺术 I~IV 写在一格里）
      expect(index.byCode('1900200051')?.name, '军事与艺术I、II、III、IV');
      expect(index.byCode('1900200061')?.name, '军事与艺术I、II、III、IV');
      expect(index.byCode('1900200081')?.name, '军事与艺术I、II、III、IV');
      // 外校网课的旧码
      expect(index.byCode('1602300052')?.name, '《汉书》导读(尔雅网络课程)');
      // 名字兜底
      expect(index.byName('管理学通论')?.code, '1004507622');
      // 查不到就是 null
      expect(index.byCode('9999999999'), isNull);
      expect(index.lookup(code: '', name: ''), isNull);
    });

    test('同一门课在两张表里都有时，先命中的年级表说了算', () {
      // 管理学通论：2021-2023 表里没模块标签，2024-2025 表里归「历史、政治与社会」。
      // 2025 级只看得到后者 → 必须是「历史政治与社会」。
      expect(
        catalog.indexFor(2025).moduleOf(code: '1004507622'),
        GeneralEducationModule.historyPoliticsSociety,
      );
      // 2022 级只看得到前者 → 没有模块标签（源表真实缺口）
      expect(catalog.indexFor(2022).moduleOf(code: '1004507622'), isNull);
    });

    test('源表里没有课程编码的两行照实收下（区间学分记 null + 原文）', () {
      final s1 = catalog.sheets[0];
      final nameless = [
        for (final c in s1.courses)
          if (c.code.isEmpty) c,
      ];
      expect(nameless.map((e) => e.name), ['学科前沿课', '竞赛指导课']);
      expect(nameless.first.credit, isNull);
      expect(nameless.first.creditText, '0.5-1');
      expect(nameless.first.module, GeneralEducationModule.developmentGuidance);
      // 没有编码 → 按码查不到，但不会串到别的课上
      expect(catalog.indexFor(2022).byCode(''), isNull);
    });
  });
}
