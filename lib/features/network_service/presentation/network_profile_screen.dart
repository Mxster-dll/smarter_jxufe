import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_actions.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_common.dart';

/// 账号设置：详细资料（联系电话 / 电子邮箱 / 账单地址 / 单位）与修改上网密码。
///
/// ⚠ 身份证号（`userIdNumber`）是只读的系统字段，页面只展示不改；上网密码修改
/// 需要「原密码 + 新密码」（6–16 位，不能含空格），与自助服务系统同校验口径。
class NetworkProfileScreen extends ConsumerStatefulWidget {
  const NetworkProfileScreen({super.key});

  @override
  ConsumerState<NetworkProfileScreen> createState() =>
      _NetworkProfileScreenState();
}

class _NetworkProfileScreenState extends ConsumerState<NetworkProfileScreen> {
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();

  /// 是否已用服务端数据初始化过输入框（只在首次拿到数据时回填，避免覆盖用户输入）。
  bool _filled = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  void _fillOnce(NetworkAccount account) {
    if (_filled) return;
    _filled = true;
    _phoneCtrl.text = '';
    _emailCtrl.text = '';
    _addressCtrl.text = '';
    _companyCtrl.text = '';
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(networkAccountProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('账号设置'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(networkAccountProvider);
          await ref.read(networkAccountProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            accountAsync.when(
              loading: () => networkLoadingCard(context),
              error: (error, _) => networkErrorCard(
                context,
                error,
                onRetry: () => ref.invalidate(networkAccountProvider),
              ),
              data: (account) {
                _fillOnce(account);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    networkSectionTitle(context, '账号信息'),
                    const SizedBox(height: 8),
                    networkCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          networkInfoRow(
                            context,
                            label: '上网账号',
                            value: account.userName,
                          ),
                          networkInfoRow(
                            context,
                            label: '姓名',
                            value: account.realName,
                          ),
                          networkInfoRow(
                            context,
                            label: '证件号码',
                            value: _maskId(account.idNumber),
                          ),
                          networkInfoRow(
                            context,
                            label: '当前套餐',
                            value: account.planName,
                          ),
                          if (account.expireAt != null)
                            networkInfoRow(
                              context,
                              label: '失效日期',
                              value: networkFormatDate(account.expireAt),
                            ),
                          networkInfoRow(
                            context,
                            label: '在线设备',
                            value:
                                '${account.ipCount} / ${account.ipMaxCount} 台'
                                '${account.multiLogin ? '（允许多终端）' : '（单终端）'}',
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '证件号码由学校统一维护，App 内不可修改。',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            networkSectionTitle(context, '联系方式'),
            const SizedBox(height: 8),
            networkCard(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '用于自助服务系统的资料与通知；留空表示不修改该项。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(_phoneCtrl, '联系电话', Icons.phone_outlined),
                  const SizedBox(height: 10),
                  _field(
                    _emailCtrl,
                    '电子邮箱',
                    Icons.mail_outline,
                    keyboard: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 10),
                  _field(_addressCtrl, '账单地址', Icons.home_outlined),
                  const SizedBox(height: 10),
                  _field(_companyCtrl, '单位 / 院系', Icons.business_outlined),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('netsvc_profile_save'),
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('保存资料'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            networkSectionTitle(context, '上网密码'),
            const SizedBox(height: 8),
            networkCard(
              context,
              padding: EdgeInsets.zero,
              child: networkRecordTile(
                context,
                icon: Icons.lock_outline,
                title: '修改上网密码',
                subtitle: '6–16 位数字或英文，不能包含空格；修改后需重新认证',
                trailing: '修改',
                onTap: _changePassword,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: label,
      isDense: true,
      prefixIcon: Icon(icon, size: 18),
      border: const OutlineInputBorder(),
    ),
  );

  /// 证件号只展示前后各 3 位（页面里不做完整展示）。
  String _maskId(String id) {
    if (id.isEmpty) return '';
    if (id.length <= 8) return id;
    return '${id.substring(0, 3)}****${id.substring(id.length - 4)}';
  }

  Future<void> _save() async {
    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(ref).updateProfile(
        guid,
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        company: _companyCtrl.text.trim(),
      ),
      successFallback: '资料已保存',
      invalidate: () => ref.invalidate(networkAccountProvider),
    );
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: const Text('修改上网密码'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('netsvc_pwd_old'),
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '原密码',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? '请输入原密码' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('netsvc_pwd_new'),
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码（6–16 位）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final text = v ?? '';
                    if (text.length < 6 || text.length > 16) {
                      return '新密码需 6–16 位';
                    }
                    if (text.contains(' ')) return '新密码不能包含空格';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('netsvc_pwd_confirm'),
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '确认新密码',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == newCtrl.text ? null : '两次输入的密码不一样',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('确定修改'),
          ),
        ],
      ),
    );

    final oldPwd = oldCtrl.text;
    final newPwd = newCtrl.text;
    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();

    if (confirmed != true || !mounted) return;
    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(
        ref,
      ).changePassword(guid, oldPassword: oldPwd, newPassword: newPwd),
      successFallback: '密码修改成功，请用新密码重新认证',
    );
  }
}
