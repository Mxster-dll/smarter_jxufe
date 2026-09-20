/// 三态组件（加载 / 空 / 错误）的**唯一实现** —— 2026-09-20 立（架构审查 ⑤）。
///
/// 由来：审计实测「横向没有地基」的具体表现之一 —— `lib/presentation` 下
/// **39 个文件**各自手写一遍 `Text('重试')` 的错误块，加载态是 107 处裸
/// `CircularProgressIndicator`、空态是「`暂无…` 文案 + 自己拼的 `Center`」。
/// 于是同一个 App 里：
///
/// - 错误文案有的剥了 `Exception: ` 前缀、有的没剥（`'$e'` 直接把英文类名印给用户）；
/// - 重试按钮一会儿 `ElevatedButton` / 一会儿 `FilledButton.tonal` / 一会儿 `TextButton`；
/// - 图标有 48 的、有 32 的、还有干脆不画的。
///
/// 三件套的**契约**：
///
/// | 组件 | 管什么 | 不管什么 |
/// |---|---|---|
/// | `AppLoadingState` | 转圈 + 一句「正在做什么」 | 骨架屏（各页差异太大，不做） |
/// | `AppErrorState` | 图标 + 标题 + **异常 → 人话**（走 `friendlyErrorText`）+ 重试 | 具体错误分类（`error` 原样收下） |
/// | `AppEmptyState` | 图标（可选）+ 灰字一句 + 可选操作按钮 | 空态的业务分支（调用方自己判 `isEmpty`） |
///
/// ⚠ 三个都**自带 `Center` + `Padding`**，直接塞进 `AsyncValue.when` 的
/// `loading:` / `error:` 分支即可；要放进 `ListView` 时把 `compact: true` 打开
/// （图标 32、间距收紧），别自己再包一层。
///
/// ⚠ **不要**在这里 import riverpod —— 设计层保持「只认 flutter」，需要
/// `AsyncValue` 糖的调用方自己在页面里写 `when`（页面本来就知道刷哪个 provider）。
library;

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/design/app_theme.dart';

/// 加载中：转圈 + 可选的一句说明（「首次取数要把当下学期的课逐门扫一遍」这种）。
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.message,
    this.compact = false,
    this.padding = const EdgeInsets.all(24),
  });

  /// 可选说明。**别写「加载中…」**（转圈已经在说这件事）—— 写就写清在等什么。
  final String? message;

  /// 紧凑档（放进列表 / 卡片里用）：转圈小一号、间距收紧。
  final bool compact;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 20 : 28,
              height: compact ? 20 : 28,
              child: const CircularProgressIndicator(strokeWidth: 2.6),
            ),
            if (message != null) ...[
              SizedBox(height: compact ? 10 : 14),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted(context),
                  fontSize: compact ? 12.5 : 13.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 出错：图标 + 可选标题 + **人话文案** + 可选重试。
///
/// [error] 直接喂异常对象（`error: (e, _) => AppErrorState(error: e, …)`）——
/// 文案一律经 `friendlyErrorText` 出，**调用方不要再自己拼 `'加载失败：$e'`**
/// （那会把 `Exception: ` 前缀印给用户；要加前缀就写进 [title]）。
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.error,
    this.title,
    this.onRetry,
    this.retryLabel = '重试',
    this.retryKey,
    this.icon = Icons.error_outline,
    this.compact = false,
    this.retryIcon = true,
    this.padding = const EdgeInsets.all(24),
  });

  /// 原始异常 / 错误对象。
  final Object error;

  /// 可选标题（如「加载失败」「成绩取不到」）。为空则只画一句文案。
  final String? title;

  /// 重试回调；为空则**不画按钮**（只读页 / 无重试语义的场景）。
  final VoidCallback? onRetry;

  final String retryLabel;

  /// 重试按钮的 key（有些测试按 key 找按钮，如 `Key('dzjSubRetry')`）——
  /// 迁移旧页面时把它带过来，别让守卫测试红掉。
  final Key? retryKey;

  final IconData icon;

  final bool compact;

  /// 重试按钮是否带刷新图标（长页面里带图标更好找，卡片内建议关）。
  final bool retryIcon;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 32 : 48,
              color: AppColors.critical(context),
            ),
            SizedBox(height: compact ? 10 : 16),
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
            ],
            Text(
              friendlyErrorText(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted(context),
                fontSize: compact ? 12.5 : null,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 14 : 24),
              if (retryIcon)
                FilledButton.tonalIcon(
                  key: retryKey,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(retryLabel),
                )
              else
                FilledButton.tonal(
                  key: retryKey,
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    foregroundColor: scheme.primary,
                  ),
                  child: Text(retryLabel),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空数据：可选图标 + 一句灰字 + 可选操作按钮。
///
/// ⚠ 文案要**说清是"没有"还是"没取到"** —— 学习通那轮踩过：把「本轮没扫到」
/// 说成「这门课没有作业」，用户会以为是数据错（见 §30）。拿不准就用
/// `snapshot` 里的 pending/failed 判据换个说法，别硬写「暂无数据」。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.action,
    this.compact = false,
    this.padding = const EdgeInsets.all(24),
  });

  final String message;

  /// 可选图标（如 `Icons.inbox_outlined`）；为空则只画文案。
  final IconData? icon;

  /// 可选操作（如「添加材料」按钮）。
  final Widget? action;

  final bool compact;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: compact ? 30 : 40,
                color: AppColors.textMuted(context),
              ),
              SizedBox(height: compact ? 8 : 12),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted(context),
                fontSize: compact ? 12.5 : 13.5,
              ),
            ),
            if (action != null) ...[
              SizedBox(height: compact ? 12 : 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
