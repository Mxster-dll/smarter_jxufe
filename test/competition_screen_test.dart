/// 学科竞赛页面的装配守卫（两 Tab / 卡片 / 分页 / 空态）。
///
/// 用 provider override 喂假数据，**不碰真网络**：验证界面把仓库返回的
/// [CompetitionPage] 正确渲染成卡片与分页条，翻页真的换了查询条件。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_screen.dart';

const _apply = CompetitionApply(
  id: 199963,
  year: '2026',
  studentId: '0000000',
  studentName: '某同学',
  gameName: '蓝桥杯全国软件和信息技术专业人才大赛',
  type: CompetitionType.individual,
  applyTime: '2026-07-06',
  status: '未审批',
);

const _apply2 = CompetitionApply(
  id: 199960,
  year: '2025',
  studentId: '0000000',
  studentName: '某同学',
  gameName: '中国高校计算机大赛',
  type: CompetitionType.team,
  applyTime: '2025-11-02',
  status: '通过',
);

const _publicity = CompetitionPublicity(
  id: 202354,
  studentId: '0254173',
  studentName: '张艺馨',
  college: '计算机与人工智能学院',
  className: '25计算机4班',
  gameName: '全国大学生数学建模竞赛',
  type: CompetitionType.team,
  time: '2026-08-26',
);

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: CompetitionScreen()),
);

void main() {
  testWidgets('两个 Tab 都在，申请卡渲染比赛名 / 类型 / 状态 / 时间', (tester) async {
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_apply, _apply2],
            page: 1,
            totalPages: 3,
          ),
        ),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的申请'), findsOneWidget);
    expect(find.text('竞赛公示'), findsOneWidget);
    expect(find.text(_apply.gameName), findsOneWidget);
    expect(find.text('未审批'), findsOneWidget);
    expect(find.text('通过'), findsOneWidget);
    expect(find.text('2026 · 申请 2026-07-06'), findsOneWidget);
    expect(find.byTooltip('删除申请'), findsNWidgets(2));
    expect(find.text('第 1 / 3 页'), findsOneWidget);
    expect(find.text('申请竞赛'), findsOneWidget);
  });

  testWidgets('翻页把 pageNumber 交给 provider，并渲染新一页', (tester) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith((ref, query) {
          seen.add(query.page);
          return CompetitionPage(
            items: query.page == 2 ? const [_apply2] : const [_apply],
            page: query.page,
            totalPages: 3,
          );
        }),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(seen, [1]);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(seen, [1, 2]);
    expect(find.text(_apply2.gameName), findsOneWidget);
    expect(find.text('第 2 / 3 页'), findsOneWidget);
  });

  testWidgets('搜索把筛选条件交给 provider（第 1 页重新查）', (tester) async {
    final seen = <CompetitionApplyQuery>[];
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith((ref, query) {
          seen.add(query);
          return CompetitionPage(
            items: query.gameName.isEmpty ? const [_apply] : const [],
            page: query.page,
            totalPages: 1,
          );
        }),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '比赛名称'), '蓝桥杯');
    await tester.tap(find.byTooltip('查询'));
    await tester.pumpAndSettle();

    expect(seen.last.gameName, '蓝桥杯');
    expect(seen.last.page, 1);
    expect(find.text('还没有申请记录'), findsOneWidget);
  });

  testWidgets('切到公示 Tab 渲染全校公示行（姓名 / 学号 / 学院 / 班级）', (tester) async {
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith(
          (ref, query) =>
              const CompetitionPage(items: [_apply], page: 1, totalPages: 1),
        ),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('竞赛公示'));
    await tester.pumpAndSettle();

    expect(find.text(_publicity.gameName), findsOneWidget);
    expect(find.text('张艺馨 · 0254173'), findsOneWidget);
    expect(find.text('计算机与人工智能学院 · 25计算机4班'), findsOneWidget);
    expect(find.text('第 1 / 13 页'), findsOneWidget);
    // 公示页没有「申请竞赛」FAB。
    expect(find.text('申请竞赛'), findsNothing);
  });

  testWidgets('公示卡显示获奖等级胶囊（列表没有这一列 → 逐行补详情）', (tester) async {
    final asked = <({int id, CompetitionType type})>[];
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith(
          (ref, query) =>
              const CompetitionPage(items: [_apply], page: 1, totalPages: 1),
        ),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
        competitionPublicityAwardProvider.overrideWith((ref, key) {
          asked.add(key);
          return const CompetitionAwardLevel(level: '省赛', award: '二等奖');
        }),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('竞赛公示'));
    await tester.pumpAndSettle();

    expect(find.text('省赛 · 二等奖'), findsOneWidget);
    expect(asked, [(id: _publicity.id, type: _publicity.type)]);
  });

  testWidgets('等级未就绪时显示占位「…」', (tester) async {
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith(
          (ref, query) =>
              const CompetitionPage(items: [_apply], page: 1, totalPages: 1),
        ),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
        // 永不完成的 Future = 一直 loading。
        competitionPublicityAwardProvider.overrideWith(
          (ref, key) => Completer<CompetitionAwardLevel>().future,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('竞赛公示'));
    await tester.pumpAndSettle();
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('等级取不到时胶囊整颗不显示，卡片其余内容照常', (tester) async {
    await tester.pumpWidget(
      _app([
        competitionApplyListProvider.overrideWith(
          (ref, query) =>
              const CompetitionPage(items: [_apply], page: 1, totalPages: 1),
        ),
        competitionPublicityListProvider.overrideWith(
          (ref, query) => const CompetitionPage(
            items: [_publicity],
            page: 1,
            totalPages: 13,
          ),
        ),
        competitionPublicityAwardProvider.overrideWith(
          (ref, key) =>
              Future<CompetitionAwardLevel>.error(Exception('详情拉取失败')),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('竞赛公示'));
    await tester.pumpAndSettle();
    expect(find.text('…'), findsNothing);
    expect(find.text(_publicity.gameName), findsOneWidget);
  });
}
