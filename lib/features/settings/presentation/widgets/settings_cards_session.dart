/// `settings_cards.dart` 的「session」一组（2026-10-08 架构审计第三轮 · 按类拆文件）。
///
/// 拆分自 `settings_cards.dart`（2297 行 / 20 个 widget 类）：调用方**不用改** —— 桶文件
/// `export` 了本文件。共用顶层件（`settingsClearSentinel` / `SettingsSubLabel`）留在桶里，
/// 故这里反向 import 桶文件（Dart 允许互相 import，见 AGENTS.md §33.4.4 ②）。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/domain/ims_token_refresh.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'settings_cards.dart';

/// 「公共查询」节：默认教学楼（找空闲教室 / 找无课时间用的默认值）。
///
/// 用户 2026-09-19 要求：「教学楼默认选哪个是可以设置的」。偏好落在
/// `features/ims/public_query/data/public_query_prefs.dart`（Hive box
/// `publicQueryPrefs`），本卡只读写它、**不发任何请求**；校区 / 楼房候选来自公共查询
/// 既有的两个下拉 provider，进弹层才取。
class SettingsPublicQueryCard extends ConsumerWidget {
  const SettingsPublicQueryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = AppColors.textMuted(context);
    final building = ref.watch(publicQueryPrefsStoreProvider).defaultBuilding;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('settingsDefaultBuilding'),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => const SettingsBuildingPickerSheet(),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 18,
                    color: fp(context).cardAccent,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '默认教学楼',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      building?.label ?? '未设置',
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: building == null
                            ? muted
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '「找空闲教室」打开时会自动选中这栋楼；若它不在当前校区，就不预选。',
                style: TextStyle(fontSize: 12, height: 1.5, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 平台标识（GUID）卡：展示当前配置状态并进入获取向导。
///
/// 用户 2026-09-11 裁定：「首页宫格里的获取 GUID 应该放到设置里」——宫格磁贴已删，
/// 设置页是本入口的唯一位置（网费实时源 / 请假记录 / 校历官方安排都依赖该标识）。
class SettingsPlatformGuidCard extends ConsumerWidget {
  const SettingsPlatformGuidCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final guid = ref.watch(platformGuidProvider).valueOrNull;
    final configured = guid != null && guid.isNotEmpty;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSubLabel(
              icon: Icons.vpn_key_outlined,
              title: '微信平台标识（GUID）',
              subtitle: '校园网实时源 / 请假记录 / 校历官方安排 都依赖它',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: configured
                        ? AppColors.successFill(context)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    configured ? '已配置' : '未配置',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: configured
                          ? AppColors.success(context)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    configured
                        ? '当前：${_maskGuid(guid)}'
                        : '未配置时相关功能自动回退离线 / 门户数据源',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GuidGuideScreen(),
                  ),
                ),
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: Text(configured ? '查看 / 更新' : '去获取'),
              ),
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GUID 由微信授权「智慧江财」下发，等同账号标识，一次获取长期有效；'
                    'App 内可一键抓取，也可从剪贴板或手动粘贴保存。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 只露出前 8 位，避免把账号级标识完整铺在界面上。
  String _maskGuid(String guid) =>
      guid.length <= 8 ? guid : '${guid.substring(0, 8)}…';
}

/// 「教务会话」卡 —— 教务登录令牌（JSESSIONID）的探活与手动换票。
///
/// 用户 2026-09-15：要求「在设置里加一个刷新 IMS 登录令牌的按钮」，并裁定语义为
/// **先探活、失效才换**——业务页面遇到「凭证已失效」本来就会自动换票
/// （`ImsAuthInterceptor` → `ImsSession.renew()`），这个按钮是给「怪状态」兜底的
/// 手动通道，不该每次按都白烧一次 CAS 往返。
///
/// 卡片状态全部来自本会话实例（`imsSessionProvider`，切号即重建）：
/// 令牌掩码 / 签发时间 / 失败原因都是**只读展示**，只有按钮会发网络。
class SettingsImsSessionCard extends ConsumerStatefulWidget {
  const SettingsImsSessionCard({super.key});

  @override
  ConsumerState<SettingsImsSessionCard> createState() => SettingsImsSessionCardState();
}

class SettingsImsSessionCardState extends ConsumerState<SettingsImsSessionCard> {
  bool _busy = false;
  bool _loading = true;
  ImsProbeResult? _probe;
  String? _error;
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocal());
  }

  /// 首屏只读本地（内存 → 磁盘）令牌：**一个请求都不发，更不会顺手换票**
  /// （`ensureReady()` 在本地没有令牌时会走 CAS 换票，打开设置页不该触发登录）。
  Future<void> _loadLocal() async {
    await ref.read(imsSessionProvider).peek();
    if (mounted) setState(() => _loading = false);
  }

  /// 按一下按钮：探活 → 只有「失效 / 本机没有 / 判不出」才换票。
  Future<void> _refresh() async {
    final session = ref.read(imsSessionProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    var probe = ImsProbeResult.unknown;
    var success = false;
    try {
      probe = await session.probe();
      if (imsTokenRefreshActionFor(probe) == ImsTokenRefreshAction.renew) {
        await session.renew();
      }
      success = true;
    } catch (e) {
      if (mounted) setState(() => _error = _shortError(e));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _loading = false;
      _probe = probe;
      _checkedAt = DateTime.now();
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(imsRefreshOutcomeText(probe: probe, success: success)),
      ),
    );
  }

  /// 失败原因只给一行，别把整段堆栈铺到卡片上。
  String _shortError(Object e) {
    final text = e.toString().replaceAll('\n', ' ');
    return text.length <= 140 ? text : '${text.substring(0, 140)}…';
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  ({String label, Color tint, Color text}) _status(
    ColorScheme scheme, {
    required bool ready,
    required bool failed,
  }) {
    if (_busy) {
      return (
        label: '刷新中',
        tint: AppColors.tint(context, fp(context).cardAccent, 0.12),
        text: fp(context).cardAccent,
      );
    }
    if (_loading) {
      return (
        label: '读取中',
        tint: AppColors.tint(context, fp(context).cardAccent, 0.12),
        text: fp(context).cardAccent,
      );
    }
    if (ready) {
      return (
        label: '已就绪',
        tint: AppColors.successFill(context),
        text: AppColors.success(context),
      );
    }
    if (failed) {
      return (
        label: '不可用',
        tint: AppColors.statusFill(context, scheme.error),
        text: scheme.error,
      );
    }
    return (
      label: '未就绪',
      tint: scheme.surfaceContainerHighest,
      text: scheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.watch(imsSessionProvider);
    // 切号 = 会话实例重建：卡片上的「最近探活」等本地状态必须跟着清掉。
    ref.listen(imsSessionProvider, (prev, next) {
      if (prev?.account != next.account) {
        setState(() {
          _probe = null;
          _error = null;
          _checkedAt = null;
          _loading = true;
        });
        unawaited(_loadLocal());
      }
    });

    final token = session.jsessionId ?? '';
    final ready = token.isNotEmpty;
    final status = _status(
      scheme,
      ready: ready,
      failed: !ready && session.phase == ImsSessionPhase.failed,
    );
    final issued = session.issuedAt;
    final meta =
        '账号 ${session.account.isEmpty ? '—' : session.account} · '
        '${issued == null ? '签发时间未知（本次启动尚未换票）' : '签发 ${_clock(issued)}'}';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSubLabel(
              icon: Icons.verified_user_outlined,
              title: '教务登录令牌（IMS 会话）',
              subtitle: '成绩 / 课表 / 选课 / 公共查询 共用同一张令牌',
              accent: fp(context).cardAccent,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: status.tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: status.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ready ? '当前：${maskImsToken(token)}' : '本机暂无令牌，点下方按钮获取',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              meta,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            if (_probe != null) ...[
              const SizedBox(height: 2),
              Text(
                '最近探活 ${_clock(_checkedAt ?? DateTime.now())}：'
                '${imsProbeLabel(_probe!)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 2),
              Text(
                '最近一次失败：$_error',
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _refresh,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_busy ? '刷新中…' : '刷新登录令牌'),
              ),
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '点击后先探活：令牌仍有效就只提示、不重复换票；确认失效'
                    '（或本机没有、判不出）才走统一身份认证重新取票并落盘。'
                    '业务页面遇到「凭证已失效」会自动换票重试，平时不必手动点。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
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
