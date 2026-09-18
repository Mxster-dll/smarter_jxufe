import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/transcript_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/transcript_report.dart';

/// 打开「本科生成绩单」申请弹层（成绩页入口）。
Future<void> showTranscriptSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TranscriptSheet(),
  );
}

/// 本科生成绩单申请弹层：**选报表类型 + 填邮箱 → 发送到邮箱**。
///
/// 官方（教务处 2025-05-20 上线）只有邮箱投递，没有下载接口 —— 用户 2026-09-16 裁定
/// 「发送后我自己去邮箱下载」，故本弹层不做本地落盘。
class TranscriptSheet extends ConsumerStatefulWidget {
  const TranscriptSheet({super.key});

  @override
  ConsumerState<TranscriptSheet> createState() => _TranscriptSheetState();
}

class _TranscriptSheetState extends ConsumerState<TranscriptSheet> {
  final TextEditingController _emailCtrl = TextEditingController();

  String? _selectedCourseId;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 预填学生邮箱（学号 @ stu.jxufe.edu.cn）；取不到就不填。
    ref.read(transcriptDefaultEmailProvider.future).then((email) {
      if (!mounted || email == null || email.isEmpty) return;
      if (_emailCtrl.text.trim().isNotEmpty) return;
      setState(() => _emailCtrl.text = email);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  List<TranscriptReportType> get _types =>
      ref.read(transcriptReportTypesProvider).valueOrNull ??
      const <TranscriptReportType>[];

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    final types = _types;
    final courseId = _selectedCourseId ?? (types.isEmpty ? '' : types.first.courseId);
    if (courseId.isEmpty) {
      setState(() => _error = '请选择报表类型。');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = '邮箱不能为空。');
      return;
    }
    if (!transcriptEmailValid(email)) {
      setState(() => _error = '请输入正确的邮箱地址。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final enc = await ref.read(transcriptEncUserIdProvider.future);
      final message = await ref
          .read(transcriptRemoteDataSourceProvider)
          .sendTranscript(enc: enc, email: email, courseId: courseId);
      if (!mounted) return;
      setState(() => _status = message);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typesAsync = ref.watch(transcriptReportTypesProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, fp(context).grade, 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    size: 21,
                    color: fp(context).grade,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '本科生成绩单',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '教务处出具的电子成绩单（加盖电子签章）会以 PDF 发送到下面这个邮箱；'
              '收到后可在学信网验证。补考按 60 分计并标注「补考」，重修取最高分并标注「重修」。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            typesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在读取可申请的报表类型…', style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
              error: (e, _) => _typeError(scheme, e),
              data: (types) => types.isEmpty
                  ? Text(
                      '暂无可申请的报表类型（教务处未开放）。',
                      style: TextStyle(fontSize: 12.5, color: scheme.error),
                    )
                  : _typeDropdown(scheme, types),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('transcript_email'),
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: '接收邮箱',
                hintText: 'name@example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('transcript_send'),
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(_busy ? '发送中…' : '发送到邮箱'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                key: const Key('transcript_status'),
                style: TextStyle(fontSize: 12.5, color: scheme.error),
              ),
            ] else if (_status != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _status!,
                      key: const Key('transcript_status'),
                      style: TextStyle(fontSize: 12.5, color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => ref.read(externalUrlOpenerProvider)(
                  Uri.parse(kTranscriptVerifyUrl),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('学信网成绩单验证'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeDropdown(ColorScheme scheme, List<TranscriptReportType> types) {
    final effective = types.any((t) => t.courseId == _selectedCourseId)
        ? _selectedCourseId!
        : types.first.courseId;
    return DropdownButtonFormField<String>(
      key: const Key('transcript_type'),
      initialValue: effective,
      decoration: const InputDecoration(
        labelText: '报表类型',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final t in types)
          DropdownMenuItem<String>(value: t.courseId, child: Text(t.label)),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() => _selectedCourseId = value),
    );
  }

  Widget _typeError(ColorScheme scheme, Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.error),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => ref.invalidate(transcriptReportTypesProvider),
            icon: const Icon(Icons.refresh_outlined, size: 16),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
}
