import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/my_mail/data/providers/my_mail_providers.dart';
import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/design/app_theme.dart';

/// 我的邮箱：学校学生邮箱的**账号 + 初始密码**，均可一键复制。
///
/// 数据源 = 门户 `GET /platForm/api/wx/email/getPwd?username=<GUID>`
/// （小程序里这一页叫「邮箱密码」，App 侧只做只读展示，见 [StudentMailbox] 注释）。
class MyMailScreen extends ConsumerStatefulWidget {
  const MyMailScreen({super.key});

  @override
  ConsumerState<MyMailScreen> createState() => _MyMailScreenState();
}

class _MyMailScreenState extends ConsumerState<MyMailScreen> {
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _refresh,
  );

  /// 密码默认掩码（小程序「邮箱密码」页同款：点眼睛才明文）。
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoRefresh.subscribeRoute(context);
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    invalidateIfLoaded(ref, myMailboxProvider);
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('已复制$label'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mailboxAsync = ref.watch(myMailboxProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('我的邮箱'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: PaneBody(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 2),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myMailboxProvider);
            await ref.read(myMailboxProvider.future).catchError(
              (Object _) => StudentMailbox.empty,
            );
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
            children: [
              ...mailboxAsync.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ],
                error: (e, _) => [
                  _errorCard(context, scheme, e),
                  const SizedBox(height: 12),
                  _hintCard(context, scheme),
                ],
                data: (mailbox) => [
                  _accountCard(context, scheme, mailbox),
                  const SizedBox(height: 12),
                  _passwordCard(context, scheme, mailbox),
                  const SizedBox(height: 12),
                  _hintCard(context, scheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 卡片 ----------

  Widget _accountCard(
    BuildContext context,
    ColorScheme scheme,
    StudentMailbox mailbox,
  ) {
    return _card(
      context,
      child: Row(
        children: [
          _iconBox(context, scheme, Icons.mark_email_read_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '邮箱账号',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1.0,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  mailbox.email,
                  key: const Key('mymail_email'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('mymail_copy_email'),
            tooltip: '复制邮箱',
            onPressed: () => _copy(mailbox.email, '邮箱'),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _passwordCard(
    BuildContext context,
    ColorScheme scheme,
    StudentMailbox mailbox,
  ) {
    return _card(
      context,
      child: Row(
        children: [
          _iconBox(context, scheme, Icons.key_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '初始密码',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1.0,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  _revealed ? mailbox.password : mailbox.maskedPassword,
                  key: const Key('mymail_password'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('mymail_reveal'),
            tooltip: _revealed ? '隐藏密码' : '显示密码',
            onPressed: () => setState(() => _revealed = !_revealed),
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
            ),
          ),
          IconButton(
            key: const Key('mymail_copy_password'),
            tooltip: '复制初始密码',
            onPressed: () => _copy(mailbox.password, '初始密码'),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _hintCard(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '邮箱账号 = 学号 @ stu.jxufe.edu.cn，初始密码由学校邮件系统下发；'
              '若你已自行改过邮箱密码，这里显示的仍是初始密码。\n'
              '邮箱 Web 入口（mail.jxufe.edu.cn）目前仅校园网可达，本页只做账号信息展示。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, ColorScheme scheme, Object error) {
    final message = error is Exception
        ? error.toString().replaceFirst('Exception: ', '')
        : '$error';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tint(context, scheme.error, 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.tintBorder(context, scheme.error, 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => myMailNeedsGuid(error)
                  ? Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GuidGuideScreen(),
                      ),
                    )
                  : _refresh(),
              icon: Icon(
                myMailNeedsGuid(error)
                    ? Icons.add_link_outlined
                    : Icons.refresh_outlined,
                size: 16,
              ),
              label: Text(myMailNeedsGuid(error) ? '去获取平台标识' : '重试'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 通用小块 ----------

  Widget _card(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        side: appCardBorderSide(scheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    );
  }

  Widget _iconBox(BuildContext context, ColorScheme scheme, IconData icon) {
    final accent = FeatureColors.forBrightness(scheme.brightness).myMail;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.tint(context, accent, 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 21, color: accent),
    );
  }
}
