/// 「我的」页（学籍页）· 行图标与数据中心新项的守卫。
///
/// 用户 2026-09-20 二轮原话：「数据中心-基本信息里的 考生号 / 录取批次 / 录取志愿 /
/// 毕业中学 / 录取分数好像没有加入『我的』页；并且我希望，这些新添加的项，
/// 前面也要有 icon，要与现有项统一」。
///
/// 上一轮从数据中心接进来的 14 行（录取时间 / 毕业中学 / 证件类型 / 学籍状态 …）
/// 当时漏配了图标 —— 这种缺失**在页面上看不出来**（只是左边空一块），靠人眼复查必然
/// 再漏。故这里做成**源码守卫**：
/// 1. 页面每一行标签都必须在 `_iconFor` 里有分支（漏一行就红）；
/// 2. 图标表里不许留陈旧的登记项（没有对应行）；
/// 3. 用户点名的那五项既要在页面上，也要真接上 `dzj` 来源，且标签与
///    [dzjBasicFields]（数据中心「基本信息」表单列名）**逐字一致**
///    —— 差一个字就是「代码接了、界面上永远是空的」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';

const _pagePath =
    'lib/features/ims/student_info/presentation/student_info_screen.dart';

void main() {
  final src = File(_pagePath).readAsStringSync();

  /// 页面上的行标签（`_r(context, '…'` 的第一个参数）。
  Set<String> rowLabels() => RegExp(r"_r\(\s*context\s*,\s*'([^']+)'")
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();

  /// `_iconFor` 里登记了图标的标签（只在那个 switch 体内取，避免误收别处的 switch）。
  Set<String> iconLabels() {
    final body = src.split('IconData? _iconFor(String label)')[1];
    return RegExp(r"'([^']+)' => Icons\.")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
  }

  /// 某一行是不是「有标签 + 接了 dzj 来源」。
  bool wired(String label) => RegExp(
    "_r\\(context, '$label', [^)]*dzj: dzj\\['$label'\\]",
  ).hasMatch(src);

  group('行图标（用户要求「要与现有项统一」）', () {
    test('页面上每一行都有图标', () {
      final missing = rowLabels().difference(iconLabels());
      expect(
        missing,
        isEmpty,
        reason: '这些行没有 icon：${missing.join('、')}（在 _iconFor 里补一个）',
      );
    });

    test('图标表里没有陈旧登记（每个图标都有对应的行）', () {
      final stale = iconLabels().difference(rowLabels());
      expect(stale, isEmpty, reason: '这些标签已不在页面上：${stale.join('、')}');
    });

    test('上一轮漏配的那 14 行都补上了', () {
      const patched = [
        '录取时间',
        '预计毕业日期',
        '毕业中学',
        '证件类型',
        '学生身份',
        '学生类型',
        '是否预科生',
        '当前状态',
        '学籍状态',
        '银行账号',
        '所属校区',
        '家庭住址',
        '担任职务',
        '获得奖励',
      ];
      for (final label in patched) {
        expect(rowLabels(), contains(label), reason: label);
        expect(iconLabels(), contains(label), reason: label);
      }
    });
  });

  group('数据中心「基本信息」那五项（用户点名）', () {
    test('考生号 / 录取成绩 / 录取批次 / 录取志愿 / 通知书号 都在页面上且接了 dzj', () {
      for (final label in const [
        '考生号',
        '录取成绩',
        '录取批次',
        '录取志愿',
        '通知书号',
      ]) {
        expect(rowLabels(), contains(label), reason: label);
        expect(wired(label), isTrue, reason: '$label 这一行没接 dzj 来源');
      }
      // 「毕业中学」在「入学培养」卡（用户同一句里点名的第五项）
      expect(rowLabels(), contains('毕业中学'));
      expect(wired('毕业中学'), isTrue);
    });

    test('标签与数据中心字段表逐字一致（差一个字 = 界面永远空白）', () {
      final known = {for (final f in dzjBasicFields) f.label};
      for (final label in const [
        '考生号',
        '录取成绩',
        '录取批次',
        '录取志愿',
        '通知书号',
        '录取时间',
        '预计毕业日期',
        '毕业中学',
        '所属校区',
      ]) {
        expect(known, contains(label), reason: 'dzjBasicFields 里没有「$label」');
      }
    });
  });
}
