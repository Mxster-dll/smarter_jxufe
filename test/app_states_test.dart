/// 三态组件（`lib/design/app_states.dart`）行为守卫 —— 2026-09-20 立（架构审查 ⑤）。
///
/// 守三件事：**错误文案必须是人话**（走 `friendlyErrorText`，不许把 `Exception: `
/// 前缀印给用户）、**重试按钮只在给了回调时才画**、**空/加载态的文案与图标按契约来**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/app_states.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// `AppException` 是抽象基类（全仓 35 个站点异常都 `extends` 它）→ 测试里用最小具体子类。
class _FakeAppError extends AppException {
  const _FakeAppError(super.message);
}

void main() {
  group('AppLoadingState', () {
    testWidgets('默认只画转圈，不画文案', (tester) async {
      await tester.pumpWidget(_host(const AppLoadingState()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('给了 message 就画在转圈下面', (tester) async {
      await tester.pumpWidget(
        _host(const AppLoadingState(message: '首次取数要把当下学期的课逐门扫一遍')),
      );
      expect(find.text('首次取数要把当下学期的课逐门扫一遍'), findsOneWidget);
    });

    testWidgets('compact 档转圈更小（20 vs 28）', (tester) async {
      await tester.pumpWidget(_host(const AppLoadingState()));
      final normal = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(normal.width, 28);

      await tester.pumpWidget(_host(const AppLoadingState(compact: true)));
      final compact = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(compact.width, 20);
    });
  });

  group('AppErrorState', () {
    testWidgets('AppException 的 message 直接上屏', (tester) async {
      await tester.pumpWidget(
        _host(AppErrorState(error: _FakeAppError('学习通限流了，稍后再试'))),
      );
      expect(find.text('学习通限流了，稍后再试'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('★ 裸 Exception 不许把 `Exception: ` 前缀印给用户', (tester) async {
      await tester.pumpWidget(_host(AppErrorState(error: Exception('仓库炸了'))));
      expect(find.text('仓库炸了'), findsOneWidget);
      expect(find.text('Exception: 仓库炸了'), findsNothing);
    });

    testWidgets('title 给了才画（加载失败 / 成绩取不到 之类）', (tester) async {
      await tester.pumpWidget(
        _host(AppErrorState(error: _FakeAppError('网络不通'), title: '加载失败')),
      );
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('网络不通'), findsOneWidget);

      await tester.pumpWidget(
        _host(AppErrorState(error: _FakeAppError('网络不通'))),
      );
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('★ 没给 onRetry 就不画重试按钮（只读页不该出现死按钮）', (tester) async {
      await tester.pumpWidget(
        _host(AppErrorState(error: _FakeAppError('网络不通'))),
      );
      expect(find.text('重试'), findsNothing);

      var taps = 0;
      await tester.pumpWidget(
        _host(
          AppErrorState(
            error: _FakeAppError('网络不通'),
            onRetry: () => taps++,
          ),
        ),
      );
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(taps, 1);
    });

    testWidgets('retryLabel / icon / compact 三档可调', (tester) async {
      await tester.pumpWidget(
        _host(
          AppErrorState(
            error: _FakeAppError('会话没了'),
            onRetry: () {},
            retryLabel: '重新登录',
            icon: Icons.lock_outline,
            compact: true,
          ),
        ),
      );
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      final icon = tester.widget<Icon>(find.byIcon(Icons.lock_outline));
      expect(icon.size, 32);
    });
  });

  group('AppEmptyState', () {
    testWidgets('只有文案时也画（灰字居中）', (tester) async {
      await tester.pumpWidget(_host(const AppEmptyState(message: '暂无成绩数据')));
      expect(find.text('暂无成绩数据'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('图标与操作按钮都是可选件', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          AppEmptyState(
            message: '还没有材料',
            icon: Icons.inbox_outlined,
            action: TextButton(
              onPressed: () => taps++,
              child: const Text('添加材料'),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      await tester.tap(find.text('添加材料'));
      expect(taps, 1);
    });
  });
}
