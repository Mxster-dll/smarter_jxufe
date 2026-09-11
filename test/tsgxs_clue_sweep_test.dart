import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_clue_sweep.dart';

void main() {
  group('TsgxsClueSweepResult', () {
    test('已学完(无需补全)算放行,结论说明不必补全', () {
      const r = TsgxsClueSweepResult(
        total: 4,
        fetched: 0,
        alreadyLearned: true,
        verified: true,
        verifyAttempts: 0,
      );
      expect(r.ok, isTrue);
      expect(r.summary, contains('无需补全'));
    });

    test('补全后复核通过 = 放行,结论带 已打开/总数', () {
      const r = TsgxsClueSweepResult(
        total: 4,
        fetched: 4,
        alreadyLearned: false,
        verified: true,
        verifyAttempts: 2,
      );
      expect(r.ok, isTrue);
      expect(r.summary, contains('4/4'));
      expect(r.summary, contains('放行'));
    });

    test('全部打开但服务端仍不放行 = 未放行,结论如实报告复核次数', () {
      const r = TsgxsClueSweepResult(
        total: 4,
        fetched: 4,
        alreadyLearned: false,
        verified: false,
        verifyAttempts: 3,
      );
      expect(r.ok, isFalse);
      expect(r.summary, contains('4/4'));
      expect(r.summary, contains('3'));
      expect(r.summary, contains('未放行'));
    });

    test('补全线索的停留时长固定为 0.2 秒(用户拍板 2026-09-11)', () {
      expect(tsgxsClueSweepDwell, const Duration(milliseconds: 200));
      expect(tsgxsClueSweepDwellText, '0.2 秒');
      expect(tsgxsClueSweepVerifyAttempts, 3);
    });
  });
}
