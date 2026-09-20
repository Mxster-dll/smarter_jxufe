import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/storage/local_data_revision.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';
import 'package:smarter_jxufe/features/tice/data/providers/tice_providers.dart';
import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';
import 'package:smarter_jxufe/features/tice/data/tice_stu_num.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_weights.dart';
import 'package:smarter_jxufe/features/zongce/presentation/zongce_widgets.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/volunteer_bar.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/weight_sheet.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/shared/widgets/academic_year_picker.dart';
import 'package:smarter_jxufe/shared/widgets/count_stepper.dart';
import 'package:smarter_jxufe/design/app_states.dart';

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

  /// 材料类型 → 条款依据规则点（材料行悬停显示分值表，便于核对加分口径）。

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
          note = '检测到体测成绩 ${zcFmt(score)} 分（已手动填写，未覆盖）';
        } else if (_manual.tMian) {
          note = '检测到体测成绩 ${zcFmt(score)} 分（当前勾选免测，可取消后自动填入）';
        } else {
          _updateManual(
            _manual.copyWith(tScore: score.clamp(0, 100).toDouble()),
          );
          note = '已自动获取 ${yearEnd - 1} 学年体测成绩 ${zcFmt(score)} 分 · 可手动修改';
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
      return const AppLoadingState();
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
        zcResultCard(context, result, mats, onEditWeights: _editWeights),
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
        zcNoteCard(context),
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

  // ===================================================================
  // 五育卡公共件
  // ===================================================================

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
    final pingyi = zcSumDetail(r, const ['德育 · 民主评议']);
    final extra = zcSumDetail(r, const [
      '德育 · 优秀事迹',
      '德育 · 思想教育',
      '德育 · 公共服务',
      '德育 · 荣誉称号',
    ]);
    final kou = zcSumDetail(r, const ['德育 · 扣分']);
    return zcYuCard(
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
        zcSubRow(
          context,
          1,
          '基础分',
          tipKey: 'd-1-basic',
          trailing: zcStaticChip(context, '60 分'),
        ),
        // 2 民主评议（单行：右侧分值可点修改）
        zcSubRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: zcTipIdsOf(const ['sh-d-2', 'd-2-ping']),
          trailing: zcTapNumber(
            context,
            label: '民主评议分',
            value: m.deyuPingyi,
            display: '${zcFmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(deyuPingyi: v)),
          ),
        ),
        // 3 附加分（材料自动）
        zcSub(
          context,
          3,
          '附加分 · 证明材料（自动带入）',
          tipKey: 'sh-d-3',
          badge: extra > 0 ? zcBadge(context, '+${zcFmt(extra)}') : null,
          tip: dMats.isEmpty ? null : '${dMats.length} 条',
        ),
        if (dMats.isEmpty)
          zcGoMaterials(context, text: '暂无德育证明 · 去材料库录入')
        else
          for (final x in dMats) zcMatRow(context, x),
        // 4 扣分项
        zcSub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? zcBadge(context, '−${zcFmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        zcSubRow(
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
        zcSubRow(
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
        zcEditRow(
          context,
          '纪律处分',
          tipKey: 'd-4-3',
          child: SizedBox(
            width: 220,
            child: zcFieldDrop<int>(
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
        zcSub(
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
    final extra = zcSumDetail(r, const [
      '智育 · 学科竞赛',
      '智育 · 论文/专利',
      '智育 · 外语',
      '智育 · 创业',
    ]);
    final kou = zcSumDetail(r, const ['智育 · 扣分']);
    final contestItems = [
      for (final x in zMats)
        if (x.typeId == ZcTypeId.contest) x,
    ];
    final contestCounted = zcContestContributingIds(contestItems);
    return zcYuCard(
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
        zcSubRow(
          context,
          1,
          '加权成绩',
          tipKey: 'z-1-sync',
          trailing: zcTapNumberOpt(
            context,
            label: '加权成绩',
            value: m.weight,
            autoValue: r.weightMissing ? null : r.weightUsed,
            max: 100,
            display: weightLoading
                ? '加载中…'
                : (r.weightMissing ? null : zcFmt2(r.weightUsed)),
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
        zcSub(
          context,
          2,
          '加分项 · 四类各计最高（附加合计 ≤ 20 分）',
          tipKey: 'sh-z-2',
          badge: extra > 0 ? zcBadge(context, '+${zcFmt(extra)}') : null,
          tip: zMats.isEmpty ? null : '${zMats.length} 条',
        ),
        // 用户 2026-09-18：「综测智育加分项分为四部分，我希望你分开显示为四小项」
        // → 四个小项各自出分值（取引擎明细，不重算），下面挂各自的证明材料。
        zcExtraItem(
          context,
          label: '学科竞赛（表 8）',
          value: zcSumDetail(r, const ['智育 · 学科竞赛']),
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
        zcExtraItem(
          context,
          label: '论文 / 专利（表 9）',
          value: zcSumDetail(r, const ['智育 · 论文/专利']),
          tipIds: const ['r42', 'r43'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.paper) x,
          ],
        ),
        zcExtraItem(
          context,
          label: '外语能力（表 10）',
          value: zcSumDetail(r, const ['智育 · 外语']),
          tipIds: const ['r44'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.foreign) x,
          ],
        ),
        zcExtraItem(
          context,
          label: '创新创业（表 11）',
          value: zcSumDetail(r, const ['智育 · 创业']),
          tipIds: const ['r45'],
          items: [
            for (final x in zMats)
              if (x.typeId == ZcTypeId.startup) x,
          ],
        ),
        zcSub(
          context,
          3,
          '扣分项',
          badge: kou < 0
              ? zcBadge(context, '−${zcFmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        zcSubRow(
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
        zcSub(context, 4, '特殊情况', tipKey: 'z-4-1', color: scheme.error),
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
    final extra = zcSumDetail(r, const ['体育 · 竞赛/心理/集体']);
    final kou = zcSumDetail(r, const ['体育 · 扣分']);
    final ticeNote = _ticeBusy
        ? '正在从体测平台自动获取成绩…'
        : (_ticeNote ?? '由体育学院测试；免测/未测试按 60 分计');
    return zcYuCard(
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
        zcSubRow(
          context,
          1,
          '体测成绩（0~100）',
          tipKey: 't-1-score',
          trailing: zcTapNumber(
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
          child: zcCheck(context, '获批免测 / 未测试（按 60 分计）', m.tMian, (v) {
            _updateManual(m.copyWith(tMian: v));
            _autoTice(); // 免测状态变化 → 重新评估自动获取
          }),
        ),
        zcSub(
          context,
          2,
          '加分项 · 证明材料',
          tipKey: 'sh-t-2',
          badge: extra > 0 ? zcBadge(context, '+${zcFmt(extra)}') : null,
          tip: tMats.isEmpty ? null : '${tMats.length} 条',
        ),
        if (tMats.isEmpty)
          zcGoMaterials(context, text: '暂无体育证明 · 去材料库录入')
        else
          for (final x in tMats) zcMatRow(context, x),
        zcSub(
          context,
          3,
          '扣分项',
          badge: kou < 0
              ? zcBadge(context, '−${zcFmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        zcSubRow(
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
        zcSubRow(
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
    final pingyi = zcSumDetail(r, const ['美育 · 民主评议']);
    final extra = zcSumDetail(r, const ['美育 · 文艺竞赛/媒体/活动']);
    final kou = zcSumDetail(r, const ['美育 · 扣分']);
    return zcYuCard(
      context,
      dim: 'm',
      icon: Icons.palette_outlined,
      name: '美育素质',
      meta: '60 基础 + 20 评议 + 附加(材料) − 扣分',
      score: r.meiyu,
      grade: r.gM,
      headerTipKey: 'sec-meiyu',
      sections: [
        zcSubRow(
          context,
          1,
          '基础分',
          tipKey: 'm-1-basic',
          trailing: zcStaticChip(context, '60 分'),
        ),
        zcSubRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: zcTipIdsOf(const ['sh-m-2', 'm-2-ping']),
          trailing: zcTapNumber(
            context,
            label: '民主评议分',
            value: m.meiyuPingyi,
            display: '${zcFmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(meiyuPingyi: v)),
          ),
        ),
        zcSub(
          context,
          3,
          '加分项 · 证明材料（文艺竞赛/媒体/活动）',
          tipKey: 'sh-m-3',
          badge: extra > 0 ? zcBadge(context, '+${zcFmt(extra)}') : null,
          tip: mMats.isEmpty ? null : '${mMats.length} 条',
        ),
        if (mMats.isEmpty)
          zcGoMaterials(context, text: '暂无美育证明 · 去材料库录入')
        else
          for (final x in mMats) zcMatRow(context, x),
        zcSub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? zcBadge(context, '−${zcFmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        zcSubRow(
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
        zcSubRow(
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
        zcSubRow(
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
    final pingyi = zcSumDetail(r, const ['劳育 · 民主评议']);
    final volScore = zcSumDetail(r, const ['劳育 · 志愿服务']);
    final otherExtra = zcSumDetail(r, const ['劳育 · 实践/活动/寝室']);
    final kou = zcSumDetail(r, const ['劳育 · 扣分']);
    return zcYuCard(
      context,
      dim: 'l',
      icon: Icons.handyman_outlined,
      name: '劳育素质',
      meta: '60 基础 + 20 评议 + 附加(材料) − 扣分',
      score: r.laoyu,
      grade: r.gL,
      headerTipKey: 'sec-laoyu',
      sections: [
        zcSubRow(
          context,
          1,
          '基础分',
          tipKey: 'l-1-basic',
          trailing: zcStaticChip(context, '60 分'),
        ),
        zcSubRow(
          context,
          2,
          '民主评议分（预估）',
          tipIds: zcTipIdsOf(const ['sh-l-2', 'l-2-ping']),
          trailing: zcTapNumber(
            context,
            label: '民主评议分',
            value: m.laoyuPingyi,
            display: '${zcFmt(pingyi)} / 20',
            max: 20,
            onChanged: (v) => _updateManual(m.copyWith(laoyuPingyi: v)),
          ),
        ),
        zcSub(
          context,
          3,
          '加分项 · 证明材料',
          tipKey: 'sh-l-3',
          badge: (volScore + otherExtra) > 0
              ? zcBadge(context, '+${zcFmt(volScore + otherExtra)}')
              : null,
          tip: lMats.isEmpty ? null : '${lMats.length} 条',
        ),
        // 志愿服务时长：与基础分/评议分/加权/体测同款的单行胶囊（右侧可点改），
        // 差别只在于**下方多一条按表 18 档位分段的进度条**
        // （用户 2026-09-18：「志愿服务也基本和基本分、评议分、加权/体测成绩一样
        // 显示，唯一不同的是，还要额外在下方显示一个进度条，并根据各级别分段」）。
        // 标题不带「（按表 18 档位换算）」、条下不带任何说明文案
        // （用户同日二轮：「提示文本太多……都要去掉」）。
        zcSubRow(
          context,
          null,
          '志愿服务时长',
          tipKey: 'l-3-1',
          trailing: zcTapNumberOpt(
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
          zcGoMaterials(context, text: '暂无劳育证明 · 去材料库录入')
        else
          for (final x in lMats) zcMatRow(context, x),
        zcSub(
          context,
          4,
          '扣分项',
          badge: kou < 0
              ? zcBadge(context, '−${zcFmt(-kou)} 分', color: scheme.error)
              : null,
          color: scheme.error,
        ),
        zcSubRow(
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
            zcCheck(context, 
              '大学期间未参加实习实训(−2)',
              m.lKou2,
              (v) => _updateManual(m.copyWith(lKou2: v)),
              color: scheme.error,
            ),
            zcCheck(context, 
              '寝室卫生·学院通报(−2)',
              m.lKou3,
              (v) => _updateManual(m.copyWith(lKou3: v)),
              color: scheme.error,
            ),
            zcCheck(context, 
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
    return zcCard(
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
                    zcLabelTip(
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
                      child: zcLabelTip(
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
                    child: zcFieldDrop<ZcRank>(
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

  // ---------- 卡片 helpers ----------

}
