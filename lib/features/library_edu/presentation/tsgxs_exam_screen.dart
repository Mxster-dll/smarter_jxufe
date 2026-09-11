import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_answer_bank.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_clue_sweep.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_chapter_screen.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_clue_sweep_action.dart';
import 'package:smarter_jxufe/features/library_edu/presentation/tsgxs_grade_screen.dart';

/// 入馆教育「闯关答题」页。
///
/// 双模式(用户拍板),**模式只由设置页决定**(`tsgxsExamPrefsProvider`),本页
/// 不提供切换入口(用户 2026-09-11 裁定:「公共模式的切换和后门模式,不应该
/// 显示在任何页面,只能显示在设置页」):
/// - **公共模式**:与网页一致 —— 自己作答,提交后看对错 / 正确答案 / 解析,
///   答错且服务端下发道具时可用道具重答一题;线索未学完时**不代做**,严格
///   要求自己逐条学习(服务端同样会拒绝开考);
/// - **后门模式**:进入时若服务端因线索未学完而拒绝开考,会**自动补全线索**
///   (逐节点 GET 内容页,服务端据此记账),放行后题库优先(命中即自动填入正确
///   答案);「一键探底」自动逐题提交收集答案,若被判闯关失败则**自动重新开考
///   继续探底,直到通过**(带安全轮数上限)。
class TsgxsExamScreen extends ConsumerStatefulWidget {
  final String chapterId;
  final String? chapterTitle;

  /// 进入后自动跑「通过此章节」一键流程(补全线索 → 自动探底)。
  /// 供章节页后门卡片的「通过此章节」直接进入时使用,免去二次点击。
  final bool autoPass;

  /// 本章有结果(通过 / 未通过)后自动 `pop(<是否通过>)`。
  /// 供「一键通过全部章节」逐章接力用:批量页 await 本次 push 的返回值。
  final bool autoPopOnPass;

  /// 探底自动重启的轮数上限(防止服务端始终不放行时无限循环)。
  /// 用户 2026-09-11 定为 10 轮。
  final int maxProbeRounds;

  const TsgxsExamScreen({
    super.key,
    required this.chapterId,
    this.chapterTitle,
    this.autoPass = false,
    this.autoPopOnPass = false,
    this.maxProbeRounds = 10,
  });

  @override
  ConsumerState<TsgxsExamScreen> createState() => _TsgxsExamScreenState();
}

class _TsgxsExamScreenState extends ConsumerState<TsgxsExamScreen> {
  bool _loading = true;
  bool _submitting = false;
  bool _probing = false;

  /// 「通过此章节」一键流程进行中(补全线索 → 自动探底)。
  bool _passing = false;
  String? _error;

  TsgxsExamPage? _page;
  TsgxsExamSession? _session;
  TsgxsQuestion? _question;
  int _index = 0;

  final Set<String> _selected = {};
  final TextEditingController _textCtrl = TextEditingController();

  TsgxsAnswerResult? _result;
  TsgxsExamFinishResult? _finish;

  TsgxsAnswerBank? _bank;
  String? _usedPropId;
  DateTime? _startedAt;
  Timer? _ticker;
  final List<String> _log = [];

  // 后门模式:补全线索(骗服务端)的运行状态。
  bool _sweeping = false;

  /// 本场是否已向服务端提交过作答(决定能否「重开考试记录」自愈)。
  bool _anySubmitted = false;
  int _sweepDone = 0;
  int _sweepTotal = 0;
  TsgxsClueSweepResult? _sweep;
  String? _sweepError;

  @override
  void initState() {
    super.initState();
    unawaited(_bootThenMaybePass());
  }

  /// 启动加载;若是被章节页后门卡片的「通过此章节」带进来的,加载完直接开跑。
  ///
  /// `autoPopOnPass`(「一键通过全部章节」批量接力)时,无论结果如何都回传:
  /// 本章本来就已通过 → `pop(true)`;服务端未放行 / 不是后门模式 → `pop(false)`;
  /// 否则跑完一键通过 → `pop(_finish?.passed == true)`。
  Future<void> _bootThenMaybePass() async {
    await _boot();
    if (!mounted || !widget.autoPass) return;
    if (_page?.passed == true) {
      _popWithResult(true);
      return;
    }
    if (_mode != TsgxsAnswerMode.backdoor || _session == null) {
      _popWithResult(false);
      return;
    }
    await _passChapter(skipConfirm: true);
    if (!mounted) return;
    _popWithResult(_finish?.passed == true);
  }

  /// 批量流程用:把本章结果回传给调用方(未被批量调用时什么都不做)。
  void _popWithResult(bool passed) {
    if (!widget.autoPopOnPass || !mounted) return;
    Navigator.of(context).pop(passed);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  String get _examPageUrl =>
      'http://tsgxs.jxufe.cn/Web/Exam?cid=${widget.chapterId}';

  /// 当前答题模式 —— 唯一来源是设置页维护的全局偏好(本页不提供切换)。
  TsgxsAnswerMode get _mode => ref.read(tsgxsExamPrefsProvider).mode;

  int get _elapsedSeconds {
    final start = _startedAt;
    if (start == null) return 0;
    return DateTime.now().difference(start).inSeconds;
  }

  String get _elapsedLabel {
    final s = _elapsedSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  void _addLog(String line) {
    _log.insert(0, line);
    if (_log.length > 40) _log.removeLast();
  }

  // ---------------- 生命周期 ----------------

  Future<void> _boot({bool allowSweep = true}) async {
    setState(() {
      _loading = true;
      _error = null;
      _finish = null;
      _result = null;
    });
    try {
      _bank ??= await ref.read(tsgxsAnswerBankProvider.future);
      final repo = await ref.read(tsgxsRepositoryProvider.future);
      final account = ref.read(currentAccountProvider);
      final page = await repo.fetchExamPage(
        account,
        chapterId: widget.chapterId,
      );
      _page = page;
      final session = page.session;
      if (page.passed || session == null) {
        // 后门模式:服务端因「线索未学完」拒绝开考时,自动慢速补全线索再重试
        // 一次;普通模式不做这一步(服务端同样拒绝,如实提示用户去学)。
        if (allowSweep && !page.passed && _mode == TsgxsAnswerMode.backdoor) {
          final swept = await _sweepClues(auto: true);
          if (!mounted) return;
          if (swept != null && swept.ok) {
            await _boot(allowSweep: false);
            return;
          }
        }
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      _session = session;
      _startedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      await _loadQuestion(0);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 后门模式:慢速逐节点「打开」本章线索,让服务端把线索记为已学习。
  ///
  /// 返回 null 表示未执行/失败(原因写进 [_sweepError] 与运行记录)。
  Future<TsgxsClueSweepResult?> _sweepClues({bool auto = false}) async {
    if (_sweeping) return null;
    setState(() {
      _sweeping = true;
      _sweepDone = 0;
      _sweepTotal = 0;
      _sweep = null;
      _sweepError = null;
    });
    _addLog(
      auto ? '后门:自动补全本章线索(每线索停留 $tsgxsClueSweepDwellText)…' : '后门:开始补全本章线索…',
    );
    try {
      final result = await runClueSweep(
        ref,
        chapterId: widget.chapterId,
        onProgress: (done, total, _) {
          if (!mounted) return;
          setState(() {
            _sweepDone = done;
            _sweepTotal = total;
          });
          _addLog('已打开线索 $done/$total');
        },
      );
      if (!mounted) return result;
      setState(() {
        _sweeping = false;
        _sweep = result;
      });
      _addLog('补全结果:${result.summary}');
      return result;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _sweeping = false;
        _sweepError = '$e';
      });
      _addLog('补全失败:$e');
      return null;
    }
  }

  /// 后门卡片的主入口「通过此章节」:补全线索 → 确保拿到开考记录 → 自动探底。
  ///
  /// 用户只关心本章通过,过程(逐个打开线索让服务端记账、逐题提交收集答案、
  /// 被判闯关失败后自动重新开考)全部由 App 代劳;任何一步失败都如实写进
  /// [_error] 与运行记录,不做静默重试以外的动作。
  ///
  /// [skipConfirm] = true 时不弹确认框(章节页的「通过此章节」已确认过一次)。
  Future<void> _passChapter({bool skipConfirm = false}) async {
    if (_passing || _probing || _sweeping || _submitting) return;
    final backdoor = _mode == TsgxsAnswerMode.backdoor;
    if (!skipConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.rocket_launch_outlined),
          title: const Text('通过此章节'),
          content: Text(
            'App 会自动完成整章:\n'
            '① 逐个打开本章全部线索(服务端据此放行答题,每线索停留 $tsgxsClueSweepDwellText);\n'
            '② 自动逐题提交,把服务端返回的正确答案逐条存入本地题库;\n'
            '③ 若被判「本章闯关失败」,自动重新开考并继续,直到本章通过(最多 ${widget.maxProbeRounds} 轮)。\n\n'
            '${backdoor ? '当前为后门模式,可一键完成。' : '当前不是后门模式:请到「设置 → 入馆教育」切换后再用本入口。'}',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('开始通过'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _passing = true;
      _error = null;
      _finish = null;
      _sweepError = null;
    });
    _addLog('后门:一键通过本章(补全线索 → 自动探底)…');

    // ① 补全线索(已学完时这一步秒过)。
    final swept = await _sweepClues(auto: true);
    if (!mounted) return;
    if (swept == null || !swept.ok) {
      setState(() {
        _passing = false;
        _error = '本章线索未放行,答题尚未开放:${_sweepError ?? swept?.summary ?? '未知原因'}';
      });
      _addLog('一键通过中止:线索补全未放行');
      return;
    }

    // ② 确保已经有开考记录(线索刚补完时上一份记录多半是空的)。
    if (_session == null) {
      final ok = await _reopenExamRecord();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _passing = false;
          _error = '答题尚未放行:重新开考失败,请稍后再试一次';
        });
        return;
      }
    }

    setState(() => _passing = false);
    // ③ 自动探底:内部自带「失败 → 重新开考 → 继续」循环,直到通过。
    await _probeAll(skipConfirm: true);
  }

  /// 是否允许「重开考试记录」自愈:仅本场第 1 题、且还没提交过任何答案时。
  /// 答题中途重开会丢掉服务端已记录的作答,故不允许。
  bool _canRecoverExam(int i) =>
      i == 0 && _index == 0 && _result == null && !_anySubmitted;

  /// 重新打开答题页换取新的开考记录与题目(自愈用)。
  Future<bool> _reopenExamRecord() async {
    _addLog('题目不在当前开考记录里,重新开考取新题…');
    try {
      final repo = await ref.read(tsgxsRepositoryProvider.future);
      final account = ref.read(currentAccountProvider);
      final page = await repo.fetchExamPage(
        account,
        chapterId: widget.chapterId,
      );
      _page = page;
      final session = page.session;
      if (session == null) {
        _addLog('重新开考失败:答题页没给题目清单');
        return false;
      }
      _session = session;
      _startedAt = DateTime.now();
      _addLog('已重新开考:本次共 ${session.questionIds.length} 题');
      return true;
    } catch (e) {
      _addLog('重新开考失败:$e');
      return false;
    }
  }

  Future<void> _loadQuestion(int i) async {
    final session = _session;
    if (session == null) return;
    final questionId = session.questionIds[i];
    final repo = await ref.read(tsgxsRepositoryProvider.future);
    final account = ref.read(currentAccountProvider);
    TsgxsQuestion question;
    try {
      question = await repo.fetchExamQuestion(
        account,
        questionId: questionId,
        examPageUrl: _examPageUrl,
      );
    } on TsgxsApiException catch (e) {
      // 服务端对「不属于当前开考记录的题目 id」返回 200 + text/html 的 500
      // 错误页(实测)。本场尚未提交任何答案、且是第 1 题时,重开一次考试记录
      // 拿新题再试;已在答题中途则原样抛出,免得丢掉已提交的作答。
      if (!_canRecoverExam(i) || !'$e'.contains('不是 JSON')) rethrow;
      final recovered = await _reopenExamRecord();
      if (!recovered) rethrow;
      question = await repo.fetchExamQuestion(
        account,
        questionId: _session!.questionIds[i],
        examPageUrl: _examPageUrl,
      );
    }
    _selected.clear();
    _textCtrl.clear();
    _result = null;
    _usedPropId = null;
    _index = i;
    _question = question;

    if (_mode == TsgxsAnswerMode.backdoor) {
      final entry = _bank?.entryFor(questionId);
      if (entry != null && entry.answer.trim().isNotEmpty) {
        if (question.kind.isText) {
          _textCtrl.text = entry.answer;
        } else {
          for (final id in entry.optionIds) {
            if (question.optionById(id) != null) _selected.add(id);
          }
        }
        _addLog(
          '第 ${i + 1} 题:题库命中,已自动填入'
          '${entry.codes.isEmpty ? '答案' : entry.codes.join('、')}',
        );
      } else {
        _addLog('第 ${i + 1} 题:题库无记录');
      }
    }
    if (mounted) setState(() {});
  }

  // ---------------- 作答 ----------------

  String get _answerPayload {
    final question = _question;
    if (question == null) return '';
    if (question.kind.isText) return _textCtrl.text.trim();
    return _selected.join(',');
  }

  /// 提交一题;成功返回服务端结果,失败置 [_error] 并返回 null。
  Future<TsgxsAnswerResult?> _sendAnswer({
    required TsgxsQuestion question,
    required String answer,
    String? helpId,
  }) async {
    final session = _session;
    if (session == null) return null;
    try {
      final repo = await ref.read(tsgxsRepositoryProvider.future);
      final account = ref.read(currentAccountProvider);
      final res = await repo.submitAnswer(
        account,
        questionId: question.id,
        answer: answer,
        chapterId: session.chapterId,
        examRecordDetailsId: session.examRecordDetailsId,
        spendtime: _elapsedSeconds,
        helpId: helpId,
        examPageUrl: _examPageUrl,
      );
      // 本场已向服务端提交过作答:此后不允许「重开考试记录」自愈(会丢作答)。
      _anySubmitted = true;
      if (res.correctRaw.trim().isNotEmpty) {
        final codes = question.kind.isText
            ? const <String>[]
            : question
                  .codesOf(
                    res.correctRaw
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty),
                  )
                  .split('、')
                  .where((e) => e.isNotEmpty)
                  .toList();
        await _bank?.record(
          TsgxsBankEntry(
            questionId: question.id,
            answer: res.correctRaw,
            codes: codes,
            kind: question.kind.name,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
        _addLog(
          '第 ${_index + 1} 题:正确答案已入库'
          '${codes.isEmpty ? '' : '(${codes.join('、')})'}',
        );
      }
      return res;
    } catch (e) {
      setState(() => _error = '$e');
      return null;
    }
  }

  Future<void> _submit() async {
    final question = _question;
    if (question == null || _submitting || _probing) return;
    final answer = _answerPayload;
    if (answer.isEmpty) {
      _toast(question.kind.isText ? '请填写答案' : '请选择答案');
      return;
    }
    setState(() => _submitting = true);
    final res = await _sendAnswer(
      question: question,
      answer: answer,
      helpId: _usedPropId,
    );
    setState(() {
      _submitting = false;
      if (res != null) _result = res;
      _usedPropId = null;
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    });
    if (res != null && res.chapterPassed) {
      _toast('本关已通过');
    }
  }

  /// 使用道具重答:清掉上一次评分,允许修改本题答案后再次提交。
  void _useProp(TsgxsExamProp prop) {
    setState(() {
      _usedPropId = prop.id;
      _result = null;
    });
    _addLog('使用道具「${prop.title}」,本题可重答一次');
    _toast('已选择道具「${prop.title}」,修改答案后再次提交');
  }

  Future<void> _next() async {
    final session = _session;
    if (session == null) return;
    if (_index + 1 < session.questionIds.length) {
      setState(() => _submitting = true);
      try {
        await _loadQuestion(_index + 1);
      } catch (e) {
        setState(() => _error = '$e');
      }
      setState(() => _submitting = false);
      return;
    }
    await _settle();
  }

  Future<void> _settle() async {
    final session = _session;
    if (session == null) return;
    setState(() => _submitting = true);
    try {
      final repo = await ref.read(tsgxsRepositoryProvider.future);
      final account = ref.read(currentAccountProvider);
      final res = await repo.finishExam(
        account,
        examRecordDetailsId: session.examRecordDetailsId,
        chapterId: session.chapterId,
        spendtime: _elapsedSeconds,
        examPageUrl: _examPageUrl,
      );
      _addLog(
        '结算:Success=${res.success}${res.message.isEmpty ? '' : ' ${res.message}'}',
      );
      ref.invalidate(tsgxsExamStatusProvider(widget.chapterId));
      ref.invalidate(tsgxsGradesProvider);
      ref.invalidate(tsgxsChaptersProvider);
      ref.invalidate(tsgxsHomeProvider);
      if (mounted) setState(() => _finish = res);
    } catch (e) {
      setState(() => _error = '$e');
    }
    setState(() => _submitting = false);
  }

  // ---------------- 后门模式:一键探底 ----------------

  /// 一键探底:逐题提交收集答案。
  ///
  /// **后门模式**:若本轮被判「本章闯关失败」/未走完,自动重新开考(必要时先补全
  /// 线索)继续探底,直到通过;最多重启 [TsgxsExamScreen.maxProbeRounds] 轮,避免服务端始终不放行
  /// 时无限循环。**公共模式**:一旦失败立即停止(与网页一致,不代做)。
  ///
  /// [skipConfirm] = true 时不再弹确认框(由「通过此章节」流程在入口确认一次)。
  Future<void> _probeAll({bool skipConfirm = false}) async {
    final session = _session;
    if (session == null || _probing || _submitting) return;
    final backdoor = _mode == TsgxsAnswerMode.backdoor;
    if (!skipConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('一键探底'),
          content: Text(
            '将自动从当前题开始逐题提交(题库里没有的题用第一个选项/固定答案试探),'
            '把服务端返回的正确答案逐条存入本地题库。\n\n'
            '注意:错题数由服务端判定。'
            '${backdoor ? '后门模式下若被判「本章闯关失败」,会自动重新开考并继续探底,'
                      '直到通过(最多 ${widget.maxProbeRounds} 轮重启);已收集的答案会保留。' : '公共模式下若被判「本章闯关失败」会立即停止探底,已收集的答案会保留。'}',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(backdoor ? '开始探底(自动重试)' : '开始探底'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _probing = true;
      _error = null;
      _finish = null;
    });
    var collected = 0;
    var restarts = 0;
    var round = 0;
    String? stopReason;
    while (mounted) {
      round++;
      final current = _session;
      if (current == null) {
        stopReason = '答题记录已失效,请退出后重新进入';
        break;
      }
      if (round > 1) _addLog('第 $round 轮探底开始(重新开考)…');
      var roundFailed = false;
      var aborted = false;
      String? roundStop;
      for (var i = _index; i < current.questionIds.length; i++) {
        if (!mounted) {
          aborted = true;
          break;
        }
        try {
          await _loadQuestion(i);
          final question = _question;
          if (question == null) {
            roundStop = '第 ${i + 1} 题加载失败';
            aborted = true;
            break;
          }
          final entry = _bank?.entryFor(question.id);
          String answer;
          if (entry != null && entry.answer.trim().isNotEmpty) {
            answer = entry.answer;
          } else if (question.kind.isText) {
            answer = '探底';
          } else if (question.options.isNotEmpty) {
            answer = question.options.first.id;
          } else {
            roundStop = '第 ${i + 1} 题无法自动作答(${question.kind.label})';
            aborted = true;
            break;
          }
          final res = await _sendAnswer(question: question, answer: answer);
          if (res == null) {
            roundStop = '第 ${i + 1} 题提交失败,已停止探底';
            aborted = true;
            break;
          }
          if (res.correctRaw.trim().isNotEmpty) collected++;
          setState(() => _result = res);
          if (res.isRestart) {
            roundFailed = true;
            break;
          }
          if (!res.graded) {
            if (res.chapterPassed) {
              // 服务端认为本关已通过 → 交由下方收尾判定。
              aborted = true;
              break;
            }
            roundStop =
                '服务端返回异常:${res.message.isEmpty ? 'Success=${res.success}' : res.message}';
            aborted = true;
            break;
          }
        } catch (e) {
          roundStop = '$e';
          aborted = true;
          break;
        }
      }

      final answeredAll =
          !aborted &&
          !roundFailed &&
          _index + 1 >= current.questionIds.length &&
          (_result?.graded ?? false);
      if (answeredAll) await _settle();
      if (!mounted) break;
      if (_finish?.passed ?? false) break; // 本关已通过

      if (!backdoor) {
        stopReason =
            roundStop ??
            (roundFailed
                ? '服务端判定本章闯关失败 —— 已停止探底,本次收集 $collected 题正确答案'
                : '本轮未走完,已停止探底');
        break;
      }

      // 后门模式:未通过 → 自动重新开考继续探底,直到通过或用完重启轮数。
      restarts++;
      if (restarts > widget.maxProbeRounds) {
        stopReason =
            '已自动重启 ${widget.maxProbeRounds} 轮仍未通过,停止探底'
            '(本次收集 $collected 题正确答案)';
        break;
      }
      _addLog('本轮未通过,自动重启答题(第 $restarts/${widget.maxProbeRounds} 次重试)…');
      _index = 0;
      _result = null;
      _anySubmitted = false;
      _session = null;
      _question = null;
      var ok = await _reopenExamRecord();
      if (!ok) {
        _addLog('重新开考被拒(线索可能被重置),先补全线索再试…');
        final swept = await _sweepClues(auto: true);
        if (swept != null && swept.ok) ok = await _reopenExamRecord();
        if (!ok) {
          stopReason = '重新开考失败,已停止自动重启';
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _probing = false;
      if (stopReason != null) _error = stopReason;
    });
  }

  // ---------------- UI ----------------

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 订阅全局偏好:设置页把模式改成后门/公共后,本页立即跟随(不需要重进)。
    final mode = ref.watch(tsgxsExamPrefsProvider).mode;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.chapterTitle == null ? '闯关答题' : '${widget.chapterTitle} · 闯关',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              children: [
                if (_error != null) ...[
                  _errorCard(scheme, _error!),
                  const SizedBox(height: 12),
                ],
                if (_page?.passed == true && _session == null)
                  _passedCard(scheme)
                else if (_session == null)
                  _noticeCard(
                    scheme,
                    '暂时无法开始答题',
                    _page?.message.isNotEmpty == true
                        ? _page!.message
                        : '答题页没返回题目清单。若线索尚未全部学完,请先回章节把线索看完。',
                  )
                else if (_finish != null)
                  _finishCard(scheme, _finish!)
                else ...[
                  _headerCard(scheme),
                  const SizedBox(height: 12),
                  if (_question != null) _questionCard(scheme, _question!),
                  const SizedBox(height: 12),
                  if (_result != null) _feedbackCard(scheme, _result!),
                  if (_result == null) _submitRow(scheme),
                ],
                if (mode == TsgxsAnswerMode.backdoor) ...[
                  const SizedBox(height: 12),
                  _backdoorCard(scheme),
                ],
              ],
            ),
    );
  }

  Widget _card(ColorScheme scheme, List<Widget> children) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _headerCard(ColorScheme scheme) {
    final session = _session!;
    final question = _question;
    return _card(scheme, [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '第 ${_index + 1}/${session.questionIds.length} 题',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (question != null)
            Text(
              question.kindName.isEmpty
                  ? question.kind.label
                  : question.kindName,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          const Spacer(),
          Icon(Icons.timer_outlined, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            _elapsedLabel,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(
        value: session.questionIds.isEmpty
            ? 0
            : (_index + (_result?.graded == true ? 1 : 0)) /
                  session.questionIds.length,
        minHeight: 4,
      ),
    ]);
  }

  Widget _questionCard(ColorScheme scheme, TsgxsQuestion question) {
    final locked = _result != null && _usedPropId == null;
    return _card(scheme, [
      Text(
        question.content,
        style: const TextStyle(
          fontSize: 14.5,
          height: 1.6,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (question.answerTip.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          question.answerTip.trim(),
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (question.kind.isText)
        TextField(
          controller: _textCtrl,
          enabled: !locked && !_probing,
          maxLines: question.kind == TsgxsQuestionKind.copy ? 4 : 1,
          decoration: InputDecoration(
            labelText: question.kind == TsgxsQuestionKind.copy
                ? '抄写答案'
                : '填写答案',
            border: const OutlineInputBorder(),
          ),
        )
      else
        for (final option in question.options) ...[
          _optionTile(scheme, question, option, locked),
          const SizedBox(height: 6),
        ],
    ]);
  }

  Widget _optionTile(
    ColorScheme scheme,
    TsgxsQuestion question,
    TsgxsExamOption option,
    bool locked,
  ) {
    final selected = _selected.contains(option.id);
    final multi = question.kind == TsgxsQuestionKind.multi;
    return Container(
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: locked || _probing
            ? null
            : () => setState(() {
                if (multi) {
                  if (!_selected.remove(option.id)) _selected.add(option.id);
                } else {
                  _selected
                    ..clear()
                    ..add(option.id);
                }
              }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                multi
                    ? (selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank)
                    : (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                size: 18,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                '${option.code}.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.primary : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  option.content.trim(),
                  style: const TextStyle(fontSize: 13.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submitRow(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: (_submitting || _probing) ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(_usedPropId == null ? '提交答案' : '提交答案(已用道具)'),
          ),
        ),
      ],
    );
  }

  Widget _feedbackCard(ColorScheme scheme, TsgxsAnswerResult result) {
    if (result.chapterPassed) {
      return _noticeCard(
        scheme,
        '本关已通过',
        '服务端提示:${result.message.isEmpty ? '本关已通过' : result.message}',
      );
    }
    if (!result.graded) {
      return _noticeCard(
        scheme,
        '提交未生效',
        result.message.isEmpty
            ? '服务端返回 Success=${result.success}'
            : result.message,
      );
    }
    final question = _question;
    final correctText = result.correctRaw.trim();
    final correctCodes = question == null || correctText.isEmpty
        ? ''
        : (question.kind.isText
              ? correctText
              : question.codesOf(
                  correctText
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty),
                ));
    final ok = result.isCorrect;
    final color = ok ? const Color(0xFF0F7B0F) : scheme.error;
    return _card(scheme, [
      Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            ok ? '回答正确' : '回答错误',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const Spacer(),
          if (result.isRestart)
            Text(
              '本章闯关失败',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.error,
              ),
            ),
        ],
      ),
      if (correctCodes.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          '正确答案:$correctCodes',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
      if (result.analysis.trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          '解析:${result.analysis.trim()}',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 12),
      if (result.isRestart)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回章节(需重新学习线索)'),
          ),
        )
      else if (!ok && result.myProps.isNotEmpty && _usedPropId == null) ...[
        Text(
          '可用道具重获一次答题机会:',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prop in result.myProps)
              OutlinedButton.icon(
                onPressed: () => _useProp(prop),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text('用「${prop.title}」重答'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: _next,
                child: Text(
                  _index + 1 >= (_session?.questionIds.length ?? 1)
                      ? '不用道具,结算'
                      : '不用道具,下一题',
                ),
              ),
            ),
          ],
        ),
      ] else
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _submitting ? null : _next,
                icon: Icon(
                  _index + 1 >= (_session?.questionIds.length ?? 1)
                      ? Icons.flag_outlined
                      : Icons.arrow_forward,
                ),
                label: Text(
                  _index + 1 >= (_session?.questionIds.length ?? 1)
                      ? '结算本关'
                      : '下一题',
                ),
              ),
            ),
          ],
        ),
    ]);
  }

  /// 后门模式「补全线索」的**进度/状态显示**(按钮已收拢到「通过此章节」)。
  ///
  /// 实测:服务端在 GET 内容页时即记账线索已学习,没有独立的标记已学接口;
  /// 因此逐个打开内容页即可让服务端放行答题(普通模式不做此步)。
  Widget _clueSweepProgress(ColorScheme scheme) {
    final result = _sweep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.auto_fix_high_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            const Text(
              '自动补全线索',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (_session == null && _page?.passed != true)
              Text(
                '答题未放行',
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '服务端在「打开线索内容页」时就记账已学习。后门模式会逐个打开一遍'
          '(每线索停留 $tsgxsClueSweepDwellText),让它认为本章线索已学完;普通模式不做这步。',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (_sweeping) ...[
          LinearProgressIndicator(
            value: _sweepTotal == 0 ? null : _sweepDone / _sweepTotal,
            minHeight: 3,
          ),
          const SizedBox(height: 6),
          Text(
            _sweepTotal == 0
                ? '正在打开第 1 个线索…'
                : '已打开 $_sweepDone/$_sweepTotal 个线索…',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ] else if (_sweepError != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 15, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '补全失败:$_sweepError',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          )
        else if (result != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.ok ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 15,
                color: result.ok ? const Color(0xFF0F7B0F) : scheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.summary,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: result.ok ? const Color(0xFF0F7B0F) : scheme.error,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _backdoorCard(ColorScheme scheme) {
    final bankCount = _bank?.count ?? 0;
    return _card(scheme, [
      Row(
        children: [
          Icon(Icons.vpn_key_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          const Text(
            '后门模式',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '题库 $bankCount 题',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '点一次「通过此章节」,App 会自动补全线索 → 自动逐题探底收集答案;'
        '若被判「本章闯关失败」会自动重新开考继续,直到本章通过。\n'
        '题库优先:命中的题直接答对(答案来自服务端每次下发,跨账号共享)。\n'
        '答题模式在「设置 → 入馆教育」切换,本页不再提供切换入口。',
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
      const SizedBox(height: 12),
      _clueSweepProgress(scheme),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: (_passing || _probing || _sweeping || _submitting)
            ? null
            : _passChapter,
        icon: (_passing || _probing)
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.rocket_launch_outlined),
        label: Text(_passing ? '正在补全线索…' : (_probing ? '正在自动探底…' : '通过此章节')),
      ),
      if (_log.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '运行记录',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        for (final line in _log.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '· $line',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ]);
  }

  Widget _finishCard(ColorScheme scheme, TsgxsExamFinishResult result) {
    final passed = result.passed;
    final color = passed ? const Color(0xFF0F7B0F) : scheme.error;
    return _card(scheme, [
      Row(
        children: [
          Icon(
            passed ? Icons.emoji_events_outlined : Icons.replay_outlined,
            size: 22,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              passed ? '本关已通过' : (result.needRestart ? '需重新闯关' : '未能通关'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
      if (result.message.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          result.message.trim(),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (result.props.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          '获得道具:${result.props.map((p) => p.title).join('、')}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回章节'),
            ),
          ),
          if (passed && result.nextChapterId != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        TsgxsChapterScreen(chapterId: result.nextChapterId!),
                  ),
                ),
                child: const Text('下一章'),
              ),
            ),
          ],
        ],
      ),
      if (passed) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TsgxsGradeScreen())),
          icon: const Icon(Icons.assessment_outlined, size: 16),
          label: const Text('查看我的成绩'),
        ),
      ],
    ]);
  }

  Widget _passedCard(ColorScheme scheme) => _card(scheme, [
    Row(
      children: [
        const Icon(Icons.verified_outlined, size: 20, color: Color(0xFF0F7B0F)),
        const SizedBox(width: 8),
        const Text(
          '本章考试已通过',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      '已通过的章节不能重复开考(学校未开放重考接口)。成绩见「入馆教育成绩」。',
      style: TextStyle(
        fontSize: 12.5,
        height: 1.6,
        color: scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回章节'),
          ),
        ),
        if (_page?.nextChapterId != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      TsgxsChapterScreen(chapterId: _page!.nextChapterId!),
                ),
              ),
              child: const Text('下一章'),
            ),
          ),
        ],
      ],
    ),
  ]);

  Widget _noticeCard(ColorScheme scheme, String title, String body) =>
      _card(scheme, [
        Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ]);

  Widget _errorCard(ColorScheme scheme, String message) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: scheme.error.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12.5, height: 1.6, color: scheme.error),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _error = null),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
