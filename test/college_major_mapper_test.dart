import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/college/data/anti_corruption/college_filter.dart';
import 'package:smarter_jxufe/features/college/data/anti_corruption/college_mapper.dart';
import 'package:smarter_jxufe/features/college/data/datasources/api_models/api_college.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/major/data/anti_corruption/major_filter.dart';
import 'package:smarter_jxufe/features/major/data/anti_corruption/major_mapper.dart';
import 'package:smarter_jxufe/features/major/data/datasources/api_models/api_major.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 学院 / 专业两个 feature 的 **anti-corruption 层**（mapper + filter）守卫。
///
/// 补测理由（2026-10-08 覆盖度盘点）：这两个 feature 共 28 个源文件里，绝大多数是
/// provider 与其生成物，**真正有逻辑的只有这 4 个小文件（合计 79 行）**，而它们
/// 恰好是「校园接口 → 应用领域模型」的翻译层 —— 脏数据在这里静默发生（学院名解析
/// 失败会变成空 id，去重错会把两个学院并成一个），且此前只有培养方案链路的**间接**覆盖。
void main() {
  group('CollegeMapper.extractCodeAndName：解析「[051]经济学院」', () {
    test('标准形态：抠出方括号里的数字 id，剩下的是名字', () {
      expect(CollegeMapper.extractCodeAndName('[051]经济学院'), ('051', '经济学院'));
    });

    test('没有方括号：id 给空串、名字原样返回（不猜、不截断）', () {
      expect(CollegeMapper.extractCodeAndName('经济学院'), ('', '经济学院'));
      expect(CollegeMapper.extractCodeAndName(''), ('', ''),
          reason: '空串也不能抛');
    });

    test('名字里再带方括号：只吃开头那一段（正则锚定 ^）', () {
      expect(
        CollegeMapper.extractCodeAndName('[051]经济学院[南昌]'),
        ('051', '经济学院[南昌]'),
      );
    });

    test('方括号里不是数字：判为「没有 id」，整体当名字（别把 [abc] 当 id）', () {
      expect(CollegeMapper.extractCodeAndName('[abc]某学院'), ('', '[abc]某学院'));
    });

    test('名字为空：id 仍要抠出来（服务端确实有这种脏数据）', () {
      expect(CollegeMapper.extractCodeAndName('[051]'), ('051', ''));
    });
  });

  group('CollegeMapper.fromApi：接口模型 → 领域模型', () {
    test('code 走 api.code，id/name 走名字解析（两个字段各有来源，不许混）', () {
      final c = CollegeMapper().fromApi(
        const ApiCollege(code: '05', name: '[051]经济学院'),
      );
      expect(c, College('051', '经济学院', '05'));
    });

    test('fromApiList 逐条映射且保持顺序', () {
      final list = CollegeMapper().fromApiList(const [
        ApiCollege(code: '05', name: '[051]经济学院'),
        ApiCollege(code: '06', name: '[052]法学院'),
      ]);
      expect(list.map((e) => e.id).toList(), ['051', '052']);
      expect(list.map((e) => e.code).toList(), ['05', '06']);
    });
  });

  group('CollegeFilter.distinctByName：按名字去重', () {
    test('同名只留一条，顺序与其余条目不受影响', () {
      final out = CollegeFilter().distinctByName(const [
        ApiCollege(code: '05', name: '[051]经济学院'),
        ApiCollege(code: '99', name: '[051]经济学院'),
        ApiCollege(code: '06', name: '[052]法学院'),
      ]);
      expect(out.length, 2);
      expect(out.map((e) => e.name).toList(), ['[051]经济学院', '[052]法学院']);
    });

    test('空表与全同表都不炸', () {
      expect(CollegeFilter().distinctByName(const []), isEmpty);
      expect(
        CollegeFilter()
            .distinctByName(const [ApiCollege(code: 'a', name: 'X')])
            .length,
        1,
      );
    });
  });

  group('MajorMapper：与 CollegeMapper 的**两处刻意差异**', () {
    test('专业 id 允许字母（正则 [A-Za-z0-9]+），学院只允许数字', () {
      expect(
        MajorMapper.extractCodeAndName('[0701001]信息与计算科学'),
        ('0701001', '信息与计算科学'),
      );
      expect(MajorMapper.extractCodeAndName('[A1]试验班'), ('A1', '试验班'),
          reason: '专业码里出现过字母，学院码没有 —— 两者的正则刻意不同');
      expect(CollegeMapper.extractCodeAndName('[A1]试验班'), ('', '[A1]试验班'));
    });

    test('fromApi 带上年份，并把 collegeName 记为**学院的名字**（不是 id/code）', () {
      final m = MajorMapper().fromApi(
        const ApiMajor(code: '0809', name: '[0701001]信息与计算科学'),
        year: 2025,
        college: College('051', '经济学院', '05'),
      );
      expect(m.id, '0701001');
      expect(m.name, '信息与计算科学');
      expect(m.code, '0809');
      expect(m.year, 2025);
      expect(m.collegeName, '经济学院',
          reason: '培养方案按「学院名 + 专业名」定位，存 id 会导致换学年后对不上');
    });

    test('fromApiList：year / college 透传到每一条', () {
      final list = MajorMapper().fromApiList(
        const [
          ApiMajor(code: '0809', name: '[0701001]信息与计算科学'),
          ApiMajor(code: '0810', name: '[0809]计算机科学与技术'),
        ],
        year: 2025,
        college: College('051', '经济学院', '05'),
      );
      expect(list.map((e) => e.year).toSet(), {2025});
      expect(list.map((e) => e.collegeName).toSet(), {'经济学院'});
    });

    test('MajorFilter.distinctByName 与学院侧同口径', () {
      final out = MajorFilter().distinctByName(const [
        ApiMajor(code: 'a', name: '[0701001]信息与计算科学'),
        ApiMajor(code: 'b', name: '[0701001]信息与计算科学'),
        ApiMajor(code: 'c', name: '[0809]计算机科学与技术'),
      ]);
      expect(out.length, 2);
      expect(out.map((e) => e.code).toList(), ['a', 'c'],
          reason: '去重保留先出现的那条（code 用来区分是哪一条被留下）');
    });
  });

  group('域模型的相等性契约（Hive 缓存靠它判「有没有变」）', () {
    test('College：三个字段逐个参与 == 与 hashCode', () {
      expect(College('051', '经济学院', '05'), College('051', '经济学院', '05'));
      expect(College('051', '经济学院', '05').hashCode,
          College('051', '经济学院', '05').hashCode);
      expect(College('051', '经济学院', '05') == College('052', '经济学院', '05'),
          isFalse);
      expect(College('051', '经济学院', '05') == College('051', '法学院', '05'),
          isFalse);
      expect(College('051', '经济学院', '05') == College('051', '经济学院', '06'),
          isFalse, reason: 'code 变了也要算不等（服务端改过代码，缓存要跟着更新）');
    });

    test('Major：五个字段全部参与，且与 College 不互相相等', () {
      Major mk() => Major(
            id: '0701001',
            name: '信息与计算科学',
            code: '0809',
            year: 2025,
            collegeName: '经济学院',
          );
      expect(mk(), mk());
      expect(mk().hashCode, mk().hashCode);
      expect(mk() == mk(), isTrue, reason: '同样的五个字段必须互相相等');
      expect(
        mk() ==
            Major(
              id: '0701001',
              name: '信息与计算科学',
              code: '0809',
              year: 2024,
              collegeName: '经济学院',
            ),
        isFalse,
        reason: 'year 参与相等性：跨学年同名专业必须算两条',
      );
      // ⚠ 不能直接写 `mk() == College(...)`：分析器会判 `unrelated_type_equality_checks`
      //（不同类型恒假 = 套套逻辑，等于没测）。转成 Object 再比，才真的在测
      // `other is Major` 这道类型守卫。
      final Object otherType = College('0701001', '信息与计算科学', '0809');
      expect(mk() == otherType, isFalse,
          reason: '两个域模型是不同类型，别让 == 跨类型相等');
    });

    test('toString 带上足够定位的字段（排查日志用）', () {
      expect(College('051', '经济学院', '05').toString(), contains('051'));
      expect(College('051', '经济学院', '05').toString(), contains('经济学院'));
      final s = Major(
        id: '0701001',
        name: '信息与计算科学',
        code: '0809',
        year: 2025,
        collegeName: '经济学院',
      ).toString();
      expect(s, contains('2025'));
      expect(s, contains('经济学院'));
    });
  });
}
