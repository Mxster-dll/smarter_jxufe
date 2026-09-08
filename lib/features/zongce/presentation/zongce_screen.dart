import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/tice/data/providers/tice_providers.dart';
import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';
import 'package:smarter_jxufe/features/tice/data/tice_stu_num.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/rule_tip.dart';

/// 综合测评 · 自动测算（单页）。
///
/// 页面版式参照《2026 综测计算器.html》：五育分卡（编号分区 + 实时徽章），
/// 底部「班级排名估计」卡决定单项等次；配色统一到 App 主题、控件全部换
/// 成 App 风格。材料加分来自共享数据源 [zcMaterialsProvider]（材料库维护），
/// 教务加权 / 第二课堂志愿自动带入，评议 / 体测 / 排名手动填写（标注预估）。
class ZongceScreen extends ConsumerStatefulWidget {
  const ZongceScreen({super.key});

  @override
  ConsumerState<ZongceScreen> createState() => _ZongceScreenState();
}

class _ZongceScreenState extends ConsumerState<ZongceScreen> {
  late int _year;
  bool _ready = false;
  ZcManual _manual = const ZcManual();
  ZcStore? _store;
  String? _loadError;

  // ---- 体测成绩自动获取（赛康体测平台，仅当用户未手动编辑时回填）----
  bool _ticeBusy = false; // 自动查询进行中
  bool _ticeTouched = false; // 本学年用户已手动编辑体测分数（防覆盖）
  bool _ticeFilled = false; // 本次自动值已写入（badge 标「自动」）
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
      _ticeFilled = false;
      _ticeNote = '正在从体测平台自动获取成绩…';
    });
    String? note;
    var filled = false;
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
          filled = true;
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
      _ticeFilled = filled;
      _ticeNote = note;
    });
  }

  /// 体测分数被手动编辑：本学年停止自动回填。
  void _markTiceManual() {
    if (_ticeTouched) return;
    setState(() {
      _ticeTouched = true;
      _ticeFilled = false;
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

  void _switchYear(int delta) => _loadYear(_year + delta);

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
      _ticeFilled = false;
      _ticeNote = null;
    });
    _autoTice();
  }

  // ---------- 工具 ----------

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

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
    return Scaffold(
      appBar: AppBar(title: const Text('综合测评'), centerTitle: false),
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
    final mats = zcFilterByYear(all, _year);
    final weightAsync = ref.watch(zcAutoWeightProvider);
    final volAsync = ref.watch(zcAutoVolunteerProvider);
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
        _buildYuCardLao(context, result, mats, volAsync.isLoading),
        const SizedBox(height: 12),
        _buildRankCard(context),
        const SizedBox(height: 12),
        _buildNoteCard(context),
      ],
    );
  }

  Widget _buildYearBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          onPressed: () => _switchYear(-1),
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一学年',
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                zcYearLabel(_year),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '测评周期：9 月起测评上一学年（材料按盖章时间归档）',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _switchYear(1),
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一学年',
        ),
      ],
    );
  }

  // ===================================================================
  // 顶部：测评结果（原网页「结果侧栏」语义，单列时置顶常驻）
  // ===================================================================
  Widget _buildResultCard(
    BuildContext context,
    ZcCalcResult r,
    List<ZcMaterial> mats,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final avg = (r.deyu + r.zhiyu + r.tiyu + r.meiyu + r.laoyu) / 5;
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
                  color: scheme.primary.withValues(alpha: 0.08),
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
                    const Text(
                      '测评结果',
                      style: TextStyle(
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
              const SizedBox(width: 4),
              RuleTip(tipKey: 'overall', size: 14),
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
                  _statLine(
                    '五育平均',
                    '${_fmt(avg)} 分',
                    emphasize: true,
                    context: context,
                  ),
                  const SizedBox(height: 4),
                  _statLine(
                    '加权成绩',
                    r.weightMissing ? '未获取' : '${_fmt(r.weightUsed)} 分',
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
        color: color.withValues(alpha: 0.12),
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
        color: Colors.white,
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
              color: color.withValues(alpha: 0.045),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.16)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
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
                if (headerTipKey != null)
                  RuleTip(tipKey: headerTipKey, size: 13.5),
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
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          ?badge,
          if (tipKey != null) RuleTip(tipKey: tipKey, color: c, size: 13.5),
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
        color: c.withValues(alpha: 0.09),
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
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
              if (tipKey != null) RuleTip(tipKey: tipKey, size: 13.5),
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

  /// 数字输入（定宽，无 Expanded —— 只能在有限宽容器里使用）。
  Widget _numField(
    String label,
    String text,
    ValueChanged<String> onChanged, {
    String? hint,
    double width = 150,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('$_year-num-$label'),
        initialValue: text,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          border: const OutlineInputBorder(),
          hintText: hint,
        ),
        onChanged: onChanged,
      ),
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
      selectedColor: (color ?? _schemeColor).withValues(alpha: 0.14),
      checkmarkColor: color ?? _schemeColor,
      labelStyle: TextStyle(
        color: value ? (color ?? _schemeColor) : null,
        fontSize: 11.5,
      ),
      onSelected: onChanged,
    );
  }

  /// 材料只读行：名称 + 类型·日期 + 分值（自动来自材料库）。
  Widget _matRow(BuildContext context, ZcMaterial m) {
    final scheme = Theme.of(context).colorScheme;
    final spec = zcTypeSpecOf[m.typeId];
    final v = zcMaterialValue(m);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 15, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  '${spec?.label ?? ''} · ${m.optionLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          RuleTip(
            ids: _materialRuleIds[m.typeId],
            color: scheme.primary,
            size: 13,
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
        ],
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
        // 1 基础分
        _sub(context, 1, '基础分', tip: '思想端正、遵纪守法、品德优良即认定'),
        _editRow(
          context,
          '德育基础分',
          tipKey: 'd-1-basic',
          scoreText: '60 分',
          scoreColor: scheme.outline,
          child: const SizedBox.shrink(),
          note: '自动认定 60 分',
        ),
        // 2 民主评议
        _sub(
          context,
          2,
          '民主评议分（预估）',
          tipKey: 'sh-d-2',
          badge: _badge(context, '${_fmt(pingyi)} / 20'),
        ),
        _editRow(
          context,
          '德育民主评议分（0~20）',
          tipKey: 'd-2-ping',
          child: _numField(
            '德育评议',
            _fmt(m.deyuPingyi),
            (s) =>
                _updateManual(m.copyWith(deyuPingyi: double.tryParse(s) ?? 0)),
          ),
          note: '思想政治8 + 社会公德3 + 遵纪守法3 + 集体观念3 + 行为规范3',
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
        _editRow(
          context,
          '无故缺课',
          tipKey: 'd-4-1',
          child: _numField(
            '缺课节数',
            '${m.kouQk}',
            (s) => _updateManual(m.copyWith(kouQk: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '节 × 2 分/节（班主任、任课老师认定）',
        ),
        _editRow(
          context,
          '无故缺席重大集体活动',
          tipKey: 'd-4-2',
          child: _numField(
            '缺席次数',
            '${m.kouHd}',
            (s) => _updateManual(m.copyWith(kouHd: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 1 分/次',
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
    final weightTxt = m.weight == null
        ? ''
        : (m.weight == 0 ? '' : _fmt(m.weight!));
    final extra = _sumDetail(r, const [
      '智育 · 学科竞赛',
      '智育 · 论文/专利',
      '智育 · 外语',
      '智育 · 创业',
    ]);
    final kou = _sumDetail(r, const ['智育 · 扣分']);
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
        _sub(
          context,
          1,
          '加权成绩',
          badge: _badge(
            context,
            '${r.weightMissing ? '未获取' : _fmt(r.weightUsed)} 分',
          ),
          tip: weightLoading ? '教务加载中…' : null,
        ),
        _editRow(
          context,
          '课程加权平均成绩',
          tipKey: 'z-1-sync',
          child: SizedBox(
            width: 170,
            child: TextFormField(
              key: ValueKey('$_year-num-智育加权'),
              initialValue: weightTxt,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: InputDecoration(
                labelText: '加权成绩',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                border: const OutlineInputBorder(),
                hintText: r.weightAuto
                    ? '自动 ${r.weightUsed <= 0 ? '未获取' : _fmt(r.weightUsed)}'
                    : null,
                suffixIcon: IconButton(
                  tooltip: '刷新教务加权',
                  icon: Icon(Icons.refresh, size: 16, color: scheme.primary),
                  onPressed: () => ref.invalidate(zcAutoWeightProvider),
                ),
              ),
              onChanged: (s) => _updateManual(
                m.copyWith(
                  weight: () => s.trim().isEmpty ? null : double.tryParse(s),
                ),
              ),
            ),
          ),
          note: '教务自动带入，留空即用自动值；也可手动覆盖',
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
                    '未获取到加权成绩（需登录教务或手动填写）',
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
        _sub(
          context,
          2,
          '加分项 · 证明材料（四类各计最高）',
          tipKey: 'sh-z-2',
          badge: extra > 0 ? _badge(context, '+${_fmt(extra)}') : null,
          tip: zMats.isEmpty ? null : '${zMats.length} 条',
        ),
        if (zMats.isEmpty)
          _goMaterials(context, text: '暂无智育证明 · 去材料库录入')
        else
          for (final x in zMats) _matRow(context, x),
        _sub(
          context,
          3,
          '扣分项',
          badge: kou < 0
              ? _badge(context, '−${_fmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        _editRow(
          context,
          '无故不参加实习实训 / 课外学术创新活动',
          tipKey: 'z-3-1',
          child: _numField(
            '次数',
            '${m.kouZhiyu}',
            (s) => _updateManual(m.copyWith(kouZhiyu: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 3 分/次',
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
        _sub(
          context,
          1,
          '体质测试成绩',
          badge: _badge(
            context,
            m.tMian
                ? '60 分（免测）'
                : (_ticeFilled ? '${_fmt(m.tScore)} 分 · 自动' : '${_fmt(m.tScore)} 分'),
          ),
        ),
        _editRow(
          context,
          '体测成绩（0~100）',
          tipKey: 't-1-score',
          child: _numField(
            '体测成绩',
            m.tMian ? '' : _fmt(m.tScore),
            (s) {
              _markTiceManual();
              _updateManual(
                m.copyWith(tScore: double.tryParse(s) ?? (m.tMian ? 60 : 0)),
              );
            },
            hint: m.tMian ? '免测按 60' : null,
            width: 150,
          ),
          note: ticeNote,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _check(
            '获批免测 / 未测试（按 60 分计）',
            m.tMian,
            (v) {
              _updateManual(m.copyWith(tMian: v));
              _autoTice(); // 免测状态变化 → 重新评估自动获取
            },
          ),
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
        _editRow(
          context,
          '体育活动当众扰乱秩序',
          tipKey: 't-3-1',
          child: _numField(
            '次数',
            '${m.tKou1}',
            (s) => _updateManual(m.copyWith(tKou1: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 5 分/次',
        ),
        _editRow(
          context,
          '参赛无故弃权 / 中途退场',
          tipKey: 't-3-2',
          child: _numField(
            '次数',
            '${m.tKou2}',
            (s) => _updateManual(m.copyWith(tKou2: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 2 分/次',
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
        _sub(context, 1, '基础分', tip: '注重感受美、表现美、鉴赏美、创造美'),
        _editRow(
          context,
          '美育基础分',
          tipKey: 'm-1-basic',
          scoreText: '60 分',
          scoreColor: scheme.outline,
          child: const SizedBox.shrink(),
          note: '自动认定 60 分',
        ),
        _sub(
          context,
          2,
          '民主评议分（预估）',
          tipKey: 'sh-m-2',
          badge: _badge(context, '${_fmt(pingyi)} / 20'),
        ),
        _editRow(
          context,
          '美育民主评议分（0~20）',
          tipKey: 'm-2-ping',
          child: _numField(
            '美育评议',
            _fmt(m.meiyuPingyi),
            (s) =>
                _updateManual(m.copyWith(meiyuPingyi: double.tryParse(s) ?? 0)),
          ),
          note: '含人文素养、艺术修养、审美能力等',
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
        _editRow(
          context,
          '文艺活动当众扰乱秩序',
          tipKey: 'm-4-1',
          child: _numField(
            '次数',
            '${m.mKou1}',
            (s) => _updateManual(m.copyWith(mKou1: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 1 分/次',
        ),
        _editRow(
          context,
          '艺术团未满服务期退团',
          tipKey: 'm-4-2',
          child: _numField(
            '次数',
            '${m.mKou2}',
            (s) => _updateManual(m.copyWith(mKou2: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 2 分/次',
        ),
        _editRow(
          context,
          '代表参赛无故弃权 / 中途退场',
          tipKey: 'm-4-3',
          child: _numField(
            '次数',
            '${m.mKou3}',
            (s) => _updateManual(m.copyWith(mKou3: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 5 分/次',
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
    bool volLoading,
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
    final volTxt = m.volunteerHours == null ? '' : _fmt(m.volunteerHours!);
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
        _sub(context, 1, '基础分', tip: '劳动观念正确、技能过关'),
        _editRow(
          context,
          '劳育基础分',
          tipKey: 'l-1-basic',
          scoreText: '60 分',
          scoreColor: scheme.outline,
          child: const SizedBox.shrink(),
          note: '自动认定 60 分',
        ),
        _sub(
          context,
          2,
          '民主评议分（预估）',
          tipKey: 'sh-l-2',
          badge: _badge(context, '${_fmt(pingyi)} / 20'),
        ),
        _editRow(
          context,
          '劳育民主评议分（0~20）',
          tipKey: 'l-2-ping',
          child: _numField(
            '劳育评议',
            _fmt(m.laoyuPingyi),
            (s) =>
                _updateManual(m.copyWith(laoyuPingyi: double.tryParse(s) ?? 0)),
          ),
          note: '劳动教育课出勤、劳动实践态度等',
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
        _editRow(
          context,
          '志愿服务时长（按表 18 档位换算）',
          tipKey: 'l-3-1',
          child: SizedBox(
            width: 170,
            child: TextFormField(
              key: ValueKey('$_year-num-劳育志愿'),
              initialValue: volTxt,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              decoration: InputDecoration(
                labelText: '本学年志愿时长(h)',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                border: const OutlineInputBorder(),
                hintText: r.volunteerAuto ? '自动累计' : null,
                suffixIcon: IconButton(
                  tooltip: '刷新第二课堂累计',
                  icon: Icon(Icons.refresh, size: 16, color: scheme.primary),
                  onPressed: () => ref.invalidate(zcAutoVolunteerProvider),
                ),
              ),
              onChanged: (s) => _updateManual(
                m.copyWith(
                  volunteerHours: () =>
                      s.trim().isEmpty ? null : double.tryParse(s),
                ),
              ),
            ),
          ),
          scoreText: volLoading
              ? '…'
              : '${_fmt(r.volunteerUsed)} h → ${_fmt(volScore)} 分',
          scoreColor: scheme.primary,
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
        _editRow(
          context,
          '未参加学校/学院组织的劳育活动',
          tipKey: 'l-4-1',
          child: _numField(
            '次数',
            '${m.lKou1}',
            (s) => _updateManual(m.copyWith(lKou1: int.tryParse(s) ?? 0)),
            width: 110,
          ),
          note: '次 × 1 分/次',
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
                    const Text(
                      '班级排名估计',
                      style: TextStyle(
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
              Icon(Icons.help_outline, size: 15, color: scheme.outline),
              const SizedBox(width: 6),
              RuleTip(tipKey: 'sec-rank', size: 13.5),
            ],
          ),
          const SizedBox(height: 10),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      it.$1,
                      style: TextStyle(fontSize: 13, color: scheme.onSurface),
                    ),
                  ),
                  RuleTip(tipKey: it.$4, size: 13),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}
