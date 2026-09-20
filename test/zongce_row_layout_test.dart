import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_tip_data.dart';

/// 综测页两处版式裁定（用户 2026-09-18 二轮）的守卫：
/// 1. 基础分 / 民主评议分**各自只有一行**，标题在左、分数在最右（评议可点改）；
/// 2. 所有悬停提示的 `?` **紧跟在左端标签文字右侧**（不再被推到行尾）。
void main() {
  final src = _zcSrc();

  group('基础分 / 民主评议分 = 单行', () {
    test('基础分 / 民主评议 / 加权成绩 / 体测成绩 都用 `zcSubRow` 渲染', () {
      expect(
        RegExp(r'zcSubRow\(').allMatches(src).length,
        greaterThanOrEqualTo(9),
        reason:
            '3 基础分 + 3 民主评议 + 加权成绩 + 体测成绩 + 志愿服务时长 = 9 行单行分区',
      );
      // 标题最右端 = 胶囊：基础分只读胶囊，其余三种是可点胶囊
      expect(
        RegExp(r"trailing: zcStaticChip\(context, '60 分'\)").allMatches(src).length,
        3,
        reason: '德育/美育/劳育基础分各一行、右侧 60 分胶囊（用户 2026-09-18 三轮：显示为胶囊）',
      );
      expect(
        RegExp(r'trailing: zcTapNumber\(').allMatches(src).length,
        4,
        reason: '三处民主评议 + 体测成绩 = 4 个可点胶囊',
      );
      expect(
        RegExp(r'trailing: zcTapNumberOpt\(').allMatches(src).length,
        2,
        reason: '加权成绩 + 志愿服务时长 = 2 个可留空回自动的胶囊',
      );
      expect(src, contains("'体测成绩（0~100）'"));
      expect(src, contains("'加权成绩'"));
    });

    test('基础分胶囊是只读件（无点击、无铅笔图标），与「加分汇总」徽章同款实心胶囊', () {
      final chip = src.substring(
        src.indexOf('Widget zcStaticChip('),
        _zcBlock(src, 'Widget zcStaticChip(').length + src.indexOf('Widget zcStaticChip('),
      );
      expect(chip, isNot(contains('InkWell')));
      expect(chip, isNot(contains('edit_outlined')));
      expect(chip, contains('borderRadius: BorderRadius.circular(999)'));
      expect(chip, contains('color: AppColors.tint(context, c, 0.09),'));
      expect(
        chip,
        isNot(contains('Border.all(')),
        reason: '用户 2026-09-18 四轮：显示胶囊而不是卡片 → 不再用细描边方框',
      );
      // 可点胶囊的宽度改为自适应内容（胶囊贴合文字）
      expect(src, contains('double? width,'));
      expect(src, contains('mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,'));
    });

    test('旧的两段式（分区标题 + 独立编辑行）已删除', () {
      for (final gone in const [
        '德育基础分',
        '美育基础分',
        '劳育基础分',
        '德育民主评议分（0~20）',
        '美育民主评议分（0~20）',
        '劳育民主评议分（0~20）',
        '课程加权平均成绩',
        '体质测试成绩',
      ]) {
        expect(src, isNot(contains(gone)), reason: '$gone 应已并入单行分区');
      }
      expect(src, isNot(contains('_flatScore(')), reason: '只读分数已换成只读胶囊');
      // 用户 2026-09-18 四轮：「只有悬浮在指定区域的悬浮提示，没有另一个悬浮
      // 提示……那种卡片式的悬浮提示保留」→ 页面上不留任何纯文字 Tooltip。
      expect(
        src,
        isNot(contains('Tooltip(')),
        reason: '纯文字悬停（如「思想端正……即认定 · 自动认定」）已全部撤掉，'
            '悬停只保留标题右侧 ? 的条款卡片（RuleTip）',
      );
    });

    test('可点胶囊与「加分汇总」同款（淡底 + 999 圆角），且不带纯文字悬停', () {
      final tap = src.substring(
        src.indexOf('Widget zcValueTap('),
        src.indexOf('/// 「自动 / 手动」小标'),
      );
      expect(tap, contains('borderRadius: BorderRadius.circular(999)'));
      expect(tap, contains('color: AppColors.tint(context, accent, 0.09),'));
      expect(tap, isNot(contains('Tooltip(')));
      expect(tap, isNot(contains('Border.all(')));
      // 数值文字与徽章同色（主色 700）——字色在 `zcValueTapText` helper 里。
      // 2026-09-21 二轮：新增可选 `color` 覆盖（结果卡头部那枚总评按综合等次上色），
      // **默认档（未传 color）仍是 `muted ? outline : primary`**。
      expect(
        src,
        contains('color: color ?? (muted ? scheme.outline : scheme.primary),'),
      );
    });

    test('民主评议的分数胶囊保留「x / 20」口径', () {
      expect(
        RegExp(r"display: '\$\{zcFmt\(pingyi\)\} / 20'").allMatches(src).length,
        3,
      );
    });
  });

  group('悬停提示位置 = 左端文字右侧', () {
    test('统一走 `zcLabelTip`（文字 + 紧跟其后的 ?），行尾只剩分值/控件', () {
      expect(src, contains('Widget zcLabelTip('));
      expect(
        RegExp(r'zcLabelTip\(').allMatches(src).length,
        greaterThanOrEqualTo(7),
        reason: 'zcEditRow / zcExtraItem / zcSub / zcSubRow / zcYuCard / 结果卡 / 排名卡',
      );
      expect(
        RegExp(r'alignment: Alignment\.centerLeft').allMatches(src).length,
        greaterThanOrEqualTo(5),
      );
      // 新写法：? 的颜色取自调用方，且必须紧跟 Flexible(Text) 之后
      expect(
        src,
        contains(
          'if (tipKey != null) RuleTip(tipKey: tipKey, color: tipColor, size: 13.5),',
        ),
      );
    });

    test('旧的「? 推到行尾」写法已全部清除', () {
      for (final gone in const [
        "if (tipKey != null) RuleTip(tipKey: tipKey, size: 13.5),", // _editRow
        "RuleTip(tipKey: 'overall', size: 14),", // 结果卡
        "RuleTip(tipKey: it.\$4, size: 13),", // 排名卡行
        'Icon(Icons.help_outline, size: 15', // 排名卡头部的重复问号
      ]) {
        expect(src, isNot(contains(gone)), reason: '「$gone」应已移到左端文字右侧');
      }
    });

    test('材料行：? 紧跟材料名（不再在分值前）', () {
      expect(src, contains('m.displayName'));
      final nameBlock = src.substring(
        src.indexOf('m.displayName'),
        src.indexOf('m.displayName') + 520,
      );
      expect(nameBlock, contains('RuleTip('));
    });

    test('民主评议的条款点合并后仍有内容（合并 key 必须都能解析）', () {
      for (final key in const [
        'd-1-basic',
        'm-1-basic',
        'l-1-basic',
        'sh-d-2',
        'd-2-ping',
        'sh-m-2',
        'm-2-ping',
        'sh-l-2',
        'l-2-ping',
      ]) {
        expect(
          zcTipRefs[key],
          isNotNull,
          reason: '$key 必须在 zc_tip_data.dart 的 zcTipRefs 里',
        );
        expect(
          zcTipRefs[key]!,
          isNotEmpty,
          reason: '$key 解析出空 ids 会让 ? 按钮变成空浮层',
        );
      }
      for (final merged in const [
        "zcTipIdsOf(const ['sh-d-2', 'd-2-ping'])",
        "zcTipIdsOf(const ['sh-m-2', 'm-2-ping'])",
        "zcTipIdsOf(const ['sh-l-2', 'l-2-ping'])",
      ]) {
        expect(src, contains(merged));
      }
    });
  });
}

/// 综测页源码（2026-09-20 架构审查 ⑥：渲染工具箱已外提到 `zongce_widgets.dart`）。
///
/// 守卫改读**两文件并集** —— 原意不变（这些形态必须存在于综测页这一族里），
/// 只是不再假设它们住在同一个文件里。
String _zcSrc() => const [
  'lib/features/zongce/presentation/zongce_screen.dart',
  'lib/features/zongce/presentation/zongce_widgets.dart',
].map((p) => File(p).readAsStringSync()).join('\n');

/// 取 `sig` 开头那个顶层函数/类的**完整块**（到列 0 的 `}` 为止）——
/// 比「indexOf + 固定字符数」稳（搬迁后行数/字符数都会变，固定窗口会切进隔壁函数）。
String _zcBlock(String src, String sig) {
  final start = src.indexOf(sig);
  if (start < 0) return '';
  final end = src.indexOf('\n}', start);
  return end < 0 ? src.substring(start) : src.substring(start, end + 2);
}
