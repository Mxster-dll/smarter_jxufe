import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/storage/local_data_revision.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';
import 'package:smarter_jxufe/features/tice/data/providers/tice_providers.dart';
import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';
import 'package:smarter_jxufe/features/tice/data/tice_stu_num.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_tip_data.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_weights.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/rule_tip.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/volunteer_bar.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/weight_sheet.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/shared/widgets/count_stepper.dart';

/// 综合测评 · 自动测算（单页）。
///
/// 页面版式参照《2026 综测计算器.html》：五育分卡（编号分区 + 实时徽章），
/// 底部「班级排名估计」卡决定单项等次；配色统一到 App 主题、控件全部换
/// 成 App 风格。材料加分来自共享数据源 [zcMaterialsProvider]（材料库维护），
/// 教务加权 / 第二课堂志愿自动带入，评议 / 体测 / 排名手动填写（标注预估）。
///
/// 两种自动源都**按测评学年**取数（用户 2026-09-16 裁定「综测按学年算」）：
/// 课程加权限定学期码落在该学年的课程，志愿时长限定活动日期落在学年窗口
/// （`[y-1]-09-01 ~ [y]-08-31`）的活动 —— 与材料「按盖章时间归入学年」同一口径。
class ZongceScreen extends ConsumerStatefulWidget {
  const ZongceScreen({super.key});

  @override
  ConsumerState<ZongceScreen> createState() => _ZongceScreenState();
}

class _ZongceScreenState extends ConsumerState<ZongceScreen> {
  /// 学年选择器可回溯的学年数（当前测评学年往前 [zcYearWindow] 个）。
  static const int zcYearWindow = 5;

  late int _year;
  bool _ready = false;
  ZcManual _manual = const ZcManual();
  ZcStore? _store;
  String? _loadError;

  /// 学年选择器是否被鼠标悬停（悬停展开时把左侧说明淡出，避免年份溢出的
  /// 数字压在文字上）。
  bool _pickerHovered = false;

  // ---- 体测成绩自动获取（赛康体测平台，仅当用户未手动编辑时回填）----
  bool _ticeBusy = false; // 自动查询进行中
  bool _ticeTouched = false; // 本学年用户已手动编辑体测分数（防覆盖）
  String? _ticeNote; // 输入行来源提示（busy/成功/失败/已手填）

  /// 五育语义色（同原网页：德红 / 智蓝 / 体绿 / 美紫 / 劳青）。
  static const _yuColors = <String, Color>{
    'd': Color(0xFFC42B1C),
    'z': Color(0xFF0078D4),
    't': Color(0xFF0F7B0F),
    'm': Color(0xFF744DA9),
    'l': Color(0xFF0F766E),
  };

  /// 材料类型 → 条款依据规则点（材料行悬停显示分值表，便于核对加分口径）。
  static const _materialRuleIds = <ZcTypeId, List<String>>{
    ZcTypeId.deed: ['r22'],
    ZcTypeId.eduCon: ['r23'],
    ZcTypeId.eduPart: ['r24'],
    ZcTypeId.servicePost: ['r27', 'r25', 'r26'],
    ZcTypeId.honorP: ['r28'],
    ZcTypeId.honorG: ['r29', 'r30'],
    ZcTypeId.contest: ['r77', 'r37', 'r38', 'r39', 'r40', 'r41'],
    ZcTypeId.paper: ['r42', 'r43'],
    ZcTypeId.foreign: ['r44'],
    ZcTypeId.startup: ['r45'],
    ZcTypeId.sportComp: ['r54'],
    ZcTypeId.psych: ['r55'],
    ZcTypeId.sportTeam: ['r56'],
    ZcTypeId.artsComp: ['r60'],
    ZcTypeId.media: ['r61'],
    ZcTypeId.artAct: ['r62'],
    ZcTypeId.social: ['r67'],
    ZcTypeId.laborAct: ['r68'],
    ZcTypeId.dorm: ['r69'],
  };

  @override
  void initState() {
    super.initState();
    _year = zcDefaultYear(DateTime.now());
    _init();
  }

  Future<void> _init() async {
    try {
      final store = await ref.read(zcStoreProvider.future);
      final manual = await store.loadManual(_year);
      if (!mounted) return;
      setState(() {
        _store = store;
        _manual = manual;
        _ready = true;
      });
      _autoTice();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '存储初始化失败：$e';
        _ready = true;
      });
    }
  }

  /// 从赛康体测平台自动获取体测成绩并回填（默认值；用户手动改过则不覆盖）。
  ///
  /// 综测 [yearEnd] 学年的体测在上一学年秋季窗口完成（如 2025-2026 学年的
  /// 体测 = 2025 年秋季 = 窗口年 [_year] - 1）。
  Future<void> _autoTice() async {
    if (!_ready) return;
    final yearEnd = _year;
    setState(() {
      _ticeBusy = true;
      _ticeNote = '正在从体测平台自动获取成绩…';
    });
    String? note;
    try {
      final stuNum = await resolveTiceStuNum(ref);
      if (stuNum.isEmpty) {
        note = '未取得学号，请手动填写体测成绩';
      } else {
        final result = await ref
            .read(ticeRemoteDataSourceProvider)
            .query(stuNum, yearEnd - 1);
        final score = result.ok && result.years.isNotEmpty
            ? result.years.last.totalScore
            : null;
        if (score == null) {
          note = '自动获取未命中（${result.message}），请手动填写或勾选免测';
        } else if (_ticeTouched) {
          note = '检测到体测成绩 ${_fmt(score)} 分（已手动填写，未覆盖）';
        } else if (_manual.tMian) {
          note = '检测到体测成绩 ${_fmt(score)} 分（当前勾选免测，可取消后自动填入）';
        } else {
          _updateManual(
            _manual.copyWith(tScore: score.clamp(0, 100).toDouble()),
          );
          note = '已自动获取 ${yearEnd - 1} 学年体测成绩 ${_fmt(score)} 分 · 可手动修改';
        }
      }
    } on TiceRequestException catch (e) {
      note = '自动获取失败（${e.message}），请手动填写';
    } catch (_) {
      note = '自动获取失败，请手动填写体测成绩';
    }
    if (!mounted || yearEnd != _year) return; // 学年已切换则丢弃
    setState(() {
      _ticeBusy = false;
      _ticeNote = note;
    });
  }

  /// 体测分数被手动编辑：本学年停止自动回填。
  void _markTiceManual() {
    if (_ticeTouched) return;
    setState(() {
      _ticeTouched = true;
      _ticeNote = null;
    });
  }

  void _updateManual(ZcManual m) {
    setState(() => _manual = m);
    final store = _store;
    if (store != null) {
      store.saveManual(_year, m).catchError((Object e) {
        debugPrint('[ZC] save manual failed: $e');
      });
    }
  }

  /// **全页统一刷新**（用户 2026-09-18：「体测成绩、加权成绩都不显示输入框和
  /// 刷新按钮，而是改成全页统一的刷新按钮」）—— 三条自动源一起重取，字段级
  /// 刷新按钮已全部撤掉。
  void _refreshAll() {
    // 加权：先失效底层成绩列表（成绩页可能刚查过新成绩），再失效本学年派生值。
    ref.invalidate(gePriorGradesProvider);
    ref.invalidate(zcAutoWeightProvider(_year));
    // 志愿时长：底层是第二课堂活动列表（联网，会话失效会自动重建）。
    ref.invalidate(volunteerActivitiesProvider);
    ref.invalidate(zcAutoVolunteerProvider(_year));
    // 体测：走本页 State 的自动获取（不经过 provider）。
    unawaited(_autoTice());
  }

  /// 云同步「从云端恢复」改了本机落盘的手册条目 → 重读一次
  /// （只动手册那一份内存副本，不碰体测 / 志愿的自动源）。
  Future<void> _reloadManual() async {
    final store = _store;
    if (store == null) return;
    final manual = await store.loadManual(_year);
    if (!mounted) return;
    setState(() => _manual = manual);
  }

  Future<void> _loadYear(int year) async {
    final store = _store;
    final manual = store == null
        ? const ZcManual()
        : await store.loadManual(year);
    if (!mounted) return;
    setState(() {
      _year = year;
      _manual = manual;
      _ticeTouched = false; // 新学年：重新允许自动回填
      _ticeNote = null;
    });
    _autoTice();
  }

  // ---------- 工具 ----------

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// 加权成绩保留 2 位（用户 2026-09-17：「综测页智育用的加权成绩保留 2 位」）。
  String _fmt2(double v) => v.toStringAsFixed(2);

  Color _gradeColor(BuildContext context, ZcGrade g) {
    switch (g) {
      case ZcGrade.ok:
        return const Color(0xFF00A870);
      case ZcGrade.good:
        return const Color(0xFF2F7BFF);
      case ZcGrade.pass:
        return const Color(0xFFED7B2F);
      case ZcGrade.fail:
        return const Color(0xFFE5484D);
    }
  }

  Color get _schemeColor => Theme.of(context).colorScheme.primary;

  /// 从计分明细按前缀求合计（徽章数值的权威来源，含 cap/取最高等引擎规则）。
  double _sumDetail(ZcCalcResult r, List<String> prefixes) {
    var s = 0.0;
    for (final d in r.details) {
      for (final p in prefixes) {
        if (d.label.startsWith(p)) {
          s += d.value;
          break;
        }
      }
    }
    return s;
  }

  // ---------- 主构建 ----------

  @override
  Widget build(BuildContext context) {
    // 云同步「从云端恢复」整体改写了本机落盘 → 重读手册条目
    // （本页的手册是**读进 State** 的，box 变了它不会自己知道）。
    ref.listen(localDataRevisionProvider, (_, _) => unawaited(_reloadManual()));
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('综合测评'),
        centerTitle: false,
        // 全页统一刷新（用户 2026-09-18：「体测成绩、加权成绩都不显示输入框和
        // 刷新按钮，而是改成全页统一的刷新按钮」）→ 字段级刷新按钮全部撤掉。
        actions: [
          IconButton(
            tooltip: '刷新数据',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_loadError!, style: TextStyle(color: scheme.error)),
        ),
      );
    }

    // 证明材料来自共享数据源（材料库独立维护，增删改后 invalidate 重算）。
    final matsAsync = ref.watch(zcMaterialsProvider);
    final all = matsAsync.value ?? const <ZcMaterial>[];
    // 材料**不分学年**（用户 2026-09-17：「所有的材料本身不分学年，只手动填入
    // 时间」）→ 全部材料都计入；学年只用于自动源（下面两个 provider 的参数）。
    final mats = all;
    // 自动源也按**测评学年**取（用户 2026-09-16 裁定「综测按学年算」）：
    // 参数 = 学年结束年，与材料归属同一窗口。
    final weightAsync = ref.watch(zcAutoWeightProvider(_year));
    final volAsync = ref.watch(zcAutoVolunteerProvider(_year));
    final autoWeight = weightAsync.value;
    final autoVol = volAsync.value;

    final result = zcCalculate(
      mats,
      manual: _manual,
      autoWeight: autoWeight,
      autoVolunteer: autoVol,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
      children: [
        _buildYearBar(context),
        if (matsAsync.isLoading || matsAsync.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              matsAsync.hasError ? '证明材料加载失败，本次测算不含材料加分' : '证明材料加载中…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: matsAsync.hasError ? scheme.error : scheme.outline,
              ),
            ),
          )
        else
          const SizedBox(height: 6),
        const SizedBox(height: 8),
        _buildResultCard(context, result, mats),
        const SizedBox(height: 14),
        _buildYuCardDe(context, result, mats),
        const SizedBox(height: 12),
        _buildYuCardZhi(context, result, mats, weightAsync.isLoading),
        const SizedBox(height: 12),
        _buildYuCardTi(context, result, mats),
        const SizedBox(height: 12),
        _buildYuCardMei(context, result, mats),
        const SizedBox(height: 12),
        _buildYuCardLao(context, result, mats, autoVol),
        const SizedBox(height: 12),
        _buildRankCard(context),
        const SizedBox(height: 12),
        _buildNoteCard(context),
      ],
    );
  }

  /// 全应用统一的学年选择器（用户 2026-09-18：「综测的年份切换要使用我们的
  /// 『学年选择器』」）—— 取代原先的两个 `chevron_left/right` 图标按钮。
  ///
  /// 范围 = 当前测评学年往前 [zcYearWindow] 个学年，**不允许选未来学年**
  /// （还没到的学年没有测评意义）。
  Widget _buildYearBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final endYear = zcDefaultYear(DateTime.now());
    final startYear = endYear - zcYearWindow;
    return Row(
      children: [
        Expanded(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: _pickerHovered ? 0.0 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '测评学年',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '9 月起测评上一学年（材料按盖章时间归档）',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
        ),
        AcademicYearPicker(
          key: const Key('zcYearPicker'),
          startYear: startYear,
          endYear: endYear,
          initialYear: _year.clamp(startYear, endYear),
          onChanged: _loadYear,
          onHoverChanged: (v) => setState(() => _pickerHovered = v),
        ),
      ],
    );
  }

  // ===================================================================
  // 顶部：测评结果（原网页「结果侧栏」语义，单列时置顶常驻）
  // ===================================================================
  /// 总评成绩（五育加权）：点胶囊就地改占比（用户 2026-09-18 拍板的入口）。
  Future<void> _editWeights(ZcWeights current) async {
    final next = await showZcWeightSheet(context, weights: current);
    if (next == null || !mounted) return;
    _updateManual(_manual.copyWith(weights: next));
  }

  Widget _buildResultCard(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final avg = r.average;
    final rows = [
      ('德育', r.deyu, r.gD),
      ('智育', r.zhiyu, r.gZ),
      ('体育', r.tiyu, r.gT),
      ('美育', r.meiyu, r.gM),
      ('劳育', r.laoyu, r.gL),
    ];
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, scheme.primary, 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.assessment_outlined,
                  color: scheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelTip(
                      context,
                      '测评结果',
                      tipKey: 'overall',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '填写/录入后自动计算，实时更新',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              _gradeChip(context, r.overall, big: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (final it in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                it.$1,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.outline,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${_fmt(it.$2)} 分',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: _gradeColor(
                                  context,
                                  it.$3,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                it.$3.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _gradeColor(context, it.$3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 总评成绩 = 五育加权（用户 2026-09-18：「综测不是直接算平均分，
                  // 而是有一个总评成绩，这个成绩的占比由班主任定，应该让用户自行
                  // 设置」）→ 点胶囊弹占比设置；平均分降级为下面那行小字。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '总评成绩',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      KeyedSubtree(
                        key: const Key('zcTotalChip'),
                        child: _valueTap(
                          context,
                          text: '${_fmt2(r.total)} 分',
                          onTap: () => _editWeights(r.weights),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '占比 ${r.weights.label}',
                    key: const Key('zcTotalWeightsLabel'),
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
                  const SizedBox(height: 4),
                  _statLine(
                    '五育平均',
                    '${_fmt(avg)} 分',
                    context: context,
                  ),
                  const SizedBox(height: 4),
                  _statLine(
                    '加权成绩',
                    r.weightMissing ? '未获取' : '${_fmt2(r.weightUsed)} 分',
                    context: context,
                  ),
                  const SizedBox(height: 4),
                  _statLine('材料条数', '${mats.length} 条', context: context),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statLine(
    String label,
    String value, {
    required BuildContext context,
    bool emphasize = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 16 : 12.5,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: emphasize ? _schemeColor : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _gradeChip(BuildContext context, ZcGrade g, {bool big = false}) {
    final color = _gradeColor(context, g);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 14 : 8,
        vertical: big ? 6 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(context, color, 0.12),
        borderRadius: BorderRadius.circular(big ? 10 : 6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '综合等次',
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
          ),
          Text(
            g.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: big ? 16 : 11,
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // 五育卡公共件
  // ===================================================================

  /// 育卡外框：白卡 + 语义色图标头 + 实时分数徽章。
  Widget _yuCard(
    BuildContext context, {
    required String dim,
    required IconData icon,
    required String name,
    required String meta,
    required double score,
    required ZcGrade grade,
    required List<Widget> sections,
    String? headerTipKey,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = _yuColors[dim] ?? scheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 卡片头（同原网页 .card>header）
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.tint(context, color, 0.045),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: AppColors.tintBorder(context, color, 0.16)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, color, 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _labelTip(
                        context,
                        name,
                        tipKey: headerTipKey,
                        tipColor: color,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        meta,
                        style: TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                // 实时分数徽章（同原网页 header .live）
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(score),
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        ' 分 · ${grade.label}',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sections,
            ),
          ),
        ],
      ),
    );
  }

  /// 把若干个条款点 key 合成一个悬停按钮的内容（同一行既挂分区点又挂行点）。
  List<String> _tipIdsOf(List<String> keys) => [
    for (final k in keys) ...?zcTipRefs[k],
  ];

  /// 行首：标签文字 + **紧跟在文字右侧**的条款依据悬停按钮。
  ///
  /// 用户 2026-09-18：「对于综测页所有的悬浮提示位置都改到左端文本的右侧旁」——
  /// 从前 `Row([Expanded(Text(label)), RuleTip, …])` 会把 `?` 推到整行最右端，
  /// 与它解释的文字隔了半屏。统一改用本件：`Row(min, [Flexible(Text), ?])`
  /// 套在 `Expanded(child: Align(centerLeft, …))` 里 —— 文字与 `?` 贴在一起、
  /// 整体靠左，行尾的分值 / 控件仍在最右侧。
  Widget _labelTip(
    BuildContext context,
    String label, {
    String? tipKey,
    List<String>? tipIds,
    TextStyle? style,
    Color? tipColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, style: style)),
        if (tipKey != null) RuleTip(tipKey: tipKey, color: tipColor, size: 13.5),
        if (tipKey == null && tipIds != null && tipIds.isNotEmpty)
          RuleTip(ids: tipIds, color: tipColor, size: 13.5),
      ],
    );
  }

  /// 胶囊内的数值文字（`_valueTap` 的自适应 / 定宽两个分支共用）。
  Widget _valueTapText(String text, ColorScheme scheme, bool muted) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: muted ? scheme.outline : scheme.primary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  /// 数值胶囊（`_subRow` 的 trailing）——基础分这类不可改的分数用它。
  ///
  /// 用户 2026-09-18 四轮：「我希望显示胶囊而不是卡片，就和其他部分的加分汇总
  /// 一样」→ 与分区徽章 [._badge] **同款**：主色淡底（`AppColors.tint` 0.09）
  /// + 圆角 999 + 主色 w700 字。旧的「圆角 8 + 细描边方框」（看着像卡片）已弃用。
  Widget _staticChip(BuildContext context, String text, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: AppColors.tint(context, c, 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: c,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// 单行分区（用户 2026-09-18：「基础分、民主评议分都只显示一行内容，都只有一个
  /// 标题行，标题行最右侧显示分数，然后评议分点击可修改」）。
  ///
  /// 行 = 序号圆块 + 标题 +「紧跟标题的条款按钮」+ 最右端的 [trailing]
  /// （`60 分` 这样的胶囊，或可点的 `_tapNumber`）。
  ///
  /// ⚠ 这一行**不挂任何纯文字 Tooltip**（用户 2026-09-18 四轮：「我希望只有悬浮在
  /// 指定区域的悬浮提示，没有另一个悬浮提示……那种卡片式的悬浮提示保留」）——
  /// 「思想端正、遵纪守法……即认定」这类说明文字已整体撤掉，悬停只剩标题右侧的
  /// `?`（[RuleTip] 卡片）。
  Widget _subRow(
    BuildContext context,
    int? no,
    String title, {
    String? tipKey,
    List<String>? tipIds,
    Color? color,
    required Widget trailing,
  }) {
    final c = color ?? _schemeColor;
    final row = Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          // 序号方块；`no == null` 时同一 18px 槽位里画一个小圆点 —— 用于「挂在
          // 分区下面、但不需要单独编号」的行（如劳育「志愿服务时长」）。
          SizedBox(
            width: 18,
            height: 18,
            child: no == null
                ? Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$no',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _labelTip(
                context,
                title,
                tipKey: tipKey,
                tipIds: tipIds,
                tipColor: c,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
    return row;
  }

  /// 分区标题（同原网页 .subhead：序号圆块 + 名称 + 可选徽章/右侧提示）。
  Widget _sub(
    BuildContext context,
    int no,
    String title, {
    Widget? badge,
    String? tip,
    String? tipKey,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? _schemeColor;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Text(
              '$no',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _labelTip(
                context,
                title,
                tipKey: tipKey,
                tipColor: c,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ?badge,
          if (tip != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                tip,
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  /// 徽章（同原网页 .sub-badge：蓝底圆角胶囊；负值红、满值绿）。
  Widget _badge(BuildContext context, String text, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.tint(context, c, 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// 一个编辑行：label（可选实时分值）+ 控件（输入 + 右侧灰规则说明）。
  /// [tipKey] 非空时在标题行尾加「条款依据」悬停按钮。
  Widget _editRow(
    BuildContext context,
    String label, {
    String? scoreText,
    Color? scoreColor,
    String? tipKey,
    required Widget child,
    String? note,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _labelTip(
                    context,
                    label,
                    tipKey: tipKey,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  ),
                ),
              ),
              if (scoreText != null)
                Text(
                  scoreText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scoreColor ?? _schemeColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              child,
              if (note != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.outline,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 智育「加分项」的一个小项（用户 2026-09-18：四类分开显示）。
  ///
  /// 行 = 小项名 + 条款依据悬停 + 该小项分值；下面接该小项的材料行，
  /// 一条都没有时给「去材料库录入」入口。**分值一律取引擎明细**
  /// （`智育 · 学科竞赛`/`智育 · 论文/专利`/`智育 · 外语`/`智育 · 创业`），
  /// 界面层不重算 —— 四小项之和 == 加分项总徽章 `extra`。
  Widget _extraItem(
    BuildContext context, {
    required String label,
    required double value,
    required List<String> tipIds,
    required List<ZcMaterial> items,
    Set<String> highlightIds = const <String>{},
    Set<String> dimmedIds = const <String>{},
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _labelTip(
                    context,
                    label,
                    tipIds: tipIds,
                    tipColor: scheme.primary,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value > 0 ? '+${_fmt(value)} 分' : '0 分',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: value > 0 ? scheme.primary : scheme.outline,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            _goMaterials(context, text: '暂无该小项证明 · 去材料库录入')
          else
            for (final x in items)
              _matRow(
                context,
                x,
                highlighted: highlightIds.contains(x.id),
                dimmed: dimmedIds.contains(x.id),
              ),
        ],
      ),
    );
  }

  /// 「点击才输入」的数值件（用户 2026-09-18：「民主评议也改成点击才输入」）。
  ///
  /// 页面上**不再常驻输入框**：数值本身是可点的胶囊，点开才弹输入框。
  /// 次数类字段另走 `CountStepper`（左右三角增减 + 点数字输入）。
  Widget _valueTap(
    BuildContext context, {
    required String text,
    required VoidCallback onTap,
    String? tag,
    bool muted = false,
    double? width,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fixed = width != null;
    final accent = muted ? scheme.outline : scheme.primary;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        // 用户 2026-09-18 四轮：与「加分汇总」徽章同款（主色淡底 + 999 圆角），
        // 且**不再挂纯文字 Tooltip** —— 悬停提示只保留标题右侧 `?` 的条款卡片，
        // 可点性由胶囊里的铅笔图标表达。
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
          decoration: BoxDecoration(
            color: AppColors.tint(context, accent, 0.09),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            // 自适应宽度（width == null）时 Row 收缩到内容宽 —— 胶囊贴合文字，
            // 与只读的 `_staticChip` 观感一致；定宽时仍用 Expanded 把尾巴推右。
            mainAxisSize: fixed ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (fixed)
                Expanded(child: _valueTapText(text, scheme, muted))
              else
                _valueTapText(text, scheme, muted),
              if (tag != null) ...[
                const SizedBox(width: 6),
                _sourceTag(context, tag),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.edit_outlined,
                size: 13,
                color: accent.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「自动 / 手动」小标（让用户一眼看出这个值是不是自动带入的）。
  Widget _sourceTag(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        // 叠在同为主色淡底的数值胶囊上，0.10 会看不见 → 加深到 0.22。
        color: AppColors.tint(context, scheme.primary, 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }

  /// 非空数值字段（评议分 / 体测分）：点击 → 弹输入框。
  Widget _tapNumber(
    BuildContext context, {
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 20,
    bool integer = false,
    String? display,
    String? note,
    double? width,
  }) {
    return _valueTap(
      context,
      text: display ?? (integer ? value.round().toString() : _fmt(value)),
      width: width,
      tag: note,
      muted: value <= 0,
      onTap: () async {
        final out = await promptNumberValue(
          context,
          title: '输入$label',
          label: label,
          initial: value,
          min: min,
          max: max,
          integer: integer,
          helper: '范围 ${_fmt(min)} ~ ${_fmt(max)}',
        );
        if (out.confirmed && !out.cleared && out.value != null) {
          onChanged(out.value!);
        }
      },
    );
  }

  /// 可空数值字段（加权成绩 / 志愿时长）：手动值 null = 用自动值。
  Widget _tapNumberOpt(
    BuildContext context, {
    required String label,
    required double? value,
    required double? autoValue,
    required ValueChanged<double?> onChanged,
    double min = 0,
    double max = 100,
    String? display,
    double? width,
  }) {
    final manual = value != null;
    final shown = value ?? autoValue;
    return _valueTap(
      context,
      // 手动值优先显示；没有手动值时才用调用方给的自动值文案（加权要 2 位小数）。
      text: manual
          ? _fmt(value)
          : (display ?? (shown == null ? '未获取' : _fmt(shown))),
      width: width,
      // 用户 2026-09-18 五轮：「加权和体测成绩不要显示『自动』字样」→
      // 自动带入的值**不挂标**，只有手动覆盖时才挂「手动」。
      tag: manual ? '手动' : null,
      muted: shown == null,
      onTap: () async {
        final out = await promptNumberValue(
          context,
          title: '输入$label',
          label: label,
          initial: value ?? autoValue,
          min: min,
          max: max,
          helper: '范围 ${_fmt(min)} ~ ${_fmt(max)}；留空用自动值',
          allowClear: manual,
        );
        if (!out.confirmed) return;
        if (out.cleared) {
          onChanged(null);
        } else if (out.value != null) {
          onChanged(out.value!);
        }
      },
    );
  }

  /// 下拉选择（在有限宽布局中直接用；卡内/Column 全宽安全）。
  Widget _fieldDrop<T>({
    required Key key,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? label,
  }) {
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _check(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    Color? color,
  }) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: value,
      visualDensity: VisualDensity.compact,
      selectedColor: AppColors.tint(context, color ?? _schemeColor, 0.14),
      checkmarkColor: color ?? _schemeColor,
      labelStyle: TextStyle(
        color: value ? (color ?? _schemeColor) : null,
        fontSize: 11.5,
      ),
      onSelected: onChanged,
    );
  }

  /// 材料只读行：名称 + 类型·档位 + 分值（自动来自材料库）。
  ///
  /// [highlighted] = 这一条**最终计入了总分**（用户 2026-09-18：「综测智育竞赛
  /// 加分要把最终贡献分数的项高亮一下」）；[dimmed] = 有分但被上限截掉、没计入。
  Widget _matRow(
    BuildContext context,
    ZcMaterial m, {
    bool highlighted = false,
    bool dimmed = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final spec = zcTypeSpecOf[m.typeId];
    final v = zcMaterialValue(m);
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.tint(context, scheme.primary, 0.10)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? scheme.primary.withValues(alpha: 0.55)
              : AppColors.hairline(context, 0.5),
          width: highlighted ? 1.1 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 15, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        // 外语行标题 = **原文条目名**（`大学英语四级 ≥425`），不再
                        // 只显示证书名（用户 2026-09-18：「不能只显示『大学英语四级』
                        // 这样的证书名，要显示原文里『大学英语四级>=425』这样的加分
                        // 条目名」）。认不出（目录外 / 未填分 / 未达门槛）→ 证书名。
                        m.typeId == ZcTypeId.foreign
                            ? (zcForeignEntryLabel(
                                    name: m.name,
                                    rawScore: m.manualScore,
                                  ) ??
                                  m.displayName)
                            : m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    RuleTip(
                      ids: _materialRuleIds[m.typeId],
                      color: scheme.primary,
                      size: 13,
                    ),
                  ],
                ),
                Text(
                  '${spec?.label ?? ''} · ${m.optionLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
                // 竞赛条目补一行备注（用户 2026-09-18：「智育的竞赛条目上也要显示
                // 竞赛的备注信息」）——备注里放的是子项目/赛道/组别（`C++ B组`、
                // `2026 ICPC全国邀请赛（沈阳）`），不显示就分不清同一赛事的几条。
                if (m.typeId == ZcTypeId.contest && m.note.trim().isNotEmpty)
                  Text(
                    m.note.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (v != null)
            Text(
              '+${_fmt(v)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Text('不计', style: TextStyle(fontSize: 11, color: scheme.outline)),
          if (highlighted) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '计入总分',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ] else if (dimmed) ...[
            const SizedBox(width: 6),
            Text(
              '未计入',
              style: TextStyle(fontSize: 9.5, color: scheme.outline),
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// 「去材料库」跳转小按钮（附加分区空态 / 头部管理入口）。
  Widget _goMaterials(BuildContext context, {String text = '去材料库管理'}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MaterialsScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.open_in_new, size: 12, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  // ===================================================================
  // 德育卡
  // ===================================================================
  Widget _buildYuCardDe(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
  ) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final dMats = mats
        .where((x) => zcTypeSpecOf[x.typeId]?.dim == 'd')
        .toList();
    final pingyi = _sumDetail(r, const ['德育 · 民主评议']);
    final extra = _sumDetail(r, const [
      '德育 · 优秀事迹',
      '德育 · 思想教育',
      '德育 · 公共服务',
      '德育 · 荣誉称号',
    ]);
    final kou = _sumDetail(r, const ['德育 · 扣分']);
    return _yuCard(
      context,
      dim: 'd',
      icon: Icons.volunteer_activism_outlined,
      name: '德育素质',
      meta: '60 基础 + 20 评议 + 附加(材料) − 扣分',
      score: r.deyu,
      grade: r.gD,
      headerTipKey: 'sec-deyu',
      sections: [
        // 1 基础分（单行：标题在左、分数在右）
        _subRow(
          context,
          1,
          '基础分',
          tipKey: 'd-1-basic',
          trailing: _staticChip(context, '60 分'),
        ),
        // 2 民主评议（单行：右侧分值可点修改）
        _subRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: _tipIdsOf(const ['sh-d-2', 'd-2-ping']),
          trailing: _tapNumber(
            context,
            label: '民主评议分',
            value: m.deyuPingyi,
            display: '${_fmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(deyuPingyi: v)),
          ),
        ),
        // 3 附加分（材料自动）
        _sub(
          context,
          3,
          '附加分 · 证明材料（自动带入）',
          tipKey: 'sh-d-3',
          badge: extra > 0 ? _badge(context, '+${_fmt(extra)}') : null,
          tip: dMats.isEmpty ? null : '${dMats.length} 条',
        ),
        if (dMats.isEmpty)
          _goMaterials(context, text: '暂无德育证明 · 去材料库录入')
        else
          for (final x in dMats) _matRow(context, x),
        // 4 扣分项
        _sub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _subRow(
          context,
          null,
          '无故缺课',
          tipKey: 'd-4-1',
          trailing: CountStepper(
            label: '缺课节数',
            value: m.kouQk,
            onChanged: (v) => _updateManual(m.copyWith(kouQk: v)),
          ),
        ),
        _subRow(
          context,
          null,
          '无故缺席重大集体活动',
          tipKey: 'd-4-2',
          trailing: CountStepper(
            label: '缺席次数',
            value: m.kouHd,
            onChanged: (v) => _updateManual(m.copyWith(kouHd: v)),
          ),
        ),
        _editRow(
          context,
          '纪律处分',
          tipKey: 'd-4-3',
          child: SizedBox(
            width: 220,
            child: _fieldDrop<int>(
              key: ValueKey('$_year-kou-cf'),
              value: m.kouCf.clamp(0, 3),
              items: const [
                DropdownMenuItem(value: 0, child: Text('无')),
                DropdownMenuItem(value: 1, child: Text('学院通报批评 −2')),
                DropdownMenuItem(value: 2, child: Text('学校警告 −5')),
                DropdownMenuItem(value: 3, child: Text('严重警告 −10')),
              ],
              onChanged: (v) {
                if (v != null) _updateManual(m.copyWith(kouCf: v));
              },
            ),
          ),
        ),
        // 5 一票否决
        _sub(
          context,
          5,
          '一票否决（德育直接评定为不合格）',
          tipKey: 'd-5-veto',
          color: scheme.error,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '受司法/公安处罚、测评弄虚作假、记过以上处分、考试舞弊等',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          value: m.vetoD,
          activeTrackColor: scheme.error.withValues(alpha: 0.6),
          onChanged: (v) => _updateManual(m.copyWith(vetoD: v)),
        ),
      ],
    );
  }

  // ===================================================================
  // 智育卡
  // ===================================================================
  Widget _buildYuCardZhi(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
    bool weightLoading,
  ) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final zMats = mats
        .where((x) => zcTypeSpecOf[x.typeId]?.dim == 'z')
        .toList();
    final extra = _sumDetail(r, const [
      '智育 · 学科竞赛',
      '智育 · 论文/专利',
      '智育 · 外语',
      '智育 · 创业',
    ]);
    final kou = _sumDetail(r, const ['智育 · 扣分']);
    final contestItems = [
      for (final x in zMats)
        if (x.typeId == ZcTypeId.contest) x,
    ];
    final contestCounted = zcContestContributingIds(contestItems);
    return _yuCard(
      context,
      dim: 'z',
      icon: Icons.school_outlined,
      name: '智育素质',
      meta: '加权成绩 + 附加(≤20) − 扣分',
      score: r.zhiyu,
      grade: r.gZ,
      headerTipKey: 'sec-zhiyu',
      sections: [
        // 单行：标题 + 右侧胶囊（点击修改 · 用户 2026-09-18 三轮）
        _subRow(
          context,
          1,
          '加权成绩',
          tipKey: 'z-1-sync',
          trailing: _tapNumberOpt(
            context,
            label: '加权成绩',
            value: m.weight,
            autoValue: r.weightMissing ? null : r.weightUsed,
            max: 100,
            display: weightLoading
                ? '加载中…'
                : (r.weightMissing ? null : _fmt2(r.weightUsed)),
            onChanged: (v) => _updateManual(m.copyWith(weight: () => v)),
          ),
        ),
        if (r.weightMissing)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '本学年未获取到加权成绩（成绩缓存无该学年课程，可手动填写）',
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
        _sub(
          context,
          2,
          '加分项 · 四类各计最高（附加合计 ≤ 20 分）',
          tipKey: 'sh-z-2',
          badge: extra > 0 ? _badge(context, '+${_fmt(extra)}') : null,
          tip: zMats.isEmpty ? null : '${zMats.length} 条',
        ),
        // 用户 2026-09-18：「综测智育加分项分为四部分，我希望你分开显示为四小项」
        // → 四个小项各自出分值（取引擎明细，不重算），下面挂各自的证明材料。
        _extraItem(
          context,
          label: '学科竞赛（表 8）',
          value: _sumDetail(r, const ['智育 · 学科竞赛']),
          tipIds: const ['r77', 'r37'],
          items: contestItems,
          // 用户 2026-09-18：「综测智育竞赛加分要把最终贡献分数的项高亮一下」
          // —— 取引擎同一套 calcJS 口径（最高项 > 5 只计最高，否则累加封顶 5）。
          highlightIds: contestCounted,
          dimmedIds: {
            for (final x in contestItems)
              if (!contestCounted.contains(x.id) &&
                  (zcMaterialValue(x) ?? 0) > 0)
                x.id,
          },
        ),
        _extraItem(
          context,
          label: '论文 / 专利（表 9）',
          value: _sumDetail(r, const ['智育 · 论文/专利']),
          tipIds: const ['r42', 'r43'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.paper) x,
          ],
        ),
        _extraItem(
          context,
          label: '外语能力（表 10）',
          value: _sumDetail(r, const ['智育 · 外语']),
          tipIds: const ['r44'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.foreign) x,
          ],
        ),
        _extraItem(
          context,
          label: '创新创业（表 11）',
          value: _sumDetail(r, const ['智育 · 创业']),
          tipIds: const ['r45'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.startup) x,
          ],
        ),
        _sub(
          context,
          3,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _subRow(
          context,
          null,
          '无故不参加实习实训 / 课外学术创新活动',
          tipKey: 'z-3-1',
          trailing: CountStepper(
            label: '未参加实习实训次数',
            value: m.kouZhiyu,
            onChanged: (v) => _updateManual(m.copyWith(kouZhiyu: v)),
          ),
        ),
        _sub(context, 4, '特殊情况', tipKey: 'z-4-1', color: scheme.error),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '受退学警告 / 毕业当年未获毕业资格（智育直接不合格）',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          value: m.tuixue,
          onChanged: (v) => _updateManual(m.copyWith(tuixue: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            '测评年度有科目考试不及格（智育最高只能认定合格）',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          value: m.guaKe,
          onChanged: (v) => _updateManual(m.copyWith(guaKe: v)),
        ),
      ],
    );
  }

  // ===================================================================
  // 体育卡
  // ===================================================================
  Widget _buildYuCardTi(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
  ) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final tMats = mats
        .where((x) => zcTypeSpecOf[x.typeId]?.dim == 't')
        .toList();
    final extra = _sumDetail(r, const ['体育 · 竞赛/心理/集体']);
    final kou = _sumDetail(r, const ['体育 · 扣分']);
    final ticeNote = _ticeBusy
        ? '正在从体测平台自动获取成绩…'
        : (_ticeNote ?? '由体育学院测试；免测/未测试按 60 分计');
    return _yuCard(
      context,
      dim: 't',
      icon: Icons.fitness_center_outlined,
      name: '体育素质',
      meta: '体测成绩 + 附加(≤20) − 扣分',
      score: r.tiyu,
      grade: r.gT,
      headerTipKey: 'sec-tiyu',
      sections: [
        // 单行：标题 + 右侧胶囊（点击修改 · 用户 2026-09-18 三轮）
        _subRow(
          context,
          1,
          '体测成绩（0~100）',
          tipKey: 't-1-score',
          trailing: _tapNumber(
            context,
            label: '体测成绩',
            value: m.tScore,
            max: 100,
            display: m.tMian ? '60（免测）' : null,
            onChanged: (v) {
              _markTiceManual();
              _updateManual(m.copyWith(tScore: v));
            },
          ),
        ),
        // 体测自动获取的状态说明（用户 2026-09-18 四轮不要纯文字悬停 → 从整行
        // Tooltip 改成行下一行灰字；这条是状态信息，不能丢）。
        Padding(
          padding: const EdgeInsets.only(left: 25, bottom: 4),
          child: Text(
            ticeNote,
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _check('获批免测 / 未测试（按 60 分计）', m.tMian, (v) {
            _updateManual(m.copyWith(tMian: v));
            _autoTice(); // 免测状态变化 → 重新评估自动获取
          }),
        ),
        _sub(
          context,
          2,
          '加分项 · 证明材料',
          tipKey: 'sh-t-2',
          badge: extra > 0 ? _badge(context, '+${_fmt(extra)}') : null,
          tip: tMats.isEmpty ? null : '${tMats.length} 条',
        ),
        if (tMats.isEmpty)
          _goMaterials(context, text: '暂无体育证明 · 去材料库录入')
        else
          for (final x in tMats) _matRow(context, x),
        _sub(
          context,
          3,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _subRow(
          context,
          null,
          '体育活动当众扰乱秩序',
          tipKey: 't-3-1',
          trailing: CountStepper(
            label: '扰乱秩序次数',
            value: m.tKou1,
            onChanged: (v) => _updateManual(m.copyWith(tKou1: v)),
          ),
        ),
        _subRow(
          context,
          null,
          '参赛无故弃权 / 中途退场',
          tipKey: 't-3-2',
          trailing: CountStepper(
            label: '体育弃权次数',
            value: m.tKou2,
            onChanged: (v) => _updateManual(m.copyWith(tKou2: v)),
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // 美育卡
  // ===================================================================
  Widget _buildYuCardMei(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
  ) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final mMats = mats
        .where((x) => zcTypeSpecOf[x.typeId]?.dim == 'm')
        .toList();
    final pingyi = _sumDetail(r, const ['美育 · 民主评议']);
    final extra = _sumDetail(r, const ['美育 · 文艺竞赛/媒体/活动']);
    final kou = _sumDetail(r, const ['美育 · 扣分']);
    return _yuCard(
      context,
      dim: 'm',
      icon: Icons.palette_outlined,
      name: '美育素质',
      meta: '60 基础 + 20 评议 + 附加(材料) − 扣分',
      score: r.meiyu,
      grade: r.gM,
      headerTipKey: 'sec-meiyu',
      sections: [
        _subRow(
          context,
          1,
          '基础分',
          tipKey: 'm-1-basic',
          trailing: _staticChip(context, '60 分'),
        ),
        _subRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: _tipIdsOf(const ['sh-m-2', 'm-2-ping']),
          trailing: _tapNumber(
            context,
            label: '民主评议分',
            value: m.meiyuPingyi,
            display: '${_fmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(meiyuPingyi: v)),
          ),
        ),
        _sub(
          context,
          3,
          '加分项 · 证明材料（文艺竞赛/媒体/活动）',
          tipKey: 'sh-m-3',
          badge: extra > 0 ? _badge(context, '+${_fmt(extra)}') : null,
          tip: mMats.isEmpty ? null : '${mMats.length} 条',
        ),
        if (mMats.isEmpty)
          _goMaterials(context, text: '暂无美育证明 · 去材料库录入')
        else
          for (final x in mMats) _matRow(context, x),
        _sub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _subRow(
          context,
          null,
          '文艺活动当众扰乱秩序',
          tipKey: 'm-4-1',
          trailing: CountStepper(
            label: '文艺扰乱次数',
            value: m.mKou1,
            onChanged: (v) => _updateManual(m.copyWith(mKou1: v)),
          ),
        ),
        _subRow(
          context,
          null,
          '艺术团未满服务期退团',
          tipKey: 'm-4-2',
          trailing: CountStepper(
            label: '退团次数',
            value: m.mKou2,
            onChanged: (v) => _updateManual(m.copyWith(mKou2: v)),
          ),
        ),
        _subRow(
          context,
          null,
          '代表参赛无故弃权 / 中途退场',
          tipKey: 'm-4-3',
          trailing: CountStepper(
            label: '文艺弃权次数',
            value: m.mKou3,
            onChanged: (v) => _updateManual(m.copyWith(mKou3: v)),
          ),
        ),
      ],
    );
  }

  // ===================================================================
  // 劳育卡
  // ===================================================================
  Widget _buildYuCardLao(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
    double? autoVolunteer,
  ) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final lMats = mats
        .where((x) => zcTypeSpecOf[x.typeId]?.dim == 'l')
        .toList();
    final pingyi = _sumDetail(r, const ['劳育 · 民主评议']);
    final volScore = _sumDetail(r, const ['劳育 · 志愿服务']);
    final otherExtra = _sumDetail(r, const ['劳育 · 实践/活动/寝室']);
    final kou = _sumDetail(r, const ['劳育 · 扣分']);
    return _yuCard(
      context,
      dim: 'l',
      icon: Icons.handyman_outlined,
      name: '劳育素质',
      meta: '60 基础 + 20 评议 + 附加(材料) − 扣分',
      score: r.laoyu,
      grade: r.gL,
      headerTipKey: 'sec-laoyu',
      sections: [
        _subRow(
          context,
          1,
          '基础分',
          tipKey: 'l-1-basic',
          trailing: _staticChip(context, '60 分'),
        ),
        _subRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: _tipIdsOf(const ['sh-l-2', 'l-2-ping']),
          trailing: _tapNumber(
            context,
            label: '民主评议分',
            value: m.laoyuPingyi,
            display: '${_fmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(laoyuPingyi: v)),
          ),
        ),
        _sub(
          context,
          3,
          '加分项 · 证明材料',
          tipKey: 'sh-l-3',
          badge: (volScore + otherExtra) > 0
              ? _badge(context, '+${_fmt(volScore + otherExtra)}')
              : null,
          tip: lMats.isEmpty ? null : '${lMats.length} 条',
        ),
        // 志愿服务时长：与基础分/评议分/加权/体测同款的单行胶囊（右侧可点改），
        // 差别只在于**下方多一条按表 18 档位分段的进度条**
        // （用户 2026-09-18：「志愿服务也基本和基本分、评议分、加权/体测成绩一样
        // 显示，唯一不同的是，还要额外在下方显示一个进度条，并根据各级别分段」）。
        // 标题不带「（按表 18 档位换算）」、条下不带任何说明文案
        // （用户同日二轮：「提示文本太多……都要去掉」）。
        _subRow(
          context,
          null,
          '志愿服务时长',
          tipKey: 'l-3-1',
          trailing: _tapNumberOpt(
            context,
            label: '学年志愿时长(h)',
            value: m.volunteerHours,
            autoValue: autoVolunteer,
            max: 500,
            onChanged: (v) => _updateManual(m.copyWith(volunteerHours: () => v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 25, right: 2, bottom: 8),
          child: ZcVolunteerBar(hours: r.volunteerUsed),
        ),
        if (lMats.isEmpty)
          _goMaterials(context, text: '暂无劳育证明 · 去材料库录入')
        else
          for (final x in lMats) _matRow(context, x),
        _sub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _subRow(
          context,
          null,
          '未参加学校/学院组织的劳育活动',
          tipKey: 'l-4-1',
          trailing: CountStepper(
            label: '未参加劳育活动次数',
            value: m.lKou1,
            onChanged: (v) => _updateManual(m.copyWith(lKou1: v)),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _check(
              '大学期间未参加实习实训(−2)',
              m.lKou2,
              (v) => _updateManual(m.copyWith(lKou2: v)),
              color: scheme.error,
            ),
            _check(
              '寝室卫生·学院通报(−2)',
              m.lKou3,
              (v) => _updateManual(m.copyWith(lKou3: v)),
              color: scheme.error,
            ),
            _check(
              '寝室卫生·学校通报(−4)',
              m.lKou4,
              (v) => _updateManual(m.copyWith(lKou4: v)),
              color: scheme.error,
            ),
          ],
        ),
      ],
    );
  }

  // ===================================================================
  // 班级排名估计（决定单项等次）
  // ===================================================================
  Widget _buildRankCard(BuildContext context) {
    final m = _manual;
    final scheme = Theme.of(context).colorScheme;
    final items = <(String, ZcRank, ValueChanged<ZcRank>, String)>[
      (
        '德育测评分班级排名',
        m.rankD,
        (v) => _updateManual(m.copyWith(rankD: v)),
        'rank-d',
      ),
      (
        '智育测评分班级排名',
        m.rankZ,
        (v) => _updateManual(m.copyWith(rankZ: v)),
        'rank-z',
      ),
      (
        '体育测评分班级排名',
        m.rankT,
        (v) => _updateManual(m.copyWith(rankT: v)),
        'rank-t',
      ),
      (
        '美育测评分班级排名',
        m.rankM,
        (v) => _updateManual(m.copyWith(rankM: v)),
        'rank-m',
      ),
      (
        '劳育测评分班级排名',
        m.rankL,
        (v) => _updateManual(m.copyWith(rankL: v)),
        'rank-l',
      ),
    ];
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.leaderboard_outlined,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelTip(
                      context,
                      '班级排名估计',
                      tipKey: 'sec-rank',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '决定单项等次（前 30% 可优秀 / 60% 后仅合格）',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _labelTip(
                        context,
                        it.$1,
                        tipKey: it.$4,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 190,
                    child: _fieldDrop<ZcRank>(
                      key: ValueKey('$_year-rank-${it.$1}'),
                      value: it.$2,
                      items: [
                        for (final rk in ZcRank.values)
                          DropdownMenuItem(value: rk, child: Text(rk.label)),
                      ],
                      onChanged: (v) {
                        if (v != null) it.$3(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本测算为个人自评参考，依据江财学工字〔2024〕27 号；材料分值按证书盖章时间计入相应学年，在「材料库」中录入后自动带入。民主评议分与班级排名为预估值，最终以班级评议、学院核查与公示结果为准。',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.outline,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          RuleTip(tipKey: 'general', size: 13),
        ],
      ),
    );
  }

  // ---------- 卡片 helpers ----------
  Widget _card(BuildContext context, Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline(context, 0.6)),
      ),
      child: child,
    );
  }
}
