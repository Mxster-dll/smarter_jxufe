import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「拆完又长回去」的棘轮守卫（2026-10-09 立）。
///
/// 由来：2026-10 那轮把 8 个巨型文件拆开之后，`public_query_screen.dart`
/// 很快又被加回 **+55 行**（1148 → 1203）。拆一次不容易，但长回去是无声的
/// —— 于是把「拆分后行数」钉在这里，**只许在允许的余量内浮动**。
///
/// 判据 = 文件总行数 ≤ 上限（= 拆分后行数 + 约 15%）。超了只有两条路：
///   ① 再拆一刀（首选）；
///   ② 确有必要就在本表上调上限，**并在下面写明理由**。
///
/// ⚠ 上限是**棘轮**：调高可以（写明理由），但请不要顺手把它改大来"过测试"。
void main() {
  /// 拆分后的基线（拆完当天**文件总行数**）→ 上限（= 基线 + 约 15%）。
  const Map<String, (int baseline, int limit)> ratchet = {
    // 1413 → 127 行壳（另 3 件：common / overview 735 / social）
    'lib/features/data_center/presentation/data_center_screen.dart': (127, 146),
    // 1336 → 57 行壳（另 4 件：support / cards / peers / pages）
    'lib/features/data_center/data/datasource/dzj_api_remote_datasource.dart': (57, 66),
    // 1179 → 893（另 1 件：electricity_widgets）
    'lib/features/electricity/presentation/electricity_screen.dart': (893, 1027),
    // 1414 → 1203（另 1 件：public_query_widgets）。⚠ 已从 1148 长回 1203 —— 正是本守卫的由来
    'lib/features/ims/public_query/presentation/public_query_screen.dart': (1203, 1383),
    // 1139 → 1084（另 1 件：rules_doc_widgets）
    'lib/features/rules/presentation/rules_reader_screen.dart': (1084, 1247),
    // 2297 → 74 行桶（另 5 件：campus / display / schedule / session / widgets）
    'lib/features/settings/presentation/widgets/settings_cards.dart': (74, 85),
    // 1061 → 222 行桶（另 3 件：values / prose / zc）
    'lib/features/fill_form/domain/fill_form_data.dart': (222, 255),
    // 1103 → 939（另 1 件：home_grid_widgets）
    'lib/features/home/presentation/home_service_grid.dart': (939, 1080),
  };

  group('拆分成果棘轮：拆过的大文件不许无声长回去', () {
    test('每个文件的当前行数都在「拆分后基线 + 约 15%」之内', () {
      final over = <String>[];
      ratchet.forEach((path, v) {
        final (baseline, limit) = v;
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path 不见了（改名/移动了？请更新本表）');
        final n = f.readAsLinesSync().length;
        if (n > limit) {
          over.add('$path：基线 $baseline 行，上限 $limit，**现在 $n 行**（+${n - baseline}）');
        }
      });
      expect(
        over,
        isEmpty,
        reason: '这些文件是 2026-10 那轮拆过的巨型文件，现在又长大了：\n${over.join('\n')}\n'
            '要么再拆一刀（首选），要么在本测试的表里上调上限并写明理由。',
      );
    });

    test('棘轮表里的文件都真的存在（防陈旧条目掩盖问题）', () {
      final missing = ratchet.keys.where((p) => !File(p).existsSync()).toList();
      expect(missing, isEmpty,
          reason: '本表指向的文件已不存在 —— 改名 / 移动 / 合并后请同步更新，'
              '否则这条守卫会变成"看着绿其实没守"');
    });

    test('上限必须大于基线（防手滑把上限调到基线以下）', () {
      final bad = ratchet.entries
          .where((e) => e.value.$2 <= e.value.$1)
          .map((e) => e.key)
          .toList();
      expect(bad, isEmpty, reason: '上限必须留出余量（当前基线 < 上限），否则等于禁止任何改动');
    });
  });
}
