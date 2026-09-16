import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/read_credit/data/providers/read_credit_providers.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_progress.dart';
import 'package:smarter_jxufe/features/read_credit/presentation/read_credit_progress_section.dart';

ReadCreditItem _item(
  ReadCreditKind kind, {
  bool? passed,
  List<ReadCreditCount> counts = const [],
  String updatedAt = '2026年09月03日',
}) => ReadCreditItem(
  kind: kind,
  statusText: passed == true ? '通过' : (passed == false ? '未通过' : ''),
  passed: passed,
  updatedAt: updatedAt,
  infoRaw: counts.isEmpty ? null : counts.map((c) => c.toString()).join(' '),
  counts: counts,
);

ReadCreditDetail _detail(
  ReadCreditKind kind,
  List<String> headers,
  List<List<String>> rows,
) => ReadCreditDetail(kind: kind, headers: headers, rows: rows);

/// 普通阅读明细：厂商含「纸质」= 纸质借阅，其余算电子阅读。
ReadCreditDetail _ordinaryDetail({
  required int electronic,
  required int paper,
}) => _detail(
  ReadCreditKind.ordinary,
  ['姓名', '已读完图书书名', '完成时间', '总阅读时长(秒)', '所属厂商'],
  [
    for (var i = 0; i < electronic; i++)
      ['某同学', '电子书$i', '2026-09-01', '7201', '京东阅读'],
    for (var i = 0; i < paper; i++) ['某同学', '纸质书$i', '2026-09-01', '0', '纸质借阅'],
  ],
);

void main() {
  group('readCreditNum', () {
    test('整数不带小数位，非整数保留 1 位', () {
      expect(readCreditNum(20), '20');
      expect(readCreditNum(4.5), '4.5');
      expect(readCreditNum(4.0006), '4');
      expect(readCreditNum(0.333), '0.3');
    });
  });

  group('第一部分 · 经典阅读', () {
    test('按明细实时统计册数与时长，两条进度条，平台不提供计数', () {
      final detail = _detail(
        ReadCreditKind.classic,
        ['已读完图书书名', '完成时间', '总阅读时长(秒)', '所属厂商'],
        [
          ['书A', '2026-09-01', '7201', '学习通'],
          ['书B', '2026-09-02', '7201', '学习通'],
        ],
      );
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [_item(ReadCreditKind.classic, passed: false)],
        ),
        details: {ReadCreditKind.classic: detail},
      );
      final part = bundle.partOf(ReadCreditKind.classic)!;
      expect(part.bars.length, 2);
      expect(part.bars[0].label, '已读册数');
      expect(part.bars[0].actualText, '2 / 10 册');
      expect(part.bars[0].remote, isNull);
      expect(part.bars[0].actualReached, isFalse);
      expect(part.bars[1].label, '阅读总时长');
      expect(part.bars[1].actualText, '4 / 20 小时');
      expect(part.actualMet, isFalse);
      expect(part.remoteMet, isFalse);
      expect(part.remoteStatusText, '未通过 · 更新于 2026年09月03日');
    });

    test('册数与时长都达标时实际口径达标', () {
      final detail = _detail(
        ReadCreditKind.classic,
        ['已读完图书书名', '总阅读时长(秒)'],
        [
          for (var i = 0; i < 10; i++) ['书$i', '8000'],
        ],
      );
      final bundle = buildReadCreditProgress(
        score: null,
        details: {ReadCreditKind.classic: detail},
      );
      final part = bundle.partOf(ReadCreditKind.classic)!;
      expect(part.bars[1].actualText, '22.2 / 20 小时');
      expect(part.actualMet, isTrue);
      expect(part.remoteMet, isNull);
      expect(part.remoteStatusText, '平台未返回该项');
      expect(bundle.actualMetCount, 1);
    });
  });

  group('第二部分 · 普通阅读', () {
    test('纸质取数据中心本年借阅，电子取明细，平台侧给汇总计数', () {
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [
            _item(
              ReadCreditKind.ordinary,
              passed: false,
              counts: const [
                ReadCreditCount('电子阅读', 2),
                ReadCreditCount('纸质阅读', 0),
              ],
            ),
          ],
        ),
        details: {
          ReadCreditKind.ordinary: _ordinaryDetail(electronic: 2, paper: 1),
        },
        borrowCounts: const {'本年': 5},
      );
      final part = bundle.partOf(ReadCreditKind.ordinary)!;
      final bar = part.bars.single;
      expect(bar.label, '累计册数');
      expect(bar.actualText, '7 / 10 册');
      expect(bar.remoteText, '2 / 10 册');
      expect(bar.actualReached, isFalse);
      expect(part.actualMet, isFalse);
      expect(bar.actualNote, contains('数据中心 · 本年'));
      expect(part.lines.length, 2);
      expect(part.lines[0], contains('实际 2 册'));
      expect(part.lines[0], contains('平台 2 册'));
      expect(part.lines[1], contains('数据中心 · 本年借阅'));
    });

    test('数据中心不可用时回退明细里的纸质行', () {
      final bundle = buildReadCreditProgress(
        score: null,
        details: {
          ReadCreditKind.ordinary: _ordinaryDetail(electronic: 8, paper: 2),
        },
      );
      final part = bundle.partOf(ReadCreditKind.ordinary)!;
      expect(part.bars.single.actualText, '10 / 10 册');
      expect(part.bars.single.remote, isNull);
      expect(part.bars.single.actualReached, isTrue);
      expect(part.actualMet, isTrue);
      expect(part.lines[1], contains('明细表口径'));
    });
  });

  group('第三部分 · 入馆教育', () {
    test('实际口径 = App 五章闯关实时进度，平台侧另记一跳记录', () {
      final detail = _detail(
        ReadCreditKind.libraryEdu,
        ['闯关结束时间', '是否通过', '所属厂商'],
        [
          ['2026/7/1 15:29:33', '是', '入馆教育'],
        ],
      );
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [_item(ReadCreditKind.libraryEdu, passed: false)],
        ),
        details: {ReadCreditKind.libraryEdu: detail},
        libraryEdu: (passed: 5, total: 5),
      );
      final part = bundle.partOf(ReadCreditKind.libraryEdu)!;
      expect(part.bars.single.actualText, '5 / 5 章');
      expect(part.bars.single.actualReached, isTrue);
      expect(part.actualMet, isTrue);
      expect(part.remoteMet, isFalse);
      expect(part.lines.single, contains('最近结果「是」'));
      expect(part.lines.single, contains('2026/7/1 15:29:33'));
    });

    test('实时进度不可用（会话/网络）时不给实际值，并说明原因', () {
      final bundle = buildReadCreditProgress(
        score: null,
        details: const {},
        libraryEdu: null,
      );
      final part = bundle.partOf(ReadCreditKind.libraryEdu)!;
      expect(part.bars, isEmpty);
      expect(part.actualMet, isNull);
      // 措辞含「未按未通过计」：取不到状态 ≠ 未通过（否则一次网络抖动
      // 就会把整项显示成未完成）。
      expect(part.actualSourceNote, contains('未按未通过计'));
      expect(part.lines.single, contains('暂无'));
    });

    test('部分章节通过时给出分数进度', () {
      final bundle = buildReadCreditProgress(
        score: null,
        details: const {},
        libraryEdu: (passed: 2, total: 5),
      );
      final part = bundle.partOf(ReadCreditKind.libraryEdu)!;
      expect(part.bars.single.actualText, '2 / 5 章');
      expect(part.actualMet, isFalse);
    });
  });

  group('第四部分 · 信息素养', () {
    test('视频数量求和，另给累计时长', () {
      final detail = _detail(
        ReadCreditKind.infoLiteracy,
        ['学习视频数量', '时长(秒)', '完成时间'],
        [
          for (var i = 0; i < 20; i++) ['1', '60', '2026-09-01'],
        ],
      );
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [_item(ReadCreditKind.infoLiteracy, passed: false)],
        ),
        details: {ReadCreditKind.infoLiteracy: detail},
      );
      final part = bundle.partOf(ReadCreditKind.infoLiteracy)!;
      expect(part.bars.single.actualText, '20 / 20 个');
      expect(part.bars.single.actualReached, isTrue);
      expect(part.actualMet, isTrue);
      expect(part.lines.single, '累计学习时长：0.3 小时');
    });
  });

  group('蛟湖文化活动与整体计数', () {
    test('无量化要求不给进度条，只跟平台状态', () {
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [_item(ReadCreditKind.culture, passed: true)],
        ),
      );
      final part = bundle.partOf(ReadCreditKind.culture)!;
      expect(part.bars, isEmpty);
      expect(part.actualMet, isNull);
      expect(part.remoteMet, isTrue);
      expect(part.requirementText, contains('无量化要求'));
    });

    test('平台整体不可用时仍出全部五部分（实际口径照常）', () {
      final bundle = buildReadCreditProgress(
        score: null,
        details: {
          ReadCreditKind.classic: _detail(
            ReadCreditKind.classic,
            ['已读完图书书名', '总阅读时长(秒)'],
            [
              for (var i = 0; i < 10; i++) ['书$i', '8000'],
            ],
          ),
        },
        libraryEdu: (passed: 5, total: 5),
        borrowCounts: const {'本年': 10},
      );
      expect(bundle.partCount, 5);
      expect(bundle.remoteMetCount, 0);
      expect(bundle.actualMetCount, 3, reason: '经典阅读 + 入馆教育 + 普通阅读(借阅 10 册)');
      for (final part in bundle.parts) {
        expect(part.remoteStatusText, '平台未返回该项');
      }
    });
  });

  group('进度区渲染', () {
    testWidgets('两档口径都出现，且无布局异常', (tester) async {
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          items: [
            _item(
              ReadCreditKind.ordinary,
              passed: false,
              counts: const [
                ReadCreditCount('电子阅读', 2),
                ReadCreditCount('纸质阅读', 0),
              ],
            ),
            _item(ReadCreditKind.classic, passed: false),
            _item(ReadCreditKind.libraryEdu, passed: false),
            _item(ReadCreditKind.culture, passed: true),
          ],
        ),
        details: {
          ReadCreditKind.classic: _detail(
            ReadCreditKind.classic,
            ['已读完图书书名', '总阅读时长(秒)'],
            [
              ['书A', '7201'],
              ['书B', '7201'],
            ],
          ),
          ReadCreditKind.ordinary: _ordinaryDetail(electronic: 2, paper: 1),
          ReadCreditKind.infoLiteracy: _detail(
            ReadCreditKind.infoLiteracy,
            ['学习视频数量', '时长(秒)'],
            [
              for (var i = 0; i < 3; i++) ['1', '60'],
            ],
          ),
        },
        libraryEdu: (passed: 5, total: 5),
        borrowCounts: const {'本年': 5},
      );

      var openedEdu = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [readCreditProgressProvider.overrideWith((ref) => bundle)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReadCreditProgressSection(
                  onOpenLibraryEdu: () => openedEdu = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 总成绩卡：四段圆环 + 学分胶囊 + 四部分图例。
      expect(find.text('阅读学分'), findsOneWidget);
      expect(find.text('未获得学分'), findsOneWidget);
      // 只有入馆教育 5/5 章完成：经典阅读 2 册 / 4 小时、普通阅读 7 册、
      // 信息素养 3 个视频都还差。
      expect(find.text('1/4'), findsOneWidget);
      expect(find.text('部分已完成'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('未完成'), findsNWidgets(3));
      // 四个部分各一张卡（用户裁定：不允许同一部分出现多张卡）——
      // 用卡片类型计数 + 各卡独有的计量要求文案断言，避开总卡图例里的同名文字。
      expect(find.byType(ReadCreditPartCard), findsNWidgets(4));
      for (final requirement in [
        '经典电子阅读 10 册 + 阅读总时长 ≥ 20 小时',
        '纸质借阅 + 电子阅读累计 ≥ 10 册',
        '通过入馆教育平台测试（五章闯关）',
        '信息素养平台在线视频学习 ≥ 20 个',
      ]) {
        expect(find.text(requirement), findsOneWidget);
      }
      expect(find.text('实际 已达标'), findsOneWidget);
      // 服务端侧有状态的 3 项未通过；信息素养服务端未返回该项 → 「服务端 未提供」。
      expect(find.text('服务端 未通过'), findsNWidgets(3));
      expect(find.text('服务端 未提供'), findsOneWidget);
      // 蛟湖文化活动并进总卡，只出一个状态胶囊。
      expect(find.text('通过'), findsOneWidget);
      // 一条进度条上叠两档：灰 = 实际、红 = 服务端，两档数值都在同一行。
      expect(find.textContaining('实际 7 / 10 册'), findsOneWidget);
      expect(find.text('服务端 2 / 10 册'), findsOneWidget);
      expect(find.textContaining('实际 5 / 5 章'), findsOneWidget);
      expect(find.textContaining('更新于 2026年09月03日'), findsWidgets);
      expect(tester.takeException(), isNull);

      // 点「入馆教育」卡 = 回调（页面注入 → 原新生入馆教育页）。
      // 卡片在长页里位于视口下方，先滚到可见再点，否则命中测试落空；
      // 总卡图例里也有「入馆教育」字样，故按卡片内部定位。
      final eduTitle = find.descendant(
        of: find.byType(ReadCreditPartCard),
        matching: find.text('入馆教育'),
      );
      await tester.ensureVisible(eduTitle);
      await tester.pumpAndSettle();
      await tester.tap(eduTitle);
      await tester.pump();
      expect(openedEdu, isTrue);
    });

    testWidgets('服务端已标记完成 → 红条拉满并显示「服务端 已完成」', (tester) async {
      const part = ReadCreditPartProgress(
        kind: ReadCreditKind.classic,
        requirementText: '经典电子阅读 10 册 + 阅读总时长 ≥ 20 小时',
        bars: [
          ReadCreditProgressBar(
            label: '已读册数',
            actual: 3,
            remote: 2,
            target: 10,
            unit: '册',
          ),
        ],
        actualMet: false,
        remoteMet: true,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReadCreditPartCard(part: part)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('实际 3 / 10 册'), findsOneWidget);
      expect(find.text('服务端 已完成'), findsOneWidget);
      expect(find.textContaining('服务端 2 / 10 册'), findsNothing);
      expect(tester.takeException(), isNull);

      // 条形尺寸：轨道与红条同宽（红条 100%），浅红（实际 3/10）更短。
      final widths = <double>[];
      for (final element in find.byType(Container).evaluate()) {
        final container = element.widget as Container;
        if (container.color == null) continue;
        widths.add(tester.getSize(find.byWidget(container)).width);
      }
      widths.sort((a, b) => b.compareTo(a));
      expect(widths.length, greaterThanOrEqualTo(3));
      expect(widths[0], closeTo(widths[1], 0.5), reason: '轨道与红条应同宽');
      expect(widths[2], lessThan(widths[0]));
    });
  });

  group('入口分派：经典阅读 → 畅想之星（用户 2026-09-15 裁定）', () {
    ReadCreditProgressBundle bundleForEntry() => buildReadCreditProgress(
      score: ReadCreditScore(
        items: [
          _item(ReadCreditKind.ordinary, passed: false),
          _item(ReadCreditKind.classic, passed: false),
          _item(ReadCreditKind.libraryEdu, passed: false),
          _item(ReadCreditKind.culture, passed: false),
        ],
      ),
      details: {
        ReadCreditKind.classic: _detail(
          ReadCreditKind.classic,
          ['已读完图书书名', '总阅读时长(秒)'],
          [
            ['书A', '7201'],
          ],
        ),
      },
      libraryEdu: (passed: 0, total: 5),
      borrowCounts: const {},
    );

    testWidgets('点经典阅读卡走 onOpenClassic，不触达入馆教育回调', (tester) async {
      final bundle = bundleForEntry();
      var openedClassic = false;
      var openedEdu = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [readCreditProgressProvider.overrideWith((ref) => bundle)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReadCreditProgressSection(
                  onOpenLibraryEdu: () => openedEdu = true,
                  onOpenClassic: () => openedClassic = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final classicTitle = find.descendant(
        of: find.byType(ReadCreditPartCard),
        matching: find.text('经典阅读'),
      );
      await tester.ensureVisible(classicTitle);
      await tester.pumpAndSettle();
      await tester.tap(classicTitle);
      await tester.pump();

      expect(openedClassic, isTrue, reason: '经典阅读卡应跳畅想之星（用户裁定）');
      expect(openedEdu, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未注入 onOpenClassic 时回退平台明细页（保底）', (tester) async {
      final bundle = bundleForEntry();
      var openedEdu = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [readCreditProgressProvider.overrideWith((ref) => bundle)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ReadCreditProgressSection(
                  onOpenLibraryEdu: () => openedEdu = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final classicTitle = find.descendant(
        of: find.byType(ReadCreditPartCard),
        matching: find.text('经典阅读'),
      );
      await tester.ensureVisible(classicTitle);
      await tester.pumpAndSettle();
      // 不注入回调时仍可点（走内置的 ReadCreditDetailScreen 兜底），
      // 这里只断言没有异常且不会误触发入馆教育回调。
      await tester.tap(classicTitle);
      await tester.pump();
      expect(openedEdu, isFalse);
    });

    test('蛟湖阅读页已删畅想之星独立入口，经典阅读卡注入 onOpenClassic', () {
      final source = File(
        'lib/features/comprehensive_service/presentation/jh_read_screen.dart',
      ).readAsStringSync();
      expect(
        source.contains('onOpenClassic:'),
        isTrue,
        reason: '经典阅读卡必须注入 onOpenClassic（跳畅想之星）',
      );
      expect(source.contains('CxstarScreen()'), isTrue);
      expect(
        source.contains('_CxstarCard'),
        isFalse,
        reason: '用户 2026-09-15 裁定：取消畅想之星独立入口',
      );
      expect(
        source.contains('畅想之星 · 经典阅读平台'),
        isFalse,
        reason: '用户 2026-09-15 裁定：删除该节标题',
      );

      // 原「经典阅读明细」数据归并到畅想之星页内（同一份 readCreditDetailProvider）。
      final cxstarSource = File(
        'lib/features/cxstar/presentation/cxstar_screen.dart',
      ).readAsStringSync();
      expect(cxstarSource.contains('_ReadCreditClassicSection'), isTrue);
      expect(cxstarSource.contains('readCreditDetailProvider'), isTrue);
      expect(cxstarSource.contains('学分平台 · 经典阅读明细'), isTrue);
    });
  });

  group('总成绩与完成口径', () {
    test('学分状态与完成计数进 bundle（文化活动不计入四部分）', () {
      final bundle = buildReadCreditProgress(
        score: ReadCreditScore(
          creditGranted: true,
          creditText: '获得学分',
          items: [
            _item(ReadCreditKind.classic, passed: true),
            _item(ReadCreditKind.ordinary, passed: true),
            _item(ReadCreditKind.libraryEdu, passed: true),
            _item(ReadCreditKind.infoLiteracy, passed: true),
            _item(ReadCreditKind.culture, passed: true),
          ],
        ),
        details: {
          ReadCreditKind.classic: _detail(
            ReadCreditKind.classic,
            ['已读完图书书名', '总阅读时长(秒)'],
            [
              for (var i = 0; i < 10; i++) ['书$i', '8000'],
            ],
          ),
          ReadCreditKind.ordinary: _ordinaryDetail(electronic: 2, paper: 1),
          ReadCreditKind.infoLiteracy: _detail(
            ReadCreditKind.infoLiteracy,
            ['学习视频数量'],
            [
              for (var i = 0; i < 20; i++) ['1'],
            ],
          ),
        },
        libraryEdu: (passed: 5, total: 5),
        borrowCounts: const {'本年': 10},
      );
      expect(bundle.creditGranted, isTrue);
      expect(bundle.creditText, '获得学分');
      expect(bundle.parts.length, 5);
      expect(bundle.creditParts.length, 4);
      expect(bundle.completedCount, 4);
    });

    test('readCreditPartCompleted：实际优先、缺席回退服务端、都没有则未完成', () {
      const actualFalseServerTrue = ReadCreditPartProgress(
        kind: ReadCreditKind.classic,
        requirementText: 'x',
        actualMet: false,
        remoteMet: true,
      );
      expect(readCreditPartCompleted(actualFalseServerTrue), isFalse);

      const actualNullServerTrue = ReadCreditPartProgress(
        kind: ReadCreditKind.infoLiteracy,
        requirementText: 'x',
        remoteMet: true,
      );
      expect(readCreditPartCompleted(actualNullServerTrue), isTrue);

      const noData = ReadCreditPartProgress(
        kind: ReadCreditKind.infoLiteracy,
        requirementText: 'x',
      );
      expect(readCreditPartCompleted(noData), isFalse);
    });
  });
}
