/// 学科竞赛申请表单（官网 `dektSubjectGame/toAdd.html` 的客户端版）。
///
/// 字段与官网一一对应：
/// - 比赛信息（必填）→ `find_game.do` 选择器 → `gameId`；
/// - 类型（必填）= 个人 / 团队 → `type` = 0 / 1；
/// - 获得奖项（必填）→ 选定比赛后按 `getCredit.do` 拉取，值为 `【赛别】奖项名` → `remark`；
/// - 团队成员（团队必填，≥2 人且含本人）→ `team` = 学号分号相连；
/// - 证书图片（必填，jpg/png，单张 ≤3MB）→ 逐张上传拿附件 id → `enclosure` 逗号相连。
///
/// ⚠ **必须前端校验**：官网 `add.do` 不做服务端校验，字段为空也返回「申请成功」而记录
/// 不落库（实测），所以这里比照官网 `checkSubmit` 逐项拦。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/competition_image_picker.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_pickers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_widgets.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';

/// 单张证书上限（官网 `maxFileSize: 3072` KB）。
const int competitionMaxAttachmentBytes = 3072 * 1024;

/// 一次最多上传张数（官网 `maxFileCount: 10`）。
const int competitionMaxAttachments = 10;

/// 团队申请最少成员数（官网 `checkSubmit`：不能少于两个人）。
const int competitionMinTeamMembers = 2;

class CompetitionApplyFormScreen extends ConsumerStatefulWidget {
  const CompetitionApplyFormScreen({super.key});

  @override
  ConsumerState<CompetitionApplyFormScreen> createState() =>
      _CompetitionApplyFormScreenState();
}

class _CompetitionApplyFormScreenState
    extends ConsumerState<CompetitionApplyFormScreen> {
  CompetitionGame? _game;
  CompetitionType _type = CompetitionType.individual;
  String? _awardRemark;
  final _members = <CompetitionStudent>[];
  final _images = <CompetitionAttachment>[];
  bool _busy = false;
  bool _selfBusy = false;

  /// 把「自己」加进团队：官网要求申请人自己也要算成员，但 `team` 存的是**内部 id**
  /// （radio value），只有从学生列表里查一次才能拿到 —— 所以这里按学号搜自己。
  Future<void> _addSelf() async {
    setState(() => _selfBusy = true);
    try {
      final account = ref.read(currentAccountProvider);
      if (account.isEmpty) throw Exception('请先登录后再申请');
      final infoRepository = await ref.read(
        studentInfoRepositoryProvider.future,
      );
      final info = infoRepository.getCachedStudentInfo().fold(
        (_) => null,
        (value) => value,
      );
      final serialNo = info?.serialNo ?? '';
      if (serialNo.isEmpty) throw Exception('读不到学籍学号，请手动搜索添加');
      final repository = await ref.read(competitionRepositoryProvider.future);
      final page = await repository.fetchStudents(account, studentId: serialNo);
      CompetitionStudent? me;
      for (final student in page.items) {
        if (student.studentId == serialNo) {
          me = student;
          break;
        }
      }
      if (me == null) {
        throw Exception('成员列表里没搜到 $serialNo，请手动搜索添加');
      }
      if (!mounted) return;
      final found = me;
      setState(() {
        if (_members.every((m) => m.rowId != found.rowId)) {
          _members.add(found);
        }
      });
    } catch (error) {
      if (!mounted) return;
      showCompetitionMessage(context, '加自己失败：$error');
    } finally {
      if (mounted) setState(() => _selfBusy = false);
    }
  }

  Future<void> _pickGame() async {
    final game = await showCompetitionGamePicker(context);
    if (game == null || !mounted) return;
    setState(() {
      _game = game;
      // 换比赛必须重选奖项：奖项随比赛变化。
      _awardRemark = null;
    });
  }

  Future<void> _addMembers() async {
    final picked = await showCompetitionStudentPicker(
      context,
      excludeStudentIds: [for (final m in _members) m.studentId],
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final student in picked) {
        if (_members.every((m) => m.rowId != student.rowId)) {
          _members.add(student);
        }
      }
    });
  }

  Future<void> _addImages(CompetitionImageSource source) async {
    if (_images.length >= competitionMaxAttachments) {
      showCompetitionMessage(context, '最多上传 $competitionMaxAttachments 张证书图片');
      return;
    }
    try {
      final picked = await ref
          .read(competitionImagePickerProvider)
          .pick(source);
      if (picked.isEmpty || !mounted) return;
      final accepted = <CompetitionAttachment>[];
      var tooLarge = 0;
      for (final image in picked) {
        if (image.sizeInBytes > competitionMaxAttachmentBytes) {
          tooLarge++;
          continue;
        }
        if (_images.length + accepted.length >= competitionMaxAttachments) {
          break;
        }
        accepted.add(image);
      }
      setState(() => _images.addAll(accepted));
      if (tooLarge > 0) {
        showCompetitionMessage(
          context,
          '有 $tooLarge 张超过 ${competitionAttachmentSize(competitionMaxAttachmentBytes)}，已跳过',
        );
      }
    } catch (error) {
      if (!mounted) return;
      showCompetitionMessage(context, '选择图片失败：$error');
    }
  }

  Future<void> _submit() async {
    final game = _game;
    if (game == null) {
      showCompetitionMessage(context, '请选择比赛');
      return;
    }
    final remark = _awardRemark;
    if (remark == null || remark.isEmpty) {
      showCompetitionMessage(context, '请选择获得奖项');
      return;
    }
    if (_images.isEmpty) {
      showCompetitionMessage(context, '请上传证书图片（原件或扫描件）');
      return;
    }
    if (_type == CompetitionType.team &&
        _members.length < competitionMinTeamMembers) {
      showCompetitionMessage(
        context,
        '团队申请成员不能少于 $competitionMinTeamMembers 人（申请人自己也要加进来）',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final account = ref.read(currentAccountProvider);
      if (account.isEmpty) throw Exception('请先登录后再申请');
      final repository = await ref.read(competitionRepositoryProvider.future);
      final attachmentIds = <int>[];
      for (final image in _images) {
        attachmentIds.add(await repository.uploadAttachment(account, image));
      }
      final message = await repository.submitApply(
        account,
        gameId: game.id,
        remark: remark,
        type: _type,
        // ⚠ 官网 team 字段存的是成员**内部 id**（radio value），不是学号。
        memberIds: [for (final m in _members) m.teamValue],
        attachmentIds: attachmentIds,
      );
      if (!mounted) return;
      showCompetitionMessage(context, message);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showCompetitionMessage(context, '提交失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = _game;
    return Scaffold(
      appBar: AppBar(title: const Text('申请竞赛'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          _card(theme, '比赛信息', [
            InkWell(
              onTap: _busy ? null : _pickGame,
              borderRadius: BorderRadius.circular(kAppCardRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game?.name ?? '点击选择比赛',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: game == null
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          if (game != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (game.year.isNotEmpty) game.year,
                                if (game.level.isNotEmpty) game.level,
                                if (game.college.isNotEmpty)
                                  '对接：${game.college}',
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            Text(
              '比赛目录有 ${200}+ 页，请用关键词搜索（如「数学建模」「程序设计」）。',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _card(theme, '类型', [
            SegmentedButton<CompetitionType>(
              segments: const [
                ButtonSegment(
                  value: CompetitionType.individual,
                  label: Text('个人'),
                ),
                ButtonSegment(value: CompetitionType.team, label: Text('团队')),
              ],
              selected: {_type},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() => _type = selection.first),
            ),
            if (_type == CompetitionType.team) ...[
              const SizedBox(height: 10),
              Text(
                '团队由一个人提交（请不要重复提交相同的奖项），成员按团队排名添加，'
                '申请人自己也要加进来，至少 $competitionMinTeamMembers 人。',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ]),
          if (_type == CompetitionType.team) ...[
            const SizedBox(height: 12),
            _card(theme, '团队成员（${_members.length}）', [
              if (_members.isEmpty)
                Text(
                  '还没添加成员',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final member in _members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${member.name} · ${member.studentId} · ${member.className}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _members.removeWhere(
                                  (m) => m.rowId == member.rowId,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addMembers,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('添加成员'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _busy || _selfBusy ? null : _addSelf,
                    icon: _selfBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_outline, size: 18),
                    label: const Text('加自己'),
                  ),
                ],
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _awardCard(theme, game),
          const SizedBox(height: 12),
          _attachmentCard(theme),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_busy ? '提交中…' : '提交申请'),
          ),
          const SizedBox(height: 8),
          Text(
            '提交后由学院 / 校团委审批，进度在「我的申请」里看（未审批 = 还没审）。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _awardCard(ThemeData theme, CompetitionGame? game) {
    if (game == null) {
      return _card(theme, '获得奖项', [
        Text(
          '先选择比赛，再选奖项。',
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ]);
    }
    final async = ref.watch(competitionAwardsProvider(game.id));
    return _card(theme, '获得奖项', [
      async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(minHeight: 3),
        ),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '奖项加载失败：$error',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () =>
                  ref.invalidate(competitionAwardsProvider(game.id)),
              child: const Text('重试'),
            ),
          ],
        ),
        data: (awards) {
          if (awards.isEmpty) {
            return Text(
              '这场比赛还没有配置奖项，请联系校团委。',
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          final options = <String, String>{
            for (final award in awards)
              award.remarkFor(game): competitionAwardLabel(award, game),
          };
          final value = options.containsKey(_awardRemark) ? _awardRemark : null;
          return DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '选择奖项',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in options.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (picked) => setState(() => _awardRemark = picked),
          );
        },
      ),
    ]);
  }

  Widget _attachmentCard(ThemeData theme) {
    final picker = ref.watch(competitionImagePickerProvider);
    return _card(theme, '证书图片（${_images.length}/$competitionMaxAttachments）', [
      Text(
        '请上传原件或扫描件（jpg / png，单张 ≤'
        '${competitionAttachmentSize(competitionMaxAttachmentBytes)}）。',
        style: TextStyle(
          fontSize: 11.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 10),
      if (_images.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _images.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _images[i].bytes,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, _) => Container(
                        width: 76,
                        height: 76,
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_outlined, size: 20),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () => setState(() => _images.removeAt(i)),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xB3000000),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(
                          Icons.close,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _addImages(CompetitionImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('相册'),
          ),
          if (picker.supportsCamera)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _addImages(CompetitionImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('拍照'),
            ),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _addImages(CompetitionImageSource.files),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('文件'),
          ),
        ],
      ),
    ]);
  }

  Widget _card(ThemeData theme, String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(kAppCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}
