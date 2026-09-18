/// 设置页「AI 助手」节的卡片。
///
/// 放在 `features/ai/` 而不是塞进 `settings_screen.dart`（那个文件已经 1600+ 行）：
/// 设置页只挂一个 `_SectionSpec` 入口，实现留在这里。
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ai/data/ai_providers.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_floating_ball.dart';

class AiAssistantSettingsCard extends ConsumerWidget {
  const AiAssistantSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(aiSettingsStoreProvider);
    final settings = store.settings;
    final active = settings.active;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: appCardShape(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                Icons.auto_awesome_outlined,
                color: fp(context).cardAccent,
              ),
              title: const Text('AI 助手'),
              subtitle: Text(
                active == null
                    ? '未配置 —— 点这里选一个供应商并填入 API Key'
                    : '${active.name} · ${active.model}\n'
                          '密钥 ${active.maskedApiKey}'
                          '${settings.profiles.length > 1 ? ' · 共 ${settings.profiles.length} 套配置' : ''}',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              isThreeLine: active != null,
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => showAiProfilesSheet(context, ref),
            ),
            const Divider(height: 1),
            // 电脑端不出悬浮球（用户 2026-09-19 裁定）→ 开关在桌面端没有意义，
            // 换成一说明行，别让用户拨一个什么都不做的开关。
            if (aiDesktopPlatformOn(defaultTargetPlatform.name))
              const ListTile(
                dense: true,
                leading: Icon(Icons.desktop_windows_outlined, size: 20),
                title: Text('全局悬浮球', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  '电脑端不显示悬浮球 —— 入口在左侧导航栏「数据一览」下方的「AI 助手」',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              SwitchListTile(
                dense: true,
                title: const Text('全局悬浮球', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '在任意页面显示一个可以随时问 AI 的圆球',
                  style: TextStyle(fontSize: 12),
                ),
                value: settings.floatingBall,
                onChanged: (v) => store.setFloatingBall(v),
              ),
            if (active != null) ...[
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline, size: 20),
                title: const Text('开始对话', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  '用「${active.model}」提问；可以查成绩、课表、校规，也能改设置',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiChatScreen()),
                ),
              ),
            ],
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.tune, size: 20),
              title: const Text('一次提问最多几轮工具调用',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '当前 ${settings.maxToolRounds} 轮。查多个数据源时会用掉几轮，'
                '调大可减少「查一半就回答」，但更费 token。',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              trailing: Text(
                '${settings.maxToolRounds}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              onTap: () => _editRounds(context, ref, settings.maxToolRounds),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRounds(BuildContext context, WidgetRef ref, int current) async {
    var value = current.toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          icon: const Icon(Icons.tune),
          title: const Text('工具调用轮次上限'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()} 轮',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              Slider(
                value: value,
                min: kAiMinToolRounds.toDouble(),
                max: kAiMaxToolRoundsLimit.toDouble(),
                divisions: kAiMaxToolRoundsLimit - kAiMinToolRounds,
                label: '${value.round()}',
                onChanged: (v) => setState(() => value = v),
              ),
              const Text(
                '问一个需要查多处数据的问题（如「今天谁没课」）通常要 2~4 轮。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ref.read(aiSettingsStoreProvider).setMaxToolRounds(value.round());
    }
  }
}

// ────────────────────────────── 配置列表弹层 ──────────────────────────────

/// 打开「配置管理」底部弹层（列出全部配置，可切换 / 编辑 / 新增）。
Future<void> showAiProfilesSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _ProfilesSheet(),
  );
}

class _ProfilesSheet extends ConsumerWidget {
  const _ProfilesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(aiSettingsStoreProvider);
    final settings = store.settings;
    final activeId = settings.active?.id;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 配置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '可以保存多套（学校/家里/本地模型），随时切换。密钥只存在本机。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (settings.profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有配置。点下面的「新增配置」开始。',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final p in settings.profiles)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            p.id == activeId
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: p.id == activeId ? scheme.primary : null,
                          ),
                          title: Text(p.name, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${p.model.isEmpty ? '未填模型' : p.model}'
                            '${p.ready ? '' : ' · 缺少${p.missingField}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => store.activate(p.id),
                          trailing: IconButton(
                            tooltip: '编辑',
                            iconSize: 18,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await showAiProfileEditor(context, ref, p);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await showAiProfileEditor(context, ref, null);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增配置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────── 配置编辑弹层 ──────────────────────────────

/// 新增（[existing] 为 null）或编辑一套配置。
Future<void> showAiProfileEditor(
  BuildContext context,
  WidgetRef ref,
  AiConfig? existing,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ProfileEditor(existing: existing),
    ),
  );
}

class _ProfileEditor extends ConsumerStatefulWidget {
  final AiConfig? existing;
  const _ProfileEditor({this.existing});

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  late AiConfig _draft;
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _extra;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.existing ?? AiConfig.fromPreset(aiPresets.first, id: newAiConfigId());
    _name = TextEditingController(text: _draft.name);
    _baseUrl = TextEditingController(text: _draft.baseUrl);
    _model = TextEditingController(text: _draft.model);
    _apiKey = TextEditingController(text: _draft.apiKey);
    _extra = TextEditingController(text: _draft.extraSystemPrompt);
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _extra.dispose();
    super.dispose();
  }

  AiConfig get _current => _draft.copyWith(
    name: _name.text.trim().isEmpty ? '未命名' : _name.text.trim(),
    baseUrl: aiNormalizeBaseUrl(_baseUrl.text),
    model: _model.text.trim(),
    apiKey: _apiKey.text.trim(),
    extraSystemPrompt: _extra.text,
  );

  void _applyPreset(AiPreset preset) {
    setState(() {
      _draft = _draft.copyWith(presetId: preset.id, name: preset.name);
      _name.text = preset.name;
      _baseUrl.text = preset.baseUrl;
      if (preset.defaultModel.isNotEmpty) _model.text = preset.defaultModel;
    });
  }

  Future<void> _test() async {
    final config = _current;
    if (config.baseUrl.isEmpty || config.apiKey.isEmpty) {
      _toast('先填接口地址和 API Key');
      return;
    }
    setState(() => _testing = true);
    final result = await ref.read(aiClientProvider).testConnection(config);
    if (!mounted) return;
    setState(() => _testing = false);
    _toast(result.message);
  }

  Future<void> _save() async {
    final config = _current;
    if (config.baseUrl.isEmpty) {
      _toast('请填接口地址');
      return;
    }
    await ref.read(aiSettingsStoreProvider).upsertProfile(config);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除这套配置'),
        content: Text('「${_current.name}」的接口地址与 API Key 会从本机删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(aiSettingsStoreProvider).removeProfile(_draft.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = aiPresetOf(_draft.presetId);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? '新增 AI 配置' : '编辑 AI 配置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            Text('供应商', style: _labelStyle(scheme)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in aiPresets)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: _draft.presetId == p.id,
                    onSelected: (_) => _applyPreset(p),
                    labelStyle: const TextStyle(fontSize: 12.5),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (preset.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                preset.note,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '给自己看的备注，如「宿舍 DeepSeek」',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://api.deepseek.com/v1',
                helperText: 'OpenAI 兼容端点；漏写 /v1 会自动补上',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '模型名',
                hintText: 'deepseek-chat',
                isDense: true,
              ),
            ),
            if (preset.models.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in preset.models)
                    ActionChip(
                      label: Text(m, style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => setState(() => _model.text = m),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-…',
                helperText: '只保存在本机 Hive，不参与云同步',
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示' : '隐藏',
                  iconSize: 18,
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('温度', style: _labelStyle(scheme)),
                const Spacer(),
                Text(
                  _draft.temperature.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: _draft.temperature,
              min: kAiMinTemperature,
              max: kAiMaxTemperature,
              divisions: 20,
              label: _draft.temperature.toStringAsFixed(1),
              onChanged: (v) => setState(() => _draft = _draft.copyWith(temperature: v)),
            ),
            Text(
              '查数据类的问题建议 0~0.5（越低越稳），闲聊可以调高。',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('使用函数调用', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '关掉后改为「预先把数据塞进提示词」，适合不支持工具调用的模型',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _draft.useTools,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(useTools: v)),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('流式输出', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('逐字显示回答（打字机效果）', style: TextStyle(fontSize: 11.5)),
              value: _draft.stream,
              onChanged: (v) => setState(() => _draft = _draft.copyWith(stream: v)),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('携带「现在的情况」', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '每次提问附带当前时间、教学周与你的学院专业，减少一次工具调用',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _draft.includeSnapshot,
              onChanged: (v) =>
                  setState(() => _draft = _draft.copyWith(includeSnapshot: v)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _extra,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: '额外要求（可选）',
                hintText: '如「回答尽量简短」',
                isDense: true,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.existing != null)
                  IconButton(
                    tooltip: '删除这套配置',
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                TextButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 17),
                  label: const Text('测试连接'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(ColorScheme scheme) =>
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurface);
}
