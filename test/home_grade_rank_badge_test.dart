import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/home/domain/grade_rank_badge.dart';

/// 排名胶囊格式守卫（用户 2026-09-15 裁定：`#a/b/c`，a/b/c = 班级/专业/年级）。
///
/// 历史：曾是「两行」，第二行写「专业排名 第 N 名」占高度；二轮改成卡片右上角
/// 胶囊（`1 / 3 / 9`）；三轮（本次）改成紧凑写法 `#1/3/9`。
void main() {
  test('三个排名齐全 → #班级/专业/年级', () {
    expect(
      gradeRankBadge(classRank: 1, majorRank: 3, gradeRank: 9),
      '#1/3/9',
    );
  });

  test('# 前缀与斜杠两侧都不带空格（紧凑写法）', () {
    final badge = gradeRankBadge(classRank: 7, majorRank: 12, gradeRank: 45);
    expect(badge, '#7/12/45');
    expect(badge.contains(' '), isFalse, reason: '胶囊里不该有空格');
  });

  test('取不到的排名（≤ 0）写 —', () {
    expect(gradeRankBadge(classRank: 0, majorRank: 3, gradeRank: 0), '#—/3/—');
    expect(gradeRankText(0), '—');
    expect(gradeRankText(-1), '—');
    expect(gradeRankText(2), '2');
  });

  test('tooltip 仍是完整中文含义（胶囊太短，含义只能放悬停）', () {
    expect(
      gradeRankTooltip(classRank: 1, majorRank: 3, gradeRank: 9),
      '排名（班级 / 专业 / 年级）：1 / 3 / 9',
    );
  });
}
