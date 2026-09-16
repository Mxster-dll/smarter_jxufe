/// 公共查询「按当前账号预填」的匹配守卫。
///
/// 选项数据全部是 **2026-09-14 真实会话实测抓下来的**（`MsSchoolArea` / `MsYXB` /
/// `MsYXB_Specialty` / `kbbp_dykb_SpecialClassComb`），学籍值取自真实 `studentInfo`
/// 缓存（`2025` 级计算机科学与技术252）。改匹配规则先动这里。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';

/// 校区 `MsSchoolArea`（实测 6 条，`name` 原样）。
const _campuses = <PublicQueryOption>[
  PublicQueryOption(code: '05', name: '深圳校区'),
  PublicQueryOption(code: '06', name: '北京校区'),
  PublicQueryOption(code: '07', name: '上海校区'),
  PublicQueryOption(code: '1', name: '蛟桥园校区'),
  PublicQueryOption(code: '3', name: '麦庐园校区'),
  PublicQueryOption(code: '4', name: '枫林园校区'),
];

/// 学院 `MsYXB`（`nj=2025&isYXB=0`，实测 44 条，这里取真实的前几条 + 计算机）。
const _colleges = <PublicQueryOption>[
  PublicQueryOption(code: '0032', name: '[007]产业经济研究院（规制与竞争研究中心）'),
  PublicQueryOption(code: '00', name: '[010]经济管理与创业模拟实验教学中心'),
  PublicQueryOption(code: '31', name: '[011]深圳研究院'),
  PublicQueryOption(code: '36', name: '[020]人事处、党委教师工作部、人力资源中心'),
  PublicQueryOption(code: '01', name: '[023]教务处'),
  PublicQueryOption(code: '02', name: '[026]学生工作处、学生资助管理中心、心理健康教育与咨询中心'),
  PublicQueryOption(code: '44', name: '[143]计算机与人工智能学院'),
];

/// 专业 `MsYXB_Specialty`（`nj=2025&dwh=44`，实测 9 条，全量）。
const _majors = <PublicQueryOption>[
  PublicQueryOption(code: '4411', name: '[0807171T]人工智能'),
  PublicQueryOption(code: '1842', name: '[08090D2]计算机科学与技术(拔尖实验班)'),
  PublicQueryOption(code: '4405', name: '[08090D5]计算机科学与技术'),
  PublicQueryOption(code: '4402', name: '[080912TK]网络空间安全'),
  PublicQueryOption(code: '4410', name: '[080913TK]网络空间安全(低空数据管理与安全)'),
  PublicQueryOption(code: '4415', name: '[C08090C1]数据科学与大数据技术(中外合作办学)'),
  PublicQueryOption(code: '4413', name: '[C10809021]虚拟现实技术(中外合作办学)'),
  PublicQueryOption(code: '4414', name: '[C12010B1]信息管理与信息系统(中外合作办学)'),
  PublicQueryOption(code: '4403', name: '[E0809925]计算机科学与技术(第二学士学位)'),
];

/// 班级选择器（`nj=2025&xqdm=3` 麦庐园，实测 83 条，这里取计算机相关的真实条目）。
const _classes = <PublicQueryOption>[
  PublicQueryOption(code: '250807171T2', name: '[250807171T2]人工智能252'),
  PublicQueryOption(code: '2508090D21', name: '[2508090D21]计算机科学与技术(拔尖实验班)251'),
  PublicQueryOption(code: '2508090D51', name: '[2508090D51]计算机科学与技术251'),
  PublicQueryOption(code: '2508090D52', name: '[2508090D52]计算机科学与技术252'),
  PublicQueryOption(code: '2508090D53', name: '[2508090D53]计算机科学与技术253'),
  PublicQueryOption(code: '2508090D54', name: '[2508090D54]计算机科学与技术254'),
  PublicQueryOption(code: '25E08099251', name: '[25E08099251]25计算机科学与技术S1班'),
  PublicQueryOption(code: '2508090211', name: '[2508090211]软件工程251'),
  PublicQueryOption(code: '2503010011', name: '[2503010011]法学251'),
];

/// 真实学籍（`studentinfo` 缓存实测值）。
const _profile = PublicQueryAccountProfile(
  enrollYear: '2025',
  college: '计算机与人工智能学院',
  major: '计算机科学与技术',
  className: '计算机科学与技术252',
  campusName: '麦庐园校区',
);

void main() {
  group('matchPublicQueryOption 匹配规则', () {
    test('精确优先：专业「计算机科学与技术」命中 4405，而不是拔尖班/第二学士学位', () {
      expect(matchPublicQueryOption(_majors, '计算机科学与技术')?.code, '4405');
    });

    test('精确优先：班级「计算机科学与技术252」命中 2508090D52', () {
      expect(matchPublicQueryOption(_classes, '计算机科学与技术252')?.code,
          '2508090D52');
    });

    test('班级名带前缀的变体（25计算机科学与技术S1班）不会被精确名命中', () {
      // 「计算机科学与技术252」与 S1 班只是「包含」关系，精确项存在时不选它
      final hit = matchPublicQueryOption(_classes, '计算机科学与技术252');
      expect(hit?.displayName, '计算机科学与技术252');
    });

    test('课程名带后缀时可用「包含」兜底：学籍名是选项名的子串', () {
      // 假设学籍只记到「软件工程」而选项是「软件工程251」→ 前缀命中
      expect(matchPublicQueryOption(_classes, '软件工程')?.code, '2508090211');
    });

    test('同级取更短的名字：多个「前缀命中」时选最接近原名的那个', () {
      const options = <PublicQueryOption>[
        PublicQueryOption(code: 'a', name: '[x]网络空间安全(低空数据管理与安全)'),
        PublicQueryOption(code: 'b', name: '[y]网络空间安全'),
      ];
      expect(matchPublicQueryOption(options, '网络空间安全')?.code, 'b');
    });

    test('显示名剥掉方括号后的前缀码参与比较', () {
      expect(matchPublicQueryOption(_colleges, '计算机与人工智能学院')?.code,
          '44');
      // 学籍值若带上 [143] 前缀也应命中（displayName 已剥前缀，这里比对的是原值兜底）
      expect(
        matchPublicQueryOption(_colleges, '[143]计算机与人工智能学院')?.code,
        '44',
      );
    });
  });

  group('matchPublicQueryOption 容错', () {
    test('已设置但教务没有的校区（青山园校区）返回 null，不猜', () {
      expect(matchPublicQueryOption(_campuses, '青山园校区'), isNull);
    });

    test('空名称 / 空列表 / 全空候选都返回 null', () {
      expect(matchPublicQueryOption(_campuses, ''), isNull);
      expect(matchPublicQueryOption(_campuses, '   '), isNull);
      expect(matchPublicQueryOption(const [], '麦庐园校区'), isNull);
    });

    test('名称归一化：首尾空格、字间空格、全角括号都能匹配', () {
      expect(matchPublicQueryOption(_colleges, ' 计算机与人工智能学院 ')?.code,
          '44');
      expect(matchPublicQueryOption(_majors, '计算机科学与技术（拔尖实验班）')?.code,
          '1842');
    });

    test('候选项里 displayName 为空（纯 [码]）会被跳过', () {
      const options = <PublicQueryOption>[
        PublicQueryOption(code: 'z', name: '[2612020C11]'),
        PublicQueryOption(code: 'y', name: '[2612020C12]会计学261'),
      ];
      expect(matchPublicQueryOption(options, '会计学261')?.code, 'y');
    });
  });

  group('publicQueryGradeOf 年级口径', () {
    test('学籍入学年落在下拉范围内时用它（2025 级而不是学年 2026）', () {
      expect(publicQueryGradeOf('2025', 2026), '2025');
      expect(publicQueryGradeOf('2026', 2026), '2026');
      expect(publicQueryGradeOf('2022', 2026), '2022'); // 下界 base-4
    });

    test('超出范围 / 空 / 非数字一律回退学年', () {
      expect(publicQueryGradeOf('2016', 2026), '2026');
      expect(publicQueryGradeOf('2030', 2026), '2026');
      expect(publicQueryGradeOf('', 2026), '2026');
      expect(publicQueryGradeOf('  ', 2026), '2026');
      expect(publicQueryGradeOf('二〇二五', 2026), '2026');
    });

    test('带空格的真实学籍值（"2025 "）也能解析', () {
      expect(publicQueryGradeOf('2025 ', 2026), '2025');
    });
  });

  group('resolvePublicQueryAccountDefaults 全链路', () {
    test('真实账号（2025 级计算机科学与技术252 @麦庐园）四项全中', () {
      final defaults = resolvePublicQueryAccountDefaults(
        profile: _profile,
        baseYear: 2026,
        campuses: _campuses,
        colleges: _colleges,
        majors: _majors,
        classes: _classes,
      );
      expect(defaults.isEmpty, isFalse);
      expect(defaults.grade, '2025');
      expect(defaults.campus?.code, '3');
      expect(defaults.campus?.displayName, '麦庐园校区');
      expect(defaults.college?.code, '44');
      expect(defaults.major?.code, '4405');
      expect(defaults.klass?.code, '2508090D52');
      expect(defaults.klass?.displayName, '计算机科学与技术252');
    });

    test('学籍为空时：年级仍给出学年，其余留空（不误填）', () {
      final defaults = resolvePublicQueryAccountDefaults(
        profile: const PublicQueryAccountProfile(campusName: '麦庐园校区'),
        baseYear: 2026,
        campuses: _campuses,
        colleges: _colleges,
        majors: _majors,
        classes: _classes,
      );
      expect(defaults.grade, '2026');
      expect(defaults.campus?.code, '3');
      expect(defaults.college, isNull);
      expect(defaults.major, isNull);
      expect(defaults.klass, isNull);
    });

    test('某一层取不到（学院列表为空）不影响其它层各自匹配', () {
      final defaults = resolvePublicQueryAccountDefaults(
        profile: _profile,
        baseYear: 2026,
        campuses: _campuses,
        colleges: const [],
        majors: _majors,
        classes: _classes,
      );
      expect(defaults.college, isNull);
      expect(defaults.major?.code, '4405');
      expect(defaults.klass?.code, '2508090D52');
    });

    test('校区没设偏好 → 校区留空，但班级仍按传入列表匹配（界面层会跨校区再试）', () {
      final defaults = resolvePublicQueryAccountDefaults(
        profile: const PublicQueryAccountProfile(
          enrollYear: '2025',
          college: '计算机与人工智能学院',
          major: '计算机科学与技术',
          className: '计算机科学与技术252',
        ),
        baseYear: 2026,
        campuses: _campuses,
        colleges: _colleges,
        majors: _majors,
        classes: _classes,
      );
      expect(defaults.campus, isNull);
      expect(defaults.klass?.code, '2508090D52');
    });

    test('全空输入：只剩年级（学年兜底），其余四项全空', () {
      final defaults = resolvePublicQueryAccountDefaults(
        profile: const PublicQueryAccountProfile(),
        baseYear: 2026,
      );
      expect(defaults.grade, '2026');
      expect(defaults.campus, isNull);
      expect(defaults.college, isNull);
      expect(defaults.major, isNull);
      expect(defaults.klass, isNull);
      expect(PublicQueryAccountDefaults.empty.isEmpty, isTrue);
    });

    test('profile.isEmpty 判据：只有校区也算有信息', () {
      expect(const PublicQueryAccountProfile().isEmpty, isTrue);
      expect(
        const PublicQueryAccountProfile(campusName: '麦庐园校区').isEmpty,
        isFalse,
      );
      expect(const PublicQueryAccountProfile(enrollYear: '2025').isEmpty, isFalse);
    });
  });
}
