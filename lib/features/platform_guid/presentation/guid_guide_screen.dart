import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/leave/data/providers/leave_providers.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/platform_guid/data/guid_capture_session.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';

/// 从任意文本中提取平台 GUID（UUID v4 形态）。
///
/// 用户粘贴的可能是完整 URL / 日志 / 接口参数，这里只取第一个
/// `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` 形态串。
final _guidRe = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);

/// 从文本提取 GUID；找不到返回 null。
String? guidFromText(String raw) {
  final m = _guidRe.firstMatch(raw.trim());
  return m?.group(0);
}

/// 判断字符串本身是否是一个合法 GUID。
bool isValidGuid(String value) {
  final v = value.trim();
  return _guidRe.hasMatch(v) && v.length == 36;
}

/// 「获取平台标识（GUID）」向导页。
///
/// GUID 是智慧江财平台在微信授权后下发的账号级标识（等同账号身份），
/// App 无法自行申请；本页提供：原理说明、一键抓取脚本步骤指引、
/// 从剪贴板识别保存、手动粘贴识别保存（与网费/请假/校历共用配置）。
class GuidGuideScreen extends ConsumerStatefulWidget {
  const GuidGuideScreen({super.key});

  @override
  ConsumerState<GuidGuideScreen> createState() => _GuidGuideScreenState();
}

class _GuidGuideScreenState extends ConsumerState<GuidGuideScreen> {
  final _pasteCtrl = TextEditingController();
  late final GuidCaptureSession _session;

  /// 微信是否在运行（null = 未检测）。
  bool? _wxRunning;

  @override
  void initState() {
    super.initState();
    _session = GuidCaptureSession();
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    unawaited(_session.cancel());
    _session.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  /// 检测微信进程状态并刷新。
  Future<void> _checkWechat() async {
    final running = await GuidCaptureSession.wechatRunning();
    if (!mounted) return;
    setState(() => _wxRunning = running);
  }

  Future<void> _saveGuid(String guid) async {
    final box = await ref.read(wxPlatformBoxProvider.future);
    await box.put('guid', guid.trim());
    ref.invalidate(wxGuidProvider);
    ref.invalidate(wxArrangementsProvider);
    ref.invalidate(netFeeSummaryProvider);
    ref.invalidate(leaveListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('已保存平台标识，网费 / 请假 / 校历实时源已生效'),
          duration: const Duration(seconds: 2),
        ));
    }
  }

  Future<void> _saveFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    final guid = guidFromText(raw);
    if (!mounted) return;
    if (guid == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('剪贴板中未找到平台标识（GUID），请先运行一键脚本复制'),
          duration: Duration(seconds: 3),
        ));
      return;
    }
    await _saveGuid(guid);
  }

  Future<void> _saveFromField() async {
    final text = _pasteCtrl.text.trim();
    if (!mounted) return;
    final guid = guidFromText(text);
    if (guid == null || !isValidGuid(guid)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('未能识别出平台标识：请粘贴包含 GUID 的完整内容'),
          duration: Duration(seconds: 3),
        ));
      return;
    }
    await _saveGuid(guid);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final guid = ref.watch(wxGuidProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('获取平台标识'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        children: [
          _buildStatusCard(context, scheme, guid),
          const SizedBox(height: 12),
          _buildWhatCard(context, scheme),
          const SizedBox(height: 22),
          _sectionTitle(context, '一键捕获（App 内 · 免外部工具）'),
          const SizedBox(height: 10),
          _buildCaptureCard(context, scheme),
          const SizedBox(height: 22),
          _sectionTitle(context, '从剪贴板保存'),
          const SizedBox(height: 10),
          _buildClipboardCard(context, scheme),
          const SizedBox(height: 22),
          _sectionTitle(context, '手动粘贴识别'),
          const SizedBox(height: 10),
          _buildPasteCard(context, scheme),
          const SizedBox(height: 12),
          _noteText(context, scheme),
        ],
      ),
    );
  }

  // ---------- App 内一键捕获 ----------

  Widget _buildCaptureCard(BuildContext context, ColorScheme scheme) {
    switch (_session.stage) {
      case GuidCaptureStage.idle:
        return _captureIdleCard(context, scheme);
      case GuidCaptureStage.preparing:
        return _captureBusyCard(context, scheme);
      case GuidCaptureStage.waiting:
        return _captureWaitCard(context, scheme);
      case GuidCaptureStage.success:
        return _captureSuccessCard(context, scheme);
      case GuidCaptureStage.stopped:
        return _captureStoppedCard(context, scheme);
    }
  }

  Widget _captureIdleCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'App 内置抓包代理会自动捕获微信请求中的平台标识',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '过程：首次会安装一个本地信任证书（确认一次）→ 打开微信的智慧江财'
              '任一实名功能页 → App 自动检测并保存。全程约 1 分钟，捕获后自动还原系统设置。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  await _checkWechat();
                  await _session.startCapture();
                },
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('开始一键捕获'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureBusyCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _session.detail ?? '准备中…',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureWaitCard(BuildContext context, ColorScheme scheme) {
    final wx = _wxRunning;
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '正在监听…',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_session.cancel()),
                  child: Text('取消', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (wx == null)
              Center(
                child: Text(
                  '检测微信…',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (!wx) ...[
              Row(
                children: [
                  Icon(Icons.chat_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '微信未运行。点击打开微信，然后进入「智慧江财」小程序。',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    await GuidCaptureSession.startWechat();
                    await _checkWechat();
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开微信'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '微信正在运行：代理需微信重启才生效。点击重启微信后进入「智慧江财」。',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await GuidCaptureSession.stopWechat();
                    await GuidCaptureSession.startWechat();
                    await _checkWechat();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重启微信'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '请在微信打开「智慧江财」，进入任意需要登录的功能页'
                '（如请假 / 网费 / 宿舍电费）。页面正常加载即代表已捕获，'
                'App 会自动完成并保存（90 秒内）。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureSuccessCard(BuildContext context, ColorScheme scheme) {
    final guid = _session.capturedGuid;
    return _whiteCard(
      context,
      color: scheme.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, size: 22, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '捕获成功',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              guid ?? '',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '系统设置已自动还原。点击保存即配置到网费 / 请假 / 校历。',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _session.reset();
                    setState(() => _wxRunning = null);
                  },
                  child: const Text('重新捕获'),
                ),
                const SizedBox(width: 8),
                if (guid != null)
                  FilledButton.icon(
                    onPressed: () => unawaited(_saveGuid(guid)),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('保存'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureStoppedCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      color: scheme.error.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 20, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _session.detail ?? _session.error ?? '捕获未完成',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _session.reset();
                    setState(() => _wxRunning = null);
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 当前状态卡 ----------

  Widget _buildStatusCard(
    BuildContext context,
    ColorScheme scheme,
    String? guid,
  ) {
    final configured = guid != null && guid.trim().isNotEmpty;
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (configured ? scheme.primary : scheme.outlineVariant)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                configured ? Icons.verified_outlined : Icons.link_off_outlined,
                size: 22,
                color: configured ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    configured ? '已配置平台标识' : '尚未配置平台标识',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    configured
                        ? '$guid\n网费 / 请假 / 校历实时源均已生效'
                        : '配置后网费、请假、校历官方安排将使用实时数据',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (configured)
              TextButton(
                onPressed: _confirmClear,
                child: Text('清除', style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除平台标识？'),
        content: const Text('清除后网费 / 请假将不可用，校历回到内置快照。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final box = await ref.read(wxPlatformBoxProvider.future);
    await box.delete('guid');
    ref.invalidate(wxGuidProvider);
    ref.invalidate(wxArrangementsProvider);
    ref.invalidate(netFeeSummaryProvider);
    ref.invalidate(leaveListProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('已清除平台标识'),
          duration: Duration(seconds: 2),
        ));
    }
  }

  // ---------- 说明卡 ----------

  Widget _buildWhatCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      color: scheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 17, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '平台标识（GUID）是什么？',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'GUID 是智慧江财平台在微信授权后下发的「账号级」用户标识（形如 '
              '00000000-0000-4000-8000-000000000000）。它只随你的账号，不随设备'
              '变化，因此获取一次即可长期使用。\n\n'
              'App 无微信授权能力，无法自行申请；该值仅存于微信内部且不落盘明文，'
              '唯一可靠的获取方式是「让微信走一次本地抓包观测」，由下方一键脚本完成。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 剪贴板保存卡 ----------

  Widget _buildClipboardCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '一键脚本执行后会把平台标识写入剪贴板，直接点这里识别保存。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _saveFromClipboard,
              icon: const Icon(Icons.content_paste_go, size: 18),
              label: const Text('从剪贴板保存'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 手动粘贴识别卡 ----------

  Widget _buildPasteCard(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '也可把包含 GUID 的任意内容（网页地址 / 抓包文本等）粘贴到下方识别：',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pasteCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: '粘贴包含 GUID 的内容…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveFromField,
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('识别并保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteText(BuildContext context, ColorScheme scheme) {
    return Text(
      '提示：GUID 等同账号身份凭证，请勿截图分享给他人。'
      '更换账号后需重新获取一次。',
      style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.outline),
    );
  }

  // ---------- 通用小块 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _whiteCard(
    BuildContext context, {
    required Widget child,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
