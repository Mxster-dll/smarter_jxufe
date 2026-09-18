/// 学科竞赛详情页（申请详情 / 公示详情共用）。
///
/// 官网两个详情页都是只读表单（`<label>` + `input[readonly]`），所以这里统一渲染成
/// 「字段行」列表；证书附件用 `openImg_lx('<url>')` 的地址，点开交给系统浏览器。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/competition_repository.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_widgets.dart';

/// 详情加载器（申请 / 公示各一个）。
typedef CompetitionDetailLoader =
    Future<CompetitionDetail> Function(
      CompetitionRepository repository,
      String account,
    );

class CompetitionDetailScreen extends ConsumerStatefulWidget {
  const CompetitionDetailScreen({
    super.key,
    required this.title,
    required this.loader,
    this.summary,
  });

  final String title;
  final CompetitionDetailLoader loader;

  /// 顶部摘要行（比赛名 / 学生 / 时间），列表里已有，这里再摆一次方便对照。
  final Widget? summary;

  @override
  ConsumerState<CompetitionDetailScreen> createState() =>
      _CompetitionDetailScreenState();
}

class _CompetitionDetailScreenState
    extends ConsumerState<CompetitionDetailScreen> {
  CompetitionDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = ref.read(currentAccountProvider);
      if (account.isEmpty) throw Exception('请先登录后再查看');
      final repository = await ref.read(competitionRepositoryProvider.future);
      final detail = await widget.loader(repository, account);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (!mounted) return;
      showCompetitionMessage(context, '打开附件失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CompetitionErrorCard(error: _error!, onRetry: _load),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                if (widget.summary != null) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(kAppCardPadding),
                      child: widget.summary!,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(kAppCardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final field in _detail!.fields)
                          _fieldRow(theme, field),
                        if (_detail!.fields.isEmpty)
                          Text(
                            '这条记录没有可显示的字段。',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_detail!.attachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(kAppCardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '证书附件（${_detail!.attachments.length}）',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final url in _detail!.attachments)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.image_outlined,
                                    size: 16,
                                  ),
                                  label: Text(_attachmentLabel(url)),
                                  onPressed: () => _openAttachment(url),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _fieldRow(ThemeData theme, CompetitionDetailField field) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              field.label,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              field.value.isEmpty ? '—' : field.value,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _attachmentLabel(String url) {
    final name = url.split('/').last;
    return name.isEmpty ? '查看附件' : name;
  }
}

/// 申请详情：官网 `detail.html?id=&code=look`。
CompetitionDetailLoader competitionApplyDetailLoader(int id) =>
    (repository, account) => repository.fetchApplyDetail(account, id: id);

/// 公示详情：官网 `xd_detail.html?id=&code=look&team=`。
CompetitionDetailLoader competitionPublicityDetailLoader(
  int id,
  CompetitionType type,
) =>
    (repository, account) =>
        repository.fetchPublicityDetail(account, id: id, type: type);
