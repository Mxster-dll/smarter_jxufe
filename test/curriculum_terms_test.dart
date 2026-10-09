// 培养方案「开课学期」侧表 + 仓库缓存口径守卫（2026-10-09 立）。
//
// 守的是本轮新增的那条数据链：
// - `CurriculumMapper.semestersFromRows` **按表头名**取「学年学期」列（表里夹着隐藏列，
//   按下标会错位）、缺列不瞎兜；
// - `CurriculumTerms` 的 JSON 容错（旧缓存缺字段 / 类型不对不许炸）；
// - 学期文本归一走 `school_calendar`（认不出 → 「未排定」，**不猜**）；
// - `CurriculumRepository`：抓一次表把课程 + 侧表**一起落盘**；侧表与课程表条数
//   对不上时重抓而不是错配；抓不到时缓存照旧可用。
//
// 数据全是**合成**的（照真实表形状缩样，不掺任何真实学籍 / 课表）。

import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_terms_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 合成一张「查看教学计划表」HTML（形状照真表：序号 / 学年学期 / 课程 / 学分 /
/// 课程类别 / 课程地位 / 考核方式 / 总学时 / 讲授 / 实验 / 实践 / 其它 / 周学时 / 标识）。
///
/// [rows] 不含表头。
String _theoryHtml(List<List<String>> rows) {
  const head = [
    '序号',
    '学年学期',
    '课程',
    '学分',
    '课程类别',
    '课程地位',
    '考核方式',
    '总学时',
    '讲授学时',
    '实验学时',
    '实践学时',
    '其它学时',
    '周学时',
    '标识',
  ];
  String cell(String tag, String text) => '<$tag>$text</$tag>';
  final trs = [
    '<tr>${head.map((h) => cell('th', h)).join()}</tr>',
    for (final row in rows) '<tr>${row.map((c) => cell('td', c)).join()}</tr>',
  ];
  return '<html><body><table><tbody>${trs.join()}</tbody></table></body></html>';
}

const _row1 = [
  '1',
  '2025-2026学年第一学期',
  '[1000000001]高等数学A',
  '4.0',
  '2024公共课/公共数学课/必修课',
  '主干课程',
  '考试',
  '64',
  '64',
  '0',
  '0',
  '0',
  '4.0',
  '',
];

const _row2 = [
  '2',
  '2025-2026学年第二学期',
  '[1000000002]程序设计基础',
  '3.0',
  '2024专业教育课/学科基础课/必修课',
  '非主干课程',
  '考试',
  '48',
  '32',
  '16',
  '0',
  '0',
  '3.0',
  '',
];

/// 第三行：**教务没排定学期**（真表里确实有空值行）。
const _row3 = [
  '3',
  '',
  '[1000000003]专业方向选修',
  '2.0',
  '2024专业教育课/专业方向课/选修课',
  '非主干课程',
  '考查',
  '32',
  '32',
  '0',
  '0',
  '0',
  '2.0',
  '',
];

/// 内存版会话存储（不发网络、不落盘）。
class _MemSessionStore implements ImsSessionStore {
  _MemSessionStore(this.token);

  final String? token;

  @override
  Future<String?> read(String account) async => token;

  @override
  Future<void> write(String account, String jsessionId) async {}

  @override
  Future<String?> migrateLegacy(String account) async => null;

  @override
  Future<void> forget(String account) async {}
}

/// 假远程数据源：只回一份固定 HTML（顺便数一数被调了几次）。
class _FakeRemote extends CurriculumRemoteDataSource {
  _FakeRemote(this.html) : super(Dio());

  final String html;
  int calls = 0;

  @override
  Future<String> getCurriculumHtmlByKey(
    CurriculumKey key, {
    required String jsessionId,
  }) async {
    calls++;
    return html;
  }
}

/// 「没有教务会话」的取票口（**返回 Left**，不是抛异常）。
class _NoSessionAuth extends ImsAuthRepository {
  _NoSessionAuth()
    : super(
        ImsSession(
          account: '2202500001',
          dio: Dio(),
          store: _MemSessionStore(null),
          resolveRedirect: () async =>
              (url: 'https://example.invalid', gid: null),
        ),
      );

  @override
  Future<Either<Failure, String?>> getJsessionId({
    bool forceRefresh = false,
  }) async => const Left(UnknownFailure('没有教务会话'));
}

ImsAuthRepository _authed() => ImsAuthRepository(
  ImsSession(
    account: '2202500001',
    dio: Dio(),
    store: _MemSessionStore('FAKE-SESSION'),
    resolveRedirect: () async => (url: 'https://example.invalid', gid: null),
  ),
);

void main() {
  final college = College('44', '计算机与人工智能学院', '44');
  final major = Major(
    id: '4405',
    name: '计算机科学与技术',
    code: '4405',
    year: 2025,
    collegeName: '计算机与人工智能学院',
  );

  group('mapper：按表头名取「学年学期」列', () {
    final mapper = CurriculumMapper();
    final matrix = CurriculumHtmlParser().parse(
      _theoryHtml([_row1, _row2, _row3]),
    );

    test('★ 与课程同序同长，空格原样保留（未排定就是空串）', () {
      expect(mapper.semestersFromRows(matrix), [
        '2025-2026学年第一学期',
        '2025-2026学年第二学期',
        '',
      ]);
      expect(
        mapper.semestersFromRows(matrix).length,
        mapper.fromRows(matrix).length,
        reason: '侧表必须与课程表一一对应',
      );
    });

    test('表头改名（开课学期）也认', () {
      final renamed = CurriculumHtmlParser().parse(
        _theoryHtml([
          _row1,
        ]).replaceFirst('<th>学年学期</th>', '<th>开课学期</th>'),
      );
      expect(mapper.semestersFromRows(renamed), ['2025-2026学年第一学期']);
    });

    test('★ 没有这一列时返回空列表（不瞎兜一个默认学期）', () {
      final noTerm = CurriculumHtmlParser().parse(
        _theoryHtml([
          _row1,
        ]).replaceFirst('<th>学年学期</th>', '<th>备注</th>'),
      );
      expect(mapper.semestersFromRows(noTerm), isEmpty);
    });

    test('只有表头（没有数据行）→ 空列表', () {
      expect(
        mapper.semestersFromRows(CurriculumHtmlParser().parse(_theoryHtml([]))),
        isEmpty,
      );
    });
  });

  group('学期文本归一（走 school_calendar 口径）', () {
    test('教务原文 → 界面标签 / 短码 / 排序键', () {
      expect(
        curriculumTermLabel('2025-2026学年第一学期'),
        '2025-2026 学年第一学期',
      );
      expect(curriculumTermCode('2025-2026学年第一学期'), '251');
      expect(curriculumTermSortKey('2025-2026学年第一学期'), 20250);
      // 学年在前、学段在后：第一学期 < 第二学期 < 下一学年
      expect(
        curriculumTermSortKey('2025-2026学年第二学期'),
        greaterThan(curriculumTermSortKey('2025-2026学年第一学期')),
      );
      expect(
        curriculumTermSortKey('2026-2027学年第一学期'),
        greaterThan(curriculumTermSortKey('2025-2026学年第二学期')),
      );
    });

    test('★ 空 / 认不出的学期：写「未排定」、短码为空、排序排最后（不当成第一学期）', () {
      for (final raw in ['', '   ', '待定', '2025']) {
        expect(curriculumTermLabel(raw), kCurriculumTermUnassigned);
        expect(curriculumTermCode(raw), '');
        expect(curriculumTermSortKey(raw), termSortKeyUnknown);
      }
      expect(
        termSortKeyUnknown,
        greaterThan(curriculumTermSortKey('2030-2031学年第二学期')),
      );
    });
  });

  group('CurriculumTerms：JSON 容错', () {
    test('往返一致', () {
      const terms = CurriculumTerms(
        year: 2025,
        collegeName: '计算机与人工智能学院',
        majorName: '计算机科学与技术',
        entries: [
          CurriculumTermEntry(
            code: '1000000001',
            name: '高等数学A',
            semester: '2025-2026学年第一学期',
          ),
          CurriculumTermEntry(code: '', name: '无码课', semester: ''),
        ],
      );
      final back = CurriculumTerms.fromMap(terms.toMap());
      expect(back.semesters, ['2025-2026学年第一学期', '']);
      expect(back.alignsWith(2), isTrue);
      expect(back.alignsWith(3), isFalse);
      expect(back.hasAnySemester, isTrue);
    });

    test('★ 脏数据不许炸：缺字段 / 类型不对 / entries 不是列表', () {
      final broken = CurriculumTerms.fromMap({
        'year': '2025', // 字符串年份（旧版本写过）
        'entries': [
          {'code': 123, 'name': null, 'semester': 456},
          'not-a-map',
        ],
      });
      expect(broken.year, 2025);
      expect(broken.entries.length, 1, reason: '非 Map 的条目直接跳过');
      expect(broken.entries.single.code, '123', reason: '数字照样转成文本，不许抛');
      expect(broken.entries.single.name, '');
      expect(broken.entries.single.semester, '456');
      // 认不出来的学期照样按「未排定」显示，不会错配到某个真学期
      expect(curriculumTermLabel(broken.entries.single.semester), kCurriculumTermUnassigned);

      expect(
        CurriculumTerms.fromMap({'entries': 'oops'}).entries,
        isEmpty,
        reason: 'entries 类型不对时当作空表，不许抛',
      );
    });
  });

  group('本地缓存 + 仓库（真 Hive，合成数据）', () {
    late Directory dir;
    late CurriculumLocalDataSource local;
    late CurriculumTermsLocalDataSource termsLocal;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('curriculum_data_');
      Hive.init(dir.path);
      Hive.registerAdapter(AssessmentMethodAdapter());
      Hive.registerAdapter(CourseImportanceAdapter());
      Hive.registerAdapter(CourseNatureAdapter());
      Hive.registerAdapter(CourseRequirementAdapter());
      Hive.registerAdapter(CreditHourAdapter());
      Hive.registerAdapter(CourseAdapter());
      Hive.registerAdapter(CurriculumAdapter());
      Hive.registerAdapter(MajorAdapter());
      Hive.registerAdapter(CollegeAdapter());
    });

    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    setUp(() async {
      local = CurriculumLocalDataSource(
        await Hive.openBox<Curriculum>(curriculumBoxName),
      );
      termsLocal = CurriculumTermsLocalDataSource(
        await Hive.openBox<String>(curriculumTermsBoxName),
      );
      await local.clearAll();
      await termsLocal.clearAll();
    });

    CurriculumRepository repo(CurriculumRemoteDataSource remote) =>
        CurriculumRepository(
          localDataSource: local,
          remoteDataSource: remote,
          termsLocalDataSource: termsLocal,
          htmlParser: CurriculumHtmlParser(),
          curriculumMapper: CurriculumMapper(),
          imsAuthRepo: _authed(),
        );

    test('缓存：写进去读得出来，坏 JSON 返回 null', () async {
      await termsLocal.save(
        year: 2025,
        collegeName: '计算机与人工智能学院',
        majorName: '计算机科学与技术',
        terms: const CurriculumTerms(
          year: 2025,
          collegeName: '计算机与人工智能学院',
          majorName: '计算机科学与技术',
          entries: [
            CurriculumTermEntry(
              code: '1000000001',
              name: '高等数学A',
              semester: '2025-2026学年第一学期',
            ),
          ],
        ),
      );
      expect(
        termsLocal.get(2025, '计算机与人工智能学院', '计算机科学与技术')?.semesters,
        ['2025-2026学年第一学期'],
      );

      final termsBox = await Hive.openBox<String>(curriculumTermsBoxName);
      await termsBox.put(
        termsLocal.keyString(2025, '计算机与人工智能学院', '计算机科学与技术'),
        '{坏 JSON',
      );
      expect(
        termsLocal.get(2025, '计算机与人工智能学院', '计算机科学与技术'),
        isNull,
      );
    });

    test('★ 首次抓表：课程与侧表一起写下来（侧表条数 = 课程条数）', () async {
      final remote = _FakeRemote(_theoryHtml([_row1, _row2, _row3]));
      final repository = repo(remote);

      final courses = (await repository.getCurriculumIn(
        2025,
        college,
        major,
      )).getOrElse(() => throw StateError('应当成功'));
      expect(courses.courses.length, 3);
      expect(remote.calls, 1);

      // 紧接着取开课学期：**不再发请求**（上一步已落盘）
      final semesters = (await repository.getCourseSemestersIn(
        2025,
        college,
        major,
      )).getOrElse(() => throw StateError('应当成功'));
      expect(semesters, ['2025-2026学年第一学期', '2025-2026学年第二学期', '']);
      expect(remote.calls, 1, reason: '侧表已随课程表落盘，这一步该命中缓存');
    });

    test('★ 侧表与课程表条数对不上（老缓存 / 方案改过）→ 重抓，不把学期错配给别的课', () async {
      final remote = _FakeRemote(_theoryHtml([_row1, _row2, _row3]));
      final repository = repo(remote);
      await repository.getCurriculumIn(2025, college, major);

      // 手工把侧表写短（模拟条数漂移）
      await termsLocal.save(
        year: 2025,
        collegeName: college.name,
        majorName: major.name,
        terms: CurriculumTerms(
          year: 2025,
          collegeName: college.name,
          majorName: major.name,
          entries: const [
            CurriculumTermEntry(
              code: 'x',
              name: 'y',
              semester: '2025-2026学年第一学期',
            ),
          ],
        ),
      );

      final semesters = (await repository.getCourseSemestersIn(
        2025,
        college,
        major,
      )).getOrElse(() => throw StateError('应当成功'));
      expect(semesters.length, 3);
      expect(remote.calls, 2, reason: '对不上就该重抓一次');
    });

    test('老缓存只有课程表（没有侧表）→ 为侧表补抓一次', () async {
      final remote = _FakeRemote(_theoryHtml([_row1, _row2]));
      final repository = repo(remote);
      await local.saveCurriculumByKey(
        CurriculumKey(year: 2025, college: college, major: major),
        Curriculum(
          year: 2025,
          collegeName: college.name,
          majorName: major.name,
          courses: const [],
        ),
      );

      final semesters = (await repository.getCourseSemestersIn(
        2025,
        college,
        major,
      )).getOrElse(() => throw StateError('应当成功'));
      expect(semesters, ['2025-2026学年第一学期', '2025-2026学年第二学期']);
      expect(remote.calls, 1);
    });

    test('★ 没有会话：命中缓存时照样拿得到课程表（离线不退化）', () async {
      final repository = CurriculumRepository(
        localDataSource: local,
        remoteDataSource: _FakeRemote(_theoryHtml([_row1])),
        termsLocalDataSource: termsLocal,
        htmlParser: CurriculumHtmlParser(),
        curriculumMapper: CurriculumMapper(),
        imsAuthRepo: _NoSessionAuth(),
      );
      await local.saveCurriculumByKey(
        CurriculumKey(year: 2025, college: college, major: major),
        Curriculum(
          year: 2025,
          collegeName: college.name,
          majorName: major.name,
          courses: const [],
        ),
      );

      final cached = await repository.getCurriculumIn(2025, college, major);
      expect(cached.isRight(), isTrue, reason: '命中缓存时压根不该去取票');

      // 侧表没有缓存 → 必须如实报错，而不是回一份空学期列表冒充「都没排定」
      final missing = await repository.getCourseSemestersIn(
        2025,
        college,
        major,
      );
      expect(missing.isLeft(), isTrue);
      expect(
        missing.fold((failure) => failure.message, (_) => ''),
        contains('没有教务会话'),
        reason: '失败原因要如实往上抛（页面照它提示「没取到」）',
      );
    });
  });
}
