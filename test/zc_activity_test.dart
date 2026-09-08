import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_activity.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

void main() {
  group('zcSplitExample', () {
    test('中文括号 + 反斜杠拆分', () {
      final s = zcSplitExample('志愿服务（例 敬老院\\社区）');
      expect(s.has, isTrue);
      expect(s.base, '志愿服务');
      expect(s.examples, ['敬老院', '社区']);
    });

    test('半角括号 + 正斜杠拆分', () {
      final s = zcSplitExample('学生工作(例 班委/团支书)');
      expect(s.has, isTrue);
      expect(s.base, '学生工作');
      expect(s.examples, ['班委', '团支书']);
    });

    test('多分隔符（、，；）合并拆分', () {
      final s = zcSplitExample('体育活动（例 篮球、羽毛球，拔河;长跑）');
      expect(s.examples, ['篮球', '羽毛球', '拔河', '长跑']);
    });

    test('冒号后接例的写法', () {
      final s = zcSplitExample('讲座（例：学术报告\\职业规划）');
      expect(s.base, '讲座');
      expect(s.examples, ['学术报告', '职业规划']);
    });

    test('无（例…）格式返回 has=false', () {
      final s = zcSplitExample('国家级');
      expect(s.has, isFalse);
      expect(s.base, '国家级');
    });

    test('真实样例：档位（枚举…等）去尾「等」', () {
      final s = zcSplitExample('国家级（征兵入伍/西部计划/三支一扶等）');
      expect(s.has, isTrue);
      expect(s.base, '国家级');
      expect(s.examples, ['征兵入伍', '西部计划', '三支一扶']);
    });

    test('真实样例 + catalog 分值尾缀（嵌套括号）', () {
      final s = zcSplitExample('国家级（征兵入伍/西部计划/三支一扶等）（5 分）');
      expect(s.has, isTrue);
      expect(s.base, '国家级');
      expect(s.examples, ['征兵入伍', '西部计划', '三支一扶']);
    });

    test('HTML 原稿形态（分值在括号外）', () {
      final s = zcSplitExample('国家级（征兵入伍/退役证书、西部计划、三支一扶）5 分');
      expect(s.has, isTrue);
      expect(s.base, '国家级');
      expect(s.examples, ['征兵入伍', '退役证书', '西部计划', '三支一扶']);
    });

    test('括号内单一项 + 括号外斜杠 → 不拆', () {
      final s = zcSplitExample('校级（市厅级）好人好事表扬信/入选好事月月评');
      expect(s.has, isFalse);
      expect(s.base, '校级（市厅级）好人好事表扬信/入选好事月月评');
      expect(s.examples, isEmpty);
    });

    test('例项全空视为未命中', () {
      final s = zcSplitExample('xx（例 ，、）');
      expect(s.has, isFalse);
    });
  });

  group('zcActivityItems', () {
    test('竞赛目录：含三大顶尖赛、数量充足、末项为其他', () {
      final spec = zcTypeSpecOf[ZcTypeId.contest]!;
      final items = zcActivityItems(spec);
      expect(items.length, greaterThan(140));
      final names = items.map((e) => e.title).toList();
      expect(names, contains('中国国际大学生创新大赛'));
      expect(names, contains('全国大学生数学建模竞赛'));
      expect(names, anyElement(startsWith('江西省大学生科技创新竞赛 ')));
      // 类别已回填
      expect(
        items.firstWhere((e) => e.title == '中国国际大学生创新大赛').cat,
        'c1',
      );
      final last = items.last;
      expect(last.other, isTrue);
      expect(last.title, '其他比赛（手动录入）');
    });

    test('外语：候选与证书目录一一对应且回填证书名', () {
      final spec = zcTypeSpecOf[ZcTypeId.foreign]!;
      final items = zcActivityItems(spec);
      expect(items.length, zcForeignLevels.length);
      for (var i = 0; i < items.length; i++) {
        expect(items[i].levelIdx, i);
        expect(items[i].namePrefill, zcForeignLevels[i].$1);
      }
    });

    test('优秀事迹：国家级档枚举扁平化 + 其他兜底 + 余档保留', () {
      final spec = zcTypeSpecOf[ZcTypeId.deed]!;
      final items = zcActivityItems(spec);
      // 第一档拆出 3 例 + 1 个「其他 国家级」，其余 4 档原样平铺。
      expect(items.length, 8);
      final g1 = items.where((e) => e.levelIdx == 0).toList();
      expect(g1.map((e) => e.title), containsAll(['征兵入伍', '西部计划', '三支一扶', '其他 国家级']));
      expect(
        items.firstWhere((e) => e.title == '征兵入伍').namePrefill,
        '征兵入伍',
      );
      expect(items.firstWhere((e) => e.title == '其他 国家级').other, isTrue);
      // 无枚举的档位保持原文案（含 catalog 分值尾缀）平铺。
      expect(
        items.map((e) => e.title),
        contains('校级（市厅级）好人好事表扬信/入选好事月月评（3 分）'),
      );
    });
  });
}
