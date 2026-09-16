/// 经典阅读「实际口径 = 畅想之星个人计数」的口径守卫。
///
/// 背景（用户 2026-09-14 拍板）：蛟湖阅读「经典阅读」进度卡的**实际**值改为取
/// 畅想之星平台自身的个人计数（App 内实时），学分平台明细降为**平台（远端）**那一条。
/// 只采信个人会话——校园网 IP 免密是全校公用账号（实测 2160 册 vs 个人 13 册）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_progress.dart';

ReadCreditDetail _classicDetail(List<List<String>> rows) => ReadCreditDetail(
  kind: ReadCreditKind.classic,
  headers: const ['已读完图书书名', '完成时间', '总阅读时长(秒)', '所属厂商'],
  rows: rows,
);

ReadCreditScore _score({bool? passed}) => ReadCreditScore(
  items: [
    ReadCreditItem(
      kind: ReadCreditKind.classic,
      statusText: passed == true ? '通过' : '未通过',
      passed: passed,
      updatedAt: '2026年09月03日',
    ),
  ],
);

void main() {
  test('有畅想之星个人计数时，实际口径取它、明细降为平台那一条', () {
    final bundle = buildReadCreditProgress(
      score: _score(passed: false),
      details: {
        ReadCreditKind.classic: _classicDetail([
          ['书A', '2026-09-01', '7201', '学习通'],
          ['书B', '2026-09-02', '7201', '学习通'],
        ]),
      },
      cxstar: (books: 13, minutes: 1337),
    );
    final part = bundle.partOf(ReadCreditKind.classic)!;
    expect(part.bars[0].label, '已读册数');
    expect(part.bars[0].actualText, '13 / 10 册');
    expect(part.bars[0].actualReached, isTrue);
    // 学分平台明细成为「平台（远端）」那条。
    expect(part.bars[0].remoteText, '2 / 10 册');
    expect(part.bars[0].actualNote, '畅想之星平台个人计数（App 内实时）');
    // 1337 分钟 = 22.28 小时 → 已过 20 小时线。
    expect(part.bars[1].actualText, '22.3 / 20 小时');
    expect(part.bars[1].actualReached, isTrue);
    expect(part.actualMet, isTrue);
    expect(part.actualSourceNote, contains('畅想之星'));
    expect(part.lines.first, contains('畅想之星平台（个人）'));
    expect(part.lines.first, contains('13 册'));
    expect(readCreditPartCompleted(part), isTrue);
  });

  test('没有畅想之星数据时回退学分平台明细（旧行为不变）', () {
    final bundle = buildReadCreditProgress(
      score: _score(passed: false),
      details: {
        ReadCreditKind.classic: _classicDetail([
          ['书A', '2026-09-01', '7201', '学习通'],
          ['书B', '2026-09-02', '7201', '学习通'],
        ]),
      },
    );
    final part = bundle.partOf(ReadCreditKind.classic)!;
    expect(part.bars[0].actualText, '2 / 10 册');
    expect(part.bars[1].actualText, '4 / 20 小时');
    expect(part.bars[0].remote, isNull);
    expect(part.actualMet, isFalse);
    expect(part.actualSourceNote, contains('名著明细'));
  });

  test('畅想之星只有册数、时长为 0 时，时长那一条不达标', () {
    final bundle = buildReadCreditProgress(
      score: null,
      details: const {},
      cxstar: (books: 13, minutes: 0),
    );
    final part = bundle.partOf(ReadCreditKind.classic)!;
    expect(part.bars[0].actualText, '13 / 10 册');
    expect(part.bars[1].actualText, '0 / 20 小时');
    expect(part.actualMet, isFalse);
  });

  test('两边都没有时不给实际口径（actualMet 为 null，交给平台状态）', () {
    final bundle = buildReadCreditProgress(
      score: _score(passed: true),
      details: const {},
    );
    final part = bundle.partOf(ReadCreditKind.classic)!;
    expect(part.actualMet, isNull);
    expect(part.remoteMet, isTrue);
    expect(part.lines, ['暂未取到实时计数']);
    expect(readCreditPartCompleted(part), isTrue);
  });
}
