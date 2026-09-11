/// 分数估计 · 领域模型与估算引擎单元测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_engine.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';

/// 帮助构造分项。
GePart part({
  String name = 'p',
  GePartMode mode = GePartMode.up,
  int target = 10,
  int current = 0,
  double score = 0,
  double cap = 5,
}) => GePart(
  id: name,
  name: name,
  mode: mode,
  target: target,
  current: current,
  score: score,
  cap: cap,
);

/// 标准场景：平时 30 分 = 考勤 5（负计数全勤 16/16）+ 作业 15（15/15）
/// + 表现 10（5/10）→ 得分 25，均分 83.33，平时占比 30%。
GeCourse stdCourse({double? finalScore, double dailyPercent = 30}) => GeCourse(
  id: 'c1',
  name: '测试课',
  dailyPercent: dailyPercent,
  finalScore: finalScore,
  parts: [
    part(name: '考勤', mode: GePartMode.down, target: 16, current: 16, cap: 5),
    part(name: '作业', target: 15, current: 15, cap: 15),
    part(name: '表现', target: 10, current: 5, cap: 10),
  ],
);

void main() {
  group('分项得分率 / 得分', () {
    test('正计数：部分完成按比例，超额封顶', () {
      expect(gePartRatio(part(current: 5)), closeTo(0.5, 1e-9));
      expect(gePartRatio(part(current: 10)), closeTo(1.0, 1e-9));
      expect(gePartRatio(part(current: 12)), closeTo(1.0, 1e-9)); // 超额封顶
      expect(gePartScore(part(cap: 5, current: 10)), closeTo(5, 1e-9));
      expect(gePartScore(part(cap: 5, current: 12)), closeTo(5, 1e-9));
    });

    test('负计数：剩余/总数，扣完为 0', () {
      GePart down({int current = 0}) =>
          part(mode: GePartMode.down, target: 16, current: current, cap: 5);
      expect(gePartRatio(down(current: 16)), closeTo(1.0, 1e-9)); // 全勤
      expect(gePartRatio(down(current: 13)), closeTo(13 / 16, 1e-9)); // 缺 3
      expect(gePartRatio(down(current: 0)), closeTo(0.0, 1e-9));
      expect(gePartScore(down(current: 8)), closeTo(5 * 8 / 16, 1e-9));
    });

    test('非法 target（≤0）视为无目标满分', () {
      expect(
        gePartRatio(GePart(id: 'x', name: 'x', target: 0, current: 0)),
        closeTo(1.0, 1e-9),
      );
    });

    test('直接分数：得分 / 满分，超额封顶，得 0 即 0', () {
      GePart sc({double score = 0, int target = 100, double cap = 15}) =>
          part(mode: GePartMode.score, target: target, score: score, cap: cap);
      expect(gePartRatio(sc(score: 85)), closeTo(0.85, 1e-9));
      expect(gePartScore(sc(score: 85)), closeTo(12.75, 1e-9));
      expect(gePartRatio(sc(score: 100)), closeTo(1.0, 1e-9));
      expect(gePartRatio(sc(score: 105)), closeTo(1.0, 1e-9)); // 超额封顶
      expect(gePartScore(sc(score: 105)), closeTo(15, 1e-9));
      expect(gePartRatio(sc(score: 0)), closeTo(0.0, 1e-9));
      // 满分 = 分值上限 → 直接填得分（8/10 分 → 8 分）
      expect(gePartScore(sc(score: 8, target: 10, cap: 10)), closeTo(8, 1e-9));
      // 小数得分
      expect(gePartScore(sc(score: 85.5)), closeTo(0.855 * 15, 1e-9));
    });
  });

  group('课程测算', () {
    test('分值合计 / 得分合计 / 平时均分 / 平时折算', () {
      final calc = geCalc(stdCourse());
      expect(calc.capSum, closeTo(30, 1e-9));
      expect(calc.scoreSum, closeTo(25, 1e-9));
      expect(calc.dailyMean, closeTo(25 / 30 * 100, 1e-9));
      // 折算 = 均分 × 30%：25/30×30 = 25 分（口径自洽）
      expect(calc.dailyContrib, closeTo(25, 1e-9));
    });

    test('总评 = 平时折算 + 期末 × 期末占比', () {
      final calc = geCalc(stdCourse());
      expect(calc.finalWeight, closeTo(0.7, 1e-9));
      expect(calc.finalContrib(80), closeTo(56, 1e-9));
      expect(geTotalWithFinal(calc, 80), closeTo(81, 1e-9));
      expect(geTotalWithFinal(calc, null), isNull);
      // 期末输入越界按 100 封顶
      expect(geTotalWithFinal(calc, 150), closeTo(95, 1e-9));
    });

    test('期末未填：总评区间 = 平时折算 ~ +期末满分', () {
      final calc = geCalc(stdCourse());
      final (lo, hi) = geTotalRange(calc);
      expect(lo, closeTo(25, 1e-9));
      expect(hi, closeTo(95, 1e-9));
    });

    test('正计分分项剩余可补：均分上限与折算上限', () {
      final calc = geCalc(stdCourse());
      // 表现 5/10 还可补 5 分 → 均分 +5/30×100
      expect(calc.gainableCap, closeTo(5, 1e-9));
      expect(calc.meanCeiling, closeTo(25 / 30 * 100 + 5 / 30 * 100, 1e-9));
      expect(calc.dailyCeiling, closeTo(30, 1e-9)); // 折算满点 30
    });

    test('负计数损失不可回补：全扣完的均分上限不回升', () {
      final c = GeCourse(
        id: 'c',
        name: 'c',
        dailyPercent: 20,
        parts: [
          part(
            name: '考勤',
            mode: GePartMode.down,
            target: 16,
            current: 0, // 全扣光
            cap: 20,
          ),
        ],
      );
      final calc = geCalc(c);
      expect(calc.scoreSum, closeTo(0, 1e-9));
      expect(calc.meanCeiling, closeTo(0, 1e-9));
      expect(calc.dailyCeiling, closeTo(0, 1e-9));
    });

    test('三种计分方式混用：得分合计 / 可达上限（直接分数项算可补）', () {
      final c = GeCourse(
        id: 'mix',
        name: '混合',
        dailyPercent: 40,
        finalScore: 90,
        parts: [
          // 考勤：负计数 14/16 → 4.375/5（已扣减，不可回补）
          part(
            name: '考勤',
            mode: GePartMode.down,
            target: 16,
            current: 14,
            cap: 5,
          ),
          // 作业：正计数 8/10 → 8/10（还差 2 分可补）
          part(name: '作业', target: 10, current: 8, cap: 10),
          // 期中：直接分数 90/100 → 13.5/15（还差 1.5 分可补）
          part(
            name: '期中',
            mode: GePartMode.score,
            target: 100,
            score: 90,
            cap: 15,
          ),
        ],
      );
      final calc = geCalc(c);
      expect(calc.capSum, closeTo(30, 1e-9));
      expect(calc.scoreSum, closeTo(25.875, 1e-9));
      expect(calc.dailyMean, closeTo(86.25, 1e-9));
      expect(calc.dailyContrib, closeTo(34.5, 1e-9)); // 86.25 × 40%
      expect(calc.gainableCap, closeTo(3.5, 1e-9)); // 作业 2 + 期中 1.5
      expect(geTotalWithFinal(calc, 90), closeTo(34.5 + 54, 1e-9));
    });

    test('无分项课程全 0', () {
      final calc = geCalc(const GeCourse(id: 'e', name: '空'));
      expect(calc.capSum, 0);
      expect(calc.dailyMean, 0);
      expect(calc.dailyContrib, 0);
      expect(geTotalWithFinal(calc, 90), closeTo(90 * 0.7, 1e-9));
    });
  });

  group('目标反推', () {
    test('期末占比内可达：返回所需期末分', () {
      final need = geRequiredFinal(geCalc(stdCourse()), 60);
      expect(need.status, GeGoalStatus.ok);
      expect(need.requiredFinal, closeTo((60 - 25) / 0.7, 1e-9)); // 50
    });

    test('平时折算已达标 → reached（期末只需保底）', () {
      final calc = geCalc(stdCourse());
      expect(geRequiredFinal(calc, 25).status, GeGoalStatus.reached);
      expect(geRequiredFinal(calc, 20).status, GeGoalStatus.reached);
    });

    test('期末 100 分恰好够 → ok 边界', () {
      final need = geRequiredFinal(geCalc(stdCourse()), 95);
      expect(need.status, GeGoalStatus.ok);
      expect(need.requiredFinal, closeTo(100, 1e-9));
    });

    test('期末满分仍差 → 平时剩余分项可补（recoverByDaily）', () {
      final need = geRequiredFinal(geCalc(stdCourse()), 96);
      expect(need.status, GeGoalStatus.recoverByDaily);
      expect(need.dailyGap, closeTo(1, 1e-9)); // 96 − (25+70)
    });

    test('直接分数项未拿满 → 计入可补空间（recoverByDaily）', () {
      // 平时 40%：考勤 14/16 → 4.375、期中 90/100 → 18（满分 25）
      // → 均分 89.5、折算 35.8
      final c = GeCourse(
        id: 'mix',
        name: '混合',
        dailyPercent: 40,
        parts: [
          part(
            name: '考勤',
            mode: GePartMode.down,
            target: 16,
            current: 14,
            cap: 5,
          ),
          part(
            name: '期中',
            mode: GePartMode.score,
            target: 100,
            score: 90,
            cap: 20,
          ),
        ],
      );
      final calc = geCalc(c);
      expect(calc.scoreSum, closeTo(22.375, 1e-9));
      expect(calc.dailyContrib, closeTo(35.8, 1e-9));
      expect(calc.gainableCap, closeTo(2, 1e-9)); // 期中 (1−0.9)×20
      // 期末满分 100 → 最高 35.8 + 60 = 95.8，目标 96 需靠平时补 0.2
      final need = geRequiredFinal(calc, 96);
      expect(need.status, GeGoalStatus.recoverByDaily);
      expect(need.dailyGap, closeTo(0.2, 1e-9));
    });

    test('期末满分且无剩余分项可补 → impossible，给全局上限', () {
      final c = GeCourse(
        id: 'c',
        name: 'c',
        dailyPercent: 20,
        parts: [
          // 考勤已损失一半：8/16 → 10 分；无正计数分项可补
          part(
            name: '考勤',
            mode: GePartMode.down,
            target: 16,
            current: 8,
            cap: 20,
          ),
        ],
      );
      final calc = geCalc(c);
      expect(calc.gainableCap, closeTo(0, 1e-9));
      final need = geRequiredFinal(calc, 95);
      expect(need.status, GeGoalStatus.impossible);
      expect(need.maxTotal, closeTo(10 + 80, 1e-9)); // 折算 10 + 期末 80
    });

    test('期末不占比例（平时 100%）按纯平时课判定', () {
      // 负计数损失不可回补：已得 75/100（剩 3/4），平时 100% → 折算 75
      final c = GeCourse(
        id: 'c',
        name: 'c',
        dailyPercent: 100,
        parts: [
          part(
            name: '扣分项',
            mode: GePartMode.down,
            target: 4,
            current: 3,
            cap: 100,
          ),
        ],
      );
      final calc = geCalc(c);
      expect(calc.gainableCap, closeTo(0, 1e-9)); // 负计数不可补
      expect(calc.dailyContrib, closeTo(75, 1e-9));
      expect(geRequiredFinal(calc, 60).status, GeGoalStatus.reached);
      // 75 → 90 缺 15，且无剩余可补 → impossible
      final need = geRequiredFinal(calc, 90);
      expect(need.status, GeGoalStatus.impossible);
      expect(need.maxTotal, closeTo(75, 1e-9));
      // 正计数剩余可补时 → recoverByDaily（缺口 15 ≤ 可补 25）
      final c2 = GeCourse(
        id: 'c2',
        name: 'c2',
        dailyPercent: 100,
        parts: [
          part(
            name: '打卡',
            mode: GePartMode.up,
            target: 20,
            current: 10,
            cap: 50,
          ),
          part(
            name: '全勤',
            mode: GePartMode.up,
            target: 10,
            current: 10,
            cap: 50,
          ),
        ],
      );
      final calc2 = geCalc(c2);
      expect(calc2.dailyContrib, closeTo(75, 1e-9)); // 25+50
      final need2 = geRequiredFinal(calc2, 90);
      expect(need2.status, GeGoalStatus.recoverByDaily);
      expect(need2.dailyGap, closeTo(15, 1e-9));
      // 目标 100 = 缺口 25 = 可补上限 25 → 边界算可补
      expect(geRequiredFinal(calc2, 100).status, GeGoalStatus.recoverByDaily);
    });
  });

  group('学分加权平均与逐课贡献', () {
    test('两课加权：平均 = Σ分数×学分/Σ学分，贡献之和 = 平均', () {
      final summary = geWeightedSummary(const [
        GeWeightItem(name: '高数', score: 90, credits: 3, fromGrades: true),
        GeWeightItem(name: '英语', score: 80, credits: 2),
      ]);
      expect(summary.count, 2);
      expect(summary.totalCredits, closeTo(5, 1e-9));
      expect(summary.average, closeTo(86, 1e-9));
      final c1 = summary.contribution(
        const GeWeightItem(name: '高数', score: 90, credits: 3),
      );
      final c2 = summary.contribution(
        const GeWeightItem(name: '英语', score: 80, credits: 2),
      );
      expect(c1, closeTo(54, 1e-9));
      expect(c2, closeTo(32, 1e-9));
      expect(c1 + c2, closeTo(summary.average!, 1e-9));
      // 来源分账：教务已出成绩 1 门 3 学分、估计 1 门 2 学分。
      expect(summary.gradesCount, 1);
      expect(summary.gradesCredits, closeTo(3, 1e-9));
      expect(summary.estimateCount, 1);
      expect(summary.estimateCredits, closeTo(2, 1e-9));
    });

    test('学分为 0 的课不参与合计；分数越界按 0~100 截断', () {
      final summary = geWeightedSummary(const [
        GeWeightItem(name: 'a', score: 100, credits: 0), // 不参与
        GeWeightItem(name: 'b', score: 120, credits: 1), // → 100
        GeWeightItem(name: 'c', score: -5, credits: 1), // → 0
      ]);
      expect(summary.count, 2);
      expect(summary.totalCredits, closeTo(2, 1e-9));
      expect(summary.average, closeTo(50, 1e-9));
    });

    test('无有效项时平均为 null（未填期末的课不计入）', () {
      final summary = geWeightedSummary(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.average, isNull);
      expect(summary.contribution(const GeWeightItem(name: 'x', score: 90)), 0);
    });
  });

  group('加权参与项合并（教务已出成绩 + 本模块估计）', () {
    test('教务成绩全量计入；同名课不重复；未填期末 / 学分 0 不计入', () {
      final items = geMergeWeightItems(
        priorItems: const [
          GeWeightItem(name: '高数', score: 93, credits: 4, fromGrades: true),
          GeWeightItem(name: '英语', score: 85, credits: 2, fromGrades: true),
        ],
        courses: const [
          // 与教务同名 → 跳过（用真实 93 分，而不是估计的 70 分）
          GeCourse(id: '1', name: '高数', credits: 4, finalScore: 70),
          // 已填期末 → 按估计总评计入（平时占比 0 的纯期末课：总评 = 期末分）
          GeCourse(
            id: '2',
            name: '数据结构',
            credits: 3,
            dailyPercent: 0,
            finalScore: 88,
          ),
          // 未填期末 → 不计入
          GeCourse(id: '3', name: '操作系统', credits: 3),
          // 学分为 0 → 不计入
          GeCourse(id: '4', name: '体育', credits: 0, finalScore: 90),
        ],
      );
      expect(items.length, 3);
      expect(items.first.name, '高数');
      expect(items.first.fromGrades, isTrue);
      expect(items.first.score, 93);

      final summary = geWeightedSummary(items);
      expect(summary.count, 3);
      expect(summary.gradesCount, 2);
      expect(summary.gradesCredits, closeTo(6, 1e-9));
      expect(summary.estimateCount, 1);
      expect(summary.estimateCredits, closeTo(3, 1e-9));
      expect(summary.totalCredits, closeTo(9, 1e-9));
      expect(summary.average, closeTo((93 * 4 + 85 * 2 + 88 * 3) / 9, 1e-9));
    });
  });

  group('模型 JSON 往返与容错', () {
    test('课程 + 分项 JSON 往返保持语义', () {
      final c = stdCourse(finalScore: 81.5);
      final restored = GeCourse.fromJson(c.toJson());
      expect(restored.id, c.id);
      expect(restored.name, c.name);
      expect(restored.dailyPercent, c.dailyPercent);
      expect(restored.credits, c.credits);
      expect(restored.finalScore, 81.5);
      expect(restored.parts.length, 3);
      expect(restored.parts[0].mode, GePartMode.down);
      expect(restored.parts[0].target, 16);
      expect(restored.parts[0].current, 16);
      expect(restored.parts[2].cap, closeTo(10, 1e-9));
    });

    test('损坏/缺省字段容错', () {
      final p = GePart.fromJson(const {});
      expect(p.target, 1);
      expect(p.current, 0);
      expect(p.mode, GePartMode.up);
      expect(p.cap, 0);

      final c = GeCourse.fromJson(const {
        'parts': [
          {'id': 'x', 'name': 'x', 'target': 0, 'current': -5, 'cap': -2},
        ],
      });
      expect(c.name, '');
      expect(c.dailyPercent, 30);
      expect(c.credits, 1); // 旧数据无 credits → 默认 1 学分
      expect(c.parts.single.target, 1); // target <1 → 1
      expect(c.parts.single.current, 0); // current clamp
      expect(c.parts.single.cap, 0); // cap clamp
      expect(c.finalScore, isNull);
    });

    test('copyWith 可清除期末分', () {
      final c = stdCourse(finalScore: 80);
      expect(c.copyWith(clearFinalScore: true).finalScore, isNull);
      expect(c.copyWith(finalScore: 90).finalScore, 90);
    });

    test('直接分数分项：往返保留分数，旧数据/负值容错', () {
      final p = part(mode: GePartMode.score, target: 100, score: 85.5, cap: 15);
      final restored = GePart.fromJson(p.toJson());
      expect(restored.mode, GePartMode.score);
      expect(restored.target, 100);
      expect(restored.score, closeTo(85.5, 1e-9));
      expect(restored.cap, closeTo(15, 1e-9));
      expect(p.copyWith(score: 90).score, closeTo(90, 1e-9));

      // 旧数据无 score 字段 → 0（计数型分项不受影响）
      final legacy = GePart.fromJson(const {'id': 'x', 'name': 'x'});
      expect(legacy.score, 0);
      expect(legacy.mode, GePartMode.up);
      // 负数得分 → clamp 到 0
      final bad = GePart.fromJson(const {
        'id': 'x',
        'name': 'x',
        'mode': 'score',
        'score': -5,
      });
      expect(bad.mode, GePartMode.score);
      expect(bad.score, 0);
    });
  });
}
