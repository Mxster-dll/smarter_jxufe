/// AI 助手对话页。
///
/// 界面口径（与全应用一致）：
/// - 导航栏走 `paneAppBar`（内嵌到侧栏时不画导航栏），body 走 `PaneBody`；
/// - 卡片用 `appCardShape(context)`；
/// - 工具调用轨迹**对用户可见**（「正在查成绩…」）—— 用户拍板的「AI 融入底层」
///   要让人看得见它到底动了什么数据，而不是一个黑箱。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/ai/data/ai_chat_controller.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_message.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_floating_ball.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_page_launcher.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_markdown_view.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_write_confirm.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 首次进入时的建议问题（点一下直接发）。
const List<String> kAiStarterQuestions = [
  '今天蒋剑老师什么时候没课？',
  '我这学期有哪些课？',
  '我目前的加权平均分是多少？',
  '转专业需要什么条件？',
  '最近有什么作业要交？',
];

/// 一条历史消息是否要出现在对话流里。
///
/// ⚠ **这是「空卡片」的守卫**（用户 2026-09-19 报「AI 回复中偶尔会出现空卡片」）。
/// 根因：带工具调用的那一轮，assistant 消息的 `content` 常常是**空串** —— OpenAI
/// 协议要求这条消息（连同 `tool_calls`）原样发回端点，而模型在决定调用工具时往往不附
/// 任何文字。它必须留在历史里（抽掉会让端点直接 400），但**不该画出来**：画出来就是
/// 一张只有内边距的空卡片，每查一次工具多一张。它查了什么由 `_TraceStrip` 表达 ——
/// 那正是「让用户看得见 AI 动了哪些数据」的设计。
///
/// 顺带挡掉 `tool` 与 `system`（前者由轨迹条代表，后者是提示词）。
/// 单独抽成函数是为了能单测：规则藏在 `build` 里就只能靠 widget 测试碰运气。
bool aiShouldRenderMessage(AiChatMessage m) {
  if (m.role != AiRole.user && m.role != AiRole.assistant) return false;
  return m.content.trim().isNotEmpty;
}

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _showReasoning = false;

  /// 悬浮球计数器。
  ///
  /// ⚠ **必须在 `initState` 里把它取出来存住**：`dispose()` 里再 `ref.read`
  /// 会抛 `Bad state: Cannot use "ref" after the widget was disposed.`
  /// （flutter_riverpod 在 dispose 阶段就废掉 ref 了）。
  StateController<int>? _chatOpen;

  @override
  void initState() {
    super.initState();
    // 对话页开着时隐藏全局悬浮球（避免叠一个重复入口）
    _chatOpen = ref.read(aiChatScreenOpenProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatOpen?.state++;
      // 写操作确认闸门：控制器不碰 UI，这里把回调挂上去
      ref.read(aiChatControllerProvider).onConfirmWrite = (request) =>
          showAiWriteConfirm(context, request);
    });
  }

  @override
  void dispose() {
    final open = _chatOpen;
    if (open != null) {
      // ⚠ 这次「减一」**必须推迟到微任务**，不能在 dispose 里直接做 ——
      // 两件事都挡在那里：
      // ① `dispose()` 跑在 `BuildOwner.finalizeTree()`（unmount 阶段），此时
      //    Riverpod 仍处于「widget 树正在构建」状态，`_notifyListeners` 会被它的
      //    调试守卫拦下并抛
      //    `Tried to modify a provider while the widget tree was building.`
      //    （`flutter_riverpod/src/framework.dart` 的 `_debugCanModifyProviders`）
      //    → **值改了，但监听者一个都收不到通知**；
      // ② 即使通知送出去，`SchedulerBinding.schedulerPhase` 那时也是
      //    `persistentCallbacks`，`ensureVisualUpdate()` 在该阶段**不排帧**。
      // 合起来的症状 = 悬浮球隐藏后再也回不来（用户 2026-09-19 报的「电脑端不
      // 显示悬浮球」）。微任务里这两条都已解除（帧的同步阶段已结束）。
      // 对照：`initState` 里那个「加一」放在 `addPostFrameCallback` 里，
      // 跑在 `postFrameCallbacks` 阶段，两条都不犯，所以它一直是好的。
      // 守卫 = `test/ai_floating_ball_test.dart` 的「关掉后回来」。
      scheduleMicrotask(() {
        try {
          if (open.state > 0) open.state--;
          WidgetsBinding.instance.ensureVisualUpdate();
        } catch (_) {
          // provider 已随容器销毁（App 退出 / 测试拆树）→ 没有悬浮球要恢复，
          // 静默收场。`StateController.state` 在容器销毁后会抛
          // `Bad state: Tried to use StateController<int> after 'dispose' was called.`
        }
      });
    }
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    final controller = ref.read(aiChatControllerProvider);
    // 让输入框先清空、列表先长出用户气泡，再开始跑（体感更快）
    await Future<void>.delayed(Duration.zero);
    await controller.send(text);
    if (mounted) _scrollToEnd();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('清空对话'),
        content: const Text('会删除这台设备上与当前账号的全部对话记录，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(aiChatControllerProvider).clear();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(
          sections: [SettingsSection.aiAssistant],
        ),
      ),
    );
  }

  /// 回答里的 `[文字](链接)` 交给系统浏览器。
  ///
  /// 走全应用统一的外链出口 `externalUrlOpenerProvider`（provider 化的意义就是测试
  /// 能替换掉它，不会真去调起浏览器）；只放行 http/https —— 模型偶尔会编出
  /// `javascript:` / `file:` 之类的 scheme，不能顺手交给系统。
  void _openLink(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;
    unawaited(ref.read(externalUrlOpenerProvider)(uri));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(aiChatControllerProvider);
    final ready = ref.watch(aiReadyProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('AI 助手'),
        actions: [
          if (controller.messages.isNotEmpty)
            IconButton(
              tooltip: '清空对话',
              onPressed: controller.busy ? null : _clear,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: PaneBody(
        child: Column(
          children: [
            Expanded(
              child: !ready && controller.messages.isEmpty
                  ? _NotConfigured(onConfigure: _openSettings)
                  : _buildList(controller, scheme),
            ),
            if (controller.error != null)
              _ErrorBanner(
                message: controller.error!,
                onDismiss: () => ref.read(aiChatControllerProvider).clearError(),
              ),
            _Composer(
              controller: _input,
              focus: _focus,
              busy: controller.busy,
              onSend: _send,
              onStop: () => ref.read(aiChatControllerProvider).cancel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AiChatController controller, ColorScheme scheme) {
    final messages = controller.messages;
    final items = <Widget>[];

    if (messages.isEmpty && !controller.busy) {
      items.add(
        _StarterQuestions(
          onPick: (q) {
            _input.text = q;
            _focus.requestFocus();
          },
        ),
      );
    }

    for (final m in messages) {
      if (!aiShouldRenderMessage(m)) continue;
      if (m.role == AiRole.user) {
        items.add(_UserBubble(text: m.content));
      } else {
        items.add(
          _AssistantBubble(
            text: m.content,
            isNotice: m.isError,
            onTapLink: _openLink,
          ),
        );
      }
    }

    if (controller.traces.isNotEmpty) {
      items.add(_TraceStrip(traces: controller.traces));
    }

    if (controller.busy) {
      items.add(
        _StreamingBubble(
          text: controller.streamText,
          reasoning: controller.streamReasoning,
          showReasoning: _showReasoning,
          onTapLink: _openLink,
          onToggleReasoning: () =>
              setState(() => _showReasoning = !_showReasoning),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: items,
    );
  }
}

// ────────────────────────────── 消息气泡 ──────────────────────────────

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 10, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          text,
          style: TextStyle(fontSize: 14.5, height: 1.5, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  final bool isNotice;
  final void Function(String url)? onTapLink;

  const _AssistantBubble({
    required this.text,
    this.isNotice = false,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isNotice) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, right: 48),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    // 双保险：调用方已经跳过空消息，这里再兜一次 —— 气泡一旦空着就是一张空卡片
    // （只有内边距 + 底 + 描边）。这个守卫让「画出空卡片」在组件层面不可能发生。
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10, right: 32),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          color: appCardColorOf(scheme),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline(context, 0.6)),
        ),
        // 回答按 markdown 渲染（标题 / 列表 / 表格 / 代码块 / 粗体 / 行内码 / 链接）。
        // 解析与渲染分家：结构在 `domain/ai_markdown.dart`（纯 Dart、可单测）。
        child: AiMarkdownView(
          source: text,
          baseStyle: TextStyle(
            fontSize: 14.5,
            height: 1.6,
            color: scheme.onSurface,
          ),
          onTapLink: onTapLink,
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  final String text;
  final String reasoning;
  final bool showReasoning;
  final VoidCallback onToggleReasoning;
  final void Function(String url)? onTapLink;

  const _StreamingBubble({
    required this.text,
    required this.reasoning,
    required this.showReasoning,
    required this.onToggleReasoning,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = text.trim().isEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10, right: 32),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          color: appCardColorOf(scheme),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline(context, 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (empty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '正在思考…',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            else
              AiMarkdownView(
                source: text,
                baseStyle: TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  color: scheme.onSurface,
                ),
                onTapLink: onTapLink,
              ),
            if (reasoning.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onToggleReasoning,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showReasoning ? Icons.expand_less : Icons.expand_more,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      showReasoning ? '收起思考过程' : '查看思考过程',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showReasoning)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  // 思考过程也按 markdown 渲染：模型的推理里常用小标题和分点，
                  // 平铺成一坨会很难读（它是折叠的调试视图，用弱化样式即可）。
                  child: AiMarkdownView(
                    source: reasoning,
                    baseStyle: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── 工具轨迹 ──────────────────────────────

class _TraceStrip extends StatelessWidget {
  final List<AiToolTrace> traces;

  const _TraceStrip({required this.traces});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in traces)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  if (t.running)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: scheme.primary,
                      ),
                    )
                  else
                    Icon(
                      t.ok ? Icons.check_circle_outline : Icons.error_outline,
                      size: 13,
                      color: t.ok
                          ? scheme.primary.withValues(alpha: 0.8)
                          : scheme.error,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t.running ? '${t.label}…' : t.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final t in traces)
            if (t.ui?['kind'] == 'navigate' && t.ui?['title'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: _NavigateChip(title: '${t.ui!['title']}'),
              ),
        ],
      ),
    );
  }
}

/// 「打开某页面」按钮 —— 工具只给目标名，真正跳转由用户点击触发。
class _NavigateChip extends StatelessWidget {
  final String title;
  const _NavigateChip({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => openHomeServiceByTitle(context, title),
        icon: const Icon(Icons.arrow_forward, size: 15),
        label: Text('打开「$title」'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }
}

// ────────────────────────────── 空态 / 错误 / 输入 ──────────────────────────────

class _NotConfigured extends StatelessWidget {
  final VoidCallback onConfigure;
  const _NotConfigured({required this.onConfigure});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              '还没配置 AI 接口',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '填一个 OpenAI 兼容的接口地址与 API Key 就能用了。'
              '你的 Key 只存在这台设备上，不会随云同步上传。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onConfigure,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarterQuestions extends StatelessWidget {
  final void Function(String question) onPick;
  const _StarterQuestions({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '可以这样问',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in kAiStarterQuestions)
                ActionChip(
                  label: Text(q),
                  onPressed: () => onPick(q),
                  labelStyle: const TextStyle(fontSize: 12.5),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 26),
          Center(
            child: Text(
              'AI 会去读你的成绩、课表、学籍与校规来回答；\n'
              '要改设置时会先弹确认框，你不同意就不会动。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: onDismiss,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final Future<void> Function([String? preset]) onSend;
  final VoidCallback onStop;

  const _Composer({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: appCardColorOf(scheme),
        border: Border(
          top: BorderSide(color: AppColors.hairline(context, 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: busy ? null : (_) => onSend(),
              decoration: InputDecoration(
                hintText: busy ? '正在回答…' : '问点什么，比如「今天谁没课」',
                hintStyle: const TextStyle(fontSize: 13.5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.hairline(context, 0.7)),
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? IconButton.filledTonal(
                  tooltip: '停止',
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded),
                )
              : IconButton.filled(
                  tooltip: '发送',
                  onPressed: () => onSend(),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
        ],
      ),
    );
  }
}
