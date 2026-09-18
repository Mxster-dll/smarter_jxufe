/// 写操作二次确认弹窗（用户拍板的「只读 + 写操作需确认」的界面落地）。
///
/// 只做一件事：把一个 [AiWriteRequest] 说成人话，让用户点「同意 / 拒绝」。
/// **默认拒绝**：点背景、按返回键、异常 → 全部按「不同意」处理
/// （[showDialog] 返回 null 时调用方拿到 false）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';

Future<bool> showAiWriteConfirm(
  BuildContext context,
  AiWriteRequest request,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.edit_note_outlined),
      title: Text(request.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.detail, style: const TextStyle(fontSize: 14, height: 1.6)),
          const SizedBox(height: 12),
          Text(
            '这是 AI 助手发起的修改，需要你确认后才会生效。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('不同意'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('同意修改'),
        ),
      ],
    ),
  );
  return result ?? false;
}
