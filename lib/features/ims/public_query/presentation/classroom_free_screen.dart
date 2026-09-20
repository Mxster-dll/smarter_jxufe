/// 「找空闲教室」页 —— 公共查询里那两个子功能（原网页 SB11 / SB12）。
///
/// - **按时间找教室**（SB11 分周次/节次查看空闲教室）：选教学周 + 星期 + 节次
///   → 列出这些天这些节次都空着的教室；
/// - **按教室查空闲**（SB12 分教室查看空闲周次/节次）：选一间教室
///   → 看它每一周的空闲时段，以及「整学期每周都空」的固定时段。
///
/// ⚠ 两个功能**都不打原网页那两个端点**（SB11 恒空、SB12 一次回 94 MB，实测见
/// `domain/classroom_free.dart` 文件头）：只用一个**教室课表报表**
/// （`PublicQueryKind.classroom`）拿整个校区/整栋楼的占用，其余在客户端算。
///
/// ## 界面口径（用户 2026-09-19 二/三轮）
/// - 节次 = **1-12 每节独立**（不再是 `1-2 / 3-5` 那种大节档）；
/// - 进页面时按「现在」自动选中一段：**从当前节数**（不在上课时间就**从下节课开始**）
///   到「下一个节点」（相邻两节间隔 > 1 小时）前的最后一节课 —— 见
///   `domain/classroom_free.dart` 的 [classroomAutoPeriodRange]；点「按现在时间」可重算，
///   手动勾过任一节之后不再被自动覆盖。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/classroom_free.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query_defaults.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/classroom_free_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/design/settings_section.dart';

/// 星期 / 节次胶囊之间的间距。
///
/// **合并段内部也用同一个值** —— 「3 个独立格子」与「一段 3 格」的总宽因此完全
/// 相同，勾选/取消不会让后面的格子挪位（用户 2026-09-19 三轮：「节次被选择后不要
/// 显示前面的对勾，因为会导致按钮宽度变化」+「连续被选择的节次视觉上是一个卡片，
/// 但是仍然可以独立点击」）。段内那份**只是透明占位**，不画分格线
/// （用户 2026-09-20 六轮：「相连的节数按钮之间不要显示分割线」）。
const double kClassroomChipGap = 6;

/// 两个子功能。
enum ClassroomFreeMode {
  byTime('按时间找教室'),
  byRoom('按教室查空闲');

  const ClassroomFreeMode(this.label);

  final String label;
}

class ClassroomFreeScreen extends ConsumerStatefulWidget {
  const ClassroomFreeScreen({
    super.key,
    this.mode = ClassroomFreeMode.byTime,
    this.roomName = '',
    this.now,
  });

  final ClassroomFreeMode mode;

  /// 从「按时间找教室」点某一行进来的那间教室（模式 B 预选）。
  final String roomName;

  /// 注入「今天」，用于「星期默认选今天」的确定性断言（生产不传 = 真实时间）。
  ///
  /// 先例：`ge_deadline_card` 与 `CompetitionAwardScreen` 的 `now` 参数同理。
  final DateTime? now;

  @override
  ConsumerState<ClassroomFreeScreen> createState() =>
      _ClassroomFreeScreenState();
}

class _ClassroomFreeScreenState extends ConsumerState<ClassroomFreeScreen> {
  late ClassroomFreeMode _mode = widget.mode;
  PublicQueryTerm? _term;
  String _campus = '';
  String _building = '';
  late int _week;

  /// 「今天」——「星期」默认就选它（用户 2026-09-19：「时间自动选到今天」）。
  ///
  /// 不是 `final`：点「按现在时间」会重新取一次（见 [_resetPeriodsToNow]）。
  late DateTime _now = widget.now ?? DateTime.now();

  /// 选中的星期（**多选**，默认只有今天那一天）。
  late final Set<int> _weekdays = {_now.weekday};

  /// 用户**手选**的节次（多选，1-12 每节独立）。
  ///
  /// 用户 2026-09-19 二轮：「节数不要 1-2、3-5 这样，而是 1-12 每个都独立」。
  /// 只有 [_periodsTouched] 为真时它才生效；否则用「按现在时间」自动算出的那一段。
  final Set<int> _periods = <int>{};

  /// 用户是否动过节次 chip：动过之后不再被自动选段覆盖。
  bool _periodsTouched = false;

  bool _includeWeekend = true;
  int _minPeriods = 1;

  /// 模式 B 选中的教室（来自下拉清单；可能还没在清单里出现 → 只有名字）。
  ClassroomInfo? _room;

  /// 是否已经按「我的校区」预填过（只做一次，之后尊重用户选择）。
  bool _campusDefaultApplied = false;

  /// 是否已经按设置页「默认教学楼」预填过（同上，只做一次）。
  bool _buildingDefaultApplied = false;

  @override
  void initState() {
    super.initState();
    final terms = ref.read(offlineSemesterTermsProvider);
    final teachingWeek = resolveTeachingWeek(_now, terms: terms);
    _week = teachingWeek != null && teachingWeek.week > 0
        ? teachingWeek.week
        : 1;
    if (widget.roomName.isNotEmpty) {
      _room = ClassroomInfo(code: '', name: widget.roomName);
    }
  }

  /// 教务实时作息表 —— 拿不到就退回只读缓存，再退回内置兜底表。
  ///
  /// 与课表页同口径（`schedule_screen.dart` 的 `periods`）：节次自动选段只依赖它。
  PeriodTable _periodTable() =>
      ref.watch(currentPeriodTableProvider).valueOrNull ??
      ref.watch(cachedPeriodTableProvider).valueOrNull ??
      PeriodTable.builtin;

  /// 生效中的节次：用户没动过 chip 时用「按现在时间」自动算出的那一段。
  Set<int> _effectivePeriods(({int start, int end})? auto) {
    if (_periodsTouched || auto == null) return _periods;
    return <int>{for (var p = auto.start; p <= auto.end; p++) p};
  }

  /// 生效中的节次 → 领域层的 `periodBlocks`（连续节次合并成一段，恒升序）。
  List<(int, int)> _periodBlocks(Set<int> periods) =>
      classroomPeriodRanges(periods);

  /// 点「按现在时间」：回到自动选段（注入 `now` 的测试保持确定性，不刷新时钟）。
  void _resetPeriodsToNow() {
    setState(() {
      _periodsTouched = false;
      if (widget.now == null) _now = DateTime.now();
    });
  }

  String _clockText(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// 自动选段的说明（用户要看得见「为什么是这几节」）。
  String _autoPeriodHint(({int start, int end}) auto) {
    final table = _periodTable();
    final startAt = table.periodOf(auto.start)?.start;
    (int, int)? next;
    for (final segment in classroomPeriodSegments(table)) {
      if (segment.$1 > auto.end) {
        next = segment;
        break;
      }
    }
    final nextAt = next == null ? null : table.periodOf(next.$1)?.start;
    final buffer = StringBuffer(
      '已按现在时间（${_clockText(_now)}）自动选中 '
      '${classroomPeriodBlocksLabel([(auto.start, auto.end)])}',
    );
    if (startAt != null) buffer.write('，第 ${auto.start} 节 $startAt 开始');
    buffer.write('；这一段到第 ${auto.end} 节为止');
    if (next != null && nextAt != null) {
      buffer.write('，下一段从第 ${next.$1} 节（$nextAt）开始');
    }
    buffer.write('。点「按现在时间」可重算。');
    return buffer.toString();
  }

  // ---------------- 请求 ----------------

  PublicQueryTerm? _effectiveTerm(List<PublicQueryTerm> terms) {
    if (_term != null) return _term;
    if (terms.isEmpty) return null;
    final resolve = currentSchoolTerm(
      DateTime.now(),
      terms: ref.read(offlineSemesterTermsProvider),
    );
    for (final t in terms) {
      if (t.matches(resolve.xn, resolve.xq)) return t;
    }
    return terms.first;
  }

  /// 模式 A：整校区 / 整栋楼的教室课表（一次请求覆盖全部教室）。
  PublicQueryRequest? _timeRequest(PublicQueryTerm? term) {
    if (term == null || _campus.isEmpty) return null;
    return PublicQueryRequest(
      kind: PublicQueryKind.classroom,
      term: term,
      campusCode: _campus,
      buildingCode: _building,
    );
  }

  /// 模式 B：单间教室（按教室查，响应很小）。
  ///
  /// ⚠ **教室码要能兜底**：从「按时间找教室」点某一行跳过来时，那间教室来自**报表**，
  /// 报表只有名字没有教室码（`ClassroomOccupancy.code` 为空）→ 先按名字在教室清单里
  /// 找一次 `code`（`matchPublicQueryOption`，与预填同口径）；实在找不到就返回 null，
  /// 页面给出「换一间」的提示，而不是发一个空码请求。
  PublicQueryRequest? _roomRequest(
    PublicQueryTerm? term,
    List<ClassroomInfo> infos,
  ) {
    final room = _room;
    if (term == null || _campus.isEmpty || room == null) return null;
    var code = room.code;
    if (code.isEmpty) {
      code = classroomInfoNamed(infos, room.name)?.code ?? '';
    }
    if (code.isEmpty) return null;
    return PublicQueryRequest(
      kind: PublicQueryKind.classroom,
      term: term,
      campusCode: _campus,
      roomCode: code,
    );
  }

  /// 教室清单（下拉接口的 `lf_m` 实测不生效，给的是**整个校区**的教室）。
  List<ClassroomInfo> _classroomInfos() {
    if (_campus.isEmpty) return const [];
    final async = ref.watch(publicQueryClassroomsProvider('$_campus|'));
    final options = async.valueOrNull ?? const <PublicQueryOption>[];
    return parseClassroomInfos(options);
  }

  /// 按「我的校区」预填一次（设置页里的偏好；匹配不到就留空，绝不猜）。
  ///
  /// 匹配用 [matchPublicQueryOption]（精确 > 前缀 > 包含，已在 defaults 里单测过）。
  ///
  /// ⚠ 两条都是踩过的坑：
  /// 1. **必须 `ref.watch(myCampusStoreProvider)`**（在 `build` 里），不能 `read` ——
  ///    偏好 store 是异步加载的，`read` 不订阅，加载完成时本页不会重建，预填永远落不上；
  /// 2. **拿到值才落闸**：首帧 store 还是 null 时不能置 `_campusDefaultApplied`。
  void _applyCampusDefault(
    List<PublicQueryOption> campuses,
    String? myCampusLabel,
  ) {
    if (_campusDefaultApplied || _campus.isNotEmpty || campuses.isEmpty) return;
    if (myCampusLabel == null || myCampusLabel.isEmpty) return;
    _campusDefaultApplied = true;
    final matched = matchPublicQueryOption(campuses, myCampusLabel);
    if (matched != null) _campus = matched.code;
  }

  /// 按设置页「默认教学楼」预填一次（用户 2026-09-19：「教学楼默认选哪个是可以设置的」）。
  ///
  /// 三条口径：
  /// 1. **必须 `ref.watch(publicQueryPrefsStoreProvider)`**（在 `build` 里）—— store 异步
  ///    加载，`read` 不订阅，加载完成时本页不会重建，预填永远落不上（与「我的校区」同一个坑）；
  /// 2. **只有当前校区的楼房列表里真的有这栋楼才预选**：楼房码按校区编，跨校区不通用，
  ///    找不到就留空（绝不拿别的校区的同号码去顶）；
  /// 3. 已经预填过、或用户自己选过楼 → 不再覆盖（`_buildingDefaultApplied` / `_building` 非空）。
  void _applyBuildingDefault(
    List<PublicQueryOption> buildings,
    PublicQueryBuilding? wanted,
  ) {
    if (_buildingDefaultApplied || wanted == null || _building.isNotEmpty) {
      return;
    }
    if (_campus.isEmpty || buildings.isEmpty) return;
    _buildingDefaultApplied = true;
    if (buildings.any((b) => b.code == wanted.buildingCode)) {
      _building = wanted.buildingCode;
    }
  }

  void _refreshAll() {
    ref.invalidate(publicQueryTermsProvider);
    ref.invalidate(publicQueryCampusesProvider);
    if (_campus.isNotEmpty) {
      ref.invalidate(publicQueryClassroomsProvider('$_campus|'));
    }
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final termsAsync = ref.watch(publicQueryTermsProvider);
    final campusesAsync = ref.watch(publicQueryCampusesProvider);
    final terms = termsAsync.valueOrNull ?? const <PublicQueryTerm>[];
    final campuses = campusesAsync.valueOrNull ?? const <PublicQueryOption>[];
    // watch（不是 read）→「我的校区」异步加载完成时本页会重建，预填才落得上。
    final myCampusLabel = ref.watch(myCampusStoreProvider).campus?.label;
    _applyCampusDefault(campuses, myCampusLabel);
    // 同理：设置页的「默认教学楼」也是异步加载的。
    final buildings = _campus.isEmpty
        ? const <PublicQueryOption>[]
        : ref.watch(publicQueryBuildingsProvider(_campus)).valueOrNull ??
              const <PublicQueryOption>[];
    _applyBuildingDefault(
      buildings,
      ref.watch(publicQueryPrefsStoreProvider).defaultBuilding,
    );
    final term = _effectiveTerm(terms);
    // 作息表（教务实时 → 只读缓存 → 内置兜底）+「按现在时间」自动选出的那一段。
    final periodTable = _periodTable();
    final autoPeriods = classroomAutoPeriodRange(table: periodTable, now: _now);
    final periods = _effectivePeriods(autoPeriods);
    final infos = _mode == ClassroomFreeMode.byRoom || _building.isEmpty
        ? _classroomInfos()
        : const <ClassroomInfo>[];

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('找空闲教室'),
        actions: _headerActions(),
        settingsSections: const [
          SettingsSection.imsSession,
          SettingsSection.publicQuery,
        ],
      ),
      body: PaneBody(
        actions: _headerActions(),
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
          children: [
            _modeCard(context),
            const SizedBox(height: 12),
            ..._scopeCards(context, term, terms),
            const SizedBox(height: 12),
            if (_mode == ClassroomFreeMode.byTime)
              ..._byTimeBody(
                context,
                term,
                infos,
                periods: periods,
                auto: autoPeriods,
              )
            else
              ..._byRoomBody(context, term, infos),
          ],
        ),
      ),
    );
  }

  List<Widget> _headerActions() => [
    IconButton(
      tooltip: '刷新学期 / 教室列表',
      icon: const Icon(Icons.refresh),
      onPressed: _refreshAll,
    ),
  ];

  Widget _modeCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '找空闲教室',
              accent: fp(context).publicQuery,
            ),
            const SizedBox(height: 10),
            SegmentedButton<ClassroomFreeMode>(
              segments: [
                for (final m in ClassroomFreeMode.values)
                  ButtonSegment(
                    value: m,
                    label: Text(m.label),
                    icon: Icon(
                      m == ClassroomFreeMode.byTime
                          ? Icons.schedule_outlined
                          : Icons.meeting_room_outlined,
                      size: 16,
                    ),
                  ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == ClassroomFreeMode.byTime
                  ? '选教学周 + 星期 + 节次，列出这些时段都空着的教室。'
                  : '选一间教室，看它每一周的空闲时段，以及整学期每周都空的固定时段。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 学期 + 校区 + 楼房（楼房对两个模式都生效；模式 A 的响应大小由它决定）。
  List<Widget> _scopeCards(
    BuildContext context,
    PublicQueryTerm? term,
    List<PublicQueryTerm> terms,
  ) {
    final campusesAsync = ref.watch(publicQueryCampusesProvider);
    final buildingsAsync = _campus.isEmpty
        ? null
        : ref.watch(publicQueryBuildingsProvider(_campus));
    return [
      Card(
        elevation: 0,
        shape: geCardShape(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              geCardTitle(
                context,
                text: '查询范围',
                accent: fp(context).publicQuery,
              ),
              const SizedBox(height: 6),
              _row(
                context,
                icon: Icons.event_note_outlined,
                label: '学年学期',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PublicQueryTerm>(
                    key: const Key('classroomFreeTerm'),
                    isExpanded: true,
                    value: term,
                    items: [
                      for (final t in terms)
                        DropdownMenuItem(value: t, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _term = v),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _row(
                context,
                icon: Icons.location_city_outlined,
                label: '校区',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('classroomFreeCampus'),
                    isExpanded: true,
                    value: _campus.isEmpty ? '' : _campus,
                    items: [
                      const DropdownMenuItem(value: '', child: Text('请选择校区')),
                      for (final c in campusesAsync.valueOrNull ??
                          const <PublicQueryOption>[])
                        DropdownMenuItem(
                          value: c.code,
                          child: Text(c.displayName),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _campus = v ?? '';
                      _building = '';
                      _room = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _row(
                context,
                icon: Icons.apartment_outlined,
                label: '楼房',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('classroomFreeBuilding'),
                    isExpanded: true,
                    value: _building,
                    items: [
                      const DropdownMenuItem(value: '', child: Text('不限（整个校区）')),
                      for (final b in buildingsAsync?.valueOrNull ??
                          const <PublicQueryOption>[])
                        DropdownMenuItem(
                          value: b.code,
                          child: Text(b.displayName),
                        ),
                    ],
                    onChanged: (v) => setState(() => _building = v ?? ''),
                  ),
                ),
              ),
              if (_building.isEmpty && _campus.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '不选楼房 = 拉整个校区的教室课表，第一次会慢一些（几十秒）；'
                  '选定教学楼会快很多。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  /// 单格选择胶囊（星期与节次的格子共用）。
  ///
  /// 用户 2026-09-19 三轮：「节次被选择后不要显示前面的对勾，因为会导致按钮宽度
  /// 变化」—— M3 的 `FilterChip` 在选中时会插一个 18px 对勾 + 8px 间隔，格子宽度
  /// 因此跳变。这里一律 `showCheckmark: false`，并且把胶囊自身的底色/描边交出去
  /// （`backgroundColor` / `selectedColor` 透明，描边由调用方给）：
  /// 于是同一格在「选中 / 未选中」「独立 / 合并段内」四种情形下**尺寸完全一致**，
  /// 视觉状态只由外层容器与外层描边表达。
  Widget _classroomChoiceChip(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    BorderSide? side,
    Color? selectedLabel,
    Color? selectedFill,
    BorderRadius? radius,
  }) {
    final accent = fp(context).publicQuery;
    return FilterChip(
      key: key,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      elevation: 0,
      pressElevation: 0,
      // ⚠ 底色必须**由胶囊自己画**：只靠外层 `_chipFill` 是不行的 —— `FilterChip`
      // 在深色下会用 `colorScheme.surface`（#121212）把外层那层红整个盖住，窗口像素
      // 实测只剩「每格左边 11px 的红边」（最长连续红段仅 24px），用户看到的仍是黑按钮
      // （2026-09-20 四轮：「按钮选中后也要显示 c62828，而不是黑色」）。
      backgroundColor: selected ? selectedFill : Colors.transparent,
      selectedColor: selectedFill,
      disabledColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      side: side ?? BorderSide(color: AppColors.stroke(context)),
      // 圆角由调用方给：合并段内部一律**方角**（`BorderRadius.zero`）、只有段两端保留
      // 8 圆角 —— 于是整段是「一块」而不是「并排的圆角按钮」（用户 2026-09-20 七轮：
      // 「连续选中的节数按钮之间看起来还是不连续，感觉是按钮边框的问题」）。
      shape: RoundedRectangleBorder(
        borderRadius: radius ?? BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected
            ? (selectedLabel ?? accent)
            : AppColors.textMuted(context),
      ),
    );
  }

  /// 一段节次（[classroomPeriodRuns] 的输出）：
  ///
  /// - 长度 1：独立一格（选中 → 自己一张圆角淡底，未选中 → 只有描边）；
  /// - 长度 > 1：**合并成一张卡片** —— 外层一张连续圆角淡底，内部每格仍是独立
  ///   的胶囊，可以单独点（用户三轮原话）；格子之间**不画分格线**，整段连成一块红
  ///   （用户 2026-09-20 六轮原话）。
  ///
  /// 宽度不变式：段内的间隔 = [kClassroomChipGap]，与外层 `Wrap.spacing` 同值，
  /// 所以合并前后总宽不变。
  /// 星期格（周一到周日）：选中 = 与节次同一档的**红实心件**。
  ///
  /// 用户 2026-09-20 四轮：「我希望按钮选中后也要显示 c62828，而不是黑色」——
  /// 从前星期格选中只有「紫色文字 + 淡描边」，在深色卡片上等于没有选中感；
  /// 现在与 `_periodRun` 走同一套 `AppColors.errorFill / onErrorFill`。
  Widget _weekdayChip(BuildContext context, int d) {
    final selected = _weekdays.contains(d);
    final chip = _classroomChoiceChip(
      context,
      key: Key('classroomFreeWeekday-$d'),
      label: weekdayLabel(d),
      selected: selected,
      // 与节次格同一口径：选中 = 红实心件 + **无描边**（用户 2026-09-20 六轮）。
      side: selected ? const BorderSide(color: Colors.transparent) : null,
      selectedLabel: selected ? AppColors.onErrorFill(context) : null,
      selectedFill: AppColors.errorFill(context),
      onTap: () => setState(() {
        if (selected) {
          _weekdays.remove(d);
        } else {
          _weekdays.add(d);
        }
      }),
    );
    if (!selected) return chip;
    return _chipFill(
      context,
      color: AppColors.errorFill(context),
      key: Key('classroomFreeWeekdayFill-$d'),
      child: chip,
    );
  }

  Widget _periodRun(BuildContext context, List<int> run, Set<int> periods) {
    // 用户 2026-09-20：「单个按钮被选中，显示为 #C62828 底；连续选中的按钮之间要显示为
    // 用 #C62828 连接」—— 就是成绩页那套**红实心件**（`AppColors.errorFill`：浅色 =
    // scheme.error、深色 = 深红 #C62828；前景走 `onErrorFill`，两侧都是白字）。
    final fill = AppColors.errorFill(context);
    final onFill = AppColors.onErrorFill(context);
    final merged = run.length > 1;
    Widget cell(int p, {BorderRadius? radius}) {
      final selected = periods.contains(p);
      return _classroomChoiceChip(
        context,
        key: Key('classroomFreePeriod-$p'),
        label: '$p',
        selected: selected,
        // 用户 2026-09-20 六轮：「被选中的节数按钮不要显示边框」—— 选中态只留那块红实心件，
        // 描边一律透明（否则红底上还要套一圈灰框）；未选中仍保留细描边。
        side: selected ? const BorderSide(color: Colors.transparent) : null,
        radius: radius,
        selectedLabel: onFill,
        selectedFill: fill,
        onTap: () => _togglePeriod(p, periods),
      );
    }

    if (!merged) {
      final only = run.first;
      final chip = cell(only);
      if (!periods.contains(only)) return chip;
      return _chipFill(
        context,
        color: fill,
        key: Key('classroomFreePeriodFill-${run.first}'),
        child: chip,
      );
    }

    // 合并段 = **一整块**：段内格子的圆角一律削平，只有段首 / 段尾保留 8 圆角（与外层
    // `_chipFill` 的圆角对齐），格子之间的 6px 由格子自己的红色铺满 —— 于是缝里也是
    // 同一块红，不再依赖「父容器从缝里透出来」，屏幕像素上不可能再出现断口
    // （用户 2026-09-20 七轮：「看起来还是不连续，感觉是按钮边框的问题」）。
    const radius = Radius.circular(8);
    BorderRadius radiusAt(int i) {
      if (i == 0) return const BorderRadius.horizontal(left: radius);
      if (i == run.length - 1) {
        return const BorderRadius.horizontal(right: radius);
      }
      return BorderRadius.zero;
    }

    return _chipFill(
      context,
      color: fill,
      key: Key('classroomFreePeriodRun-${run.first}-${run.last}'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < run.length; i++) ...[
            if (i > 0) _runGap(),
            // 段内格子方角 + 选中态透明描边：格子之间那 6px 由外层 `_chipFill` 的同一块红
            // 铺满（`_runGap()` 只占位、不画东西）→ 屏幕上是一整块，看不出「按钮」。
            cell(run[i], radius: radiusAt(i)),
          ],
        ],
      ),
    );
  }

  /// 选中态那张圆角实心底（独立格与合并段共用同一个底色 = 调用方给的红实心件档）。
  Widget _chipFill(
    BuildContext context, {
    required Color color,
    required Widget child,
    Key? key,
  }) => Container(
    key: key,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  /// 合并段内部的**透明**占位（宽 = [kClassroomChipGap]，不改变总宽）。
  ///
  /// 用户 2026-09-20 六轮：「相连的节数按钮之间不要显示分割线」—— 从前这里画一条
  /// 1px 淡白线分格，现在整块红连成一片，只留等宽占位：几何不变式（合并前后总宽一致、
  /// 后面的格子不挪位）仍然成立，只是画面上看不出分格。
  Widget _runGap() => const SizedBox(width: kClassroomChipGap);

  /// 点某一节：先接管「自动选出来的那一段」，再改这一节，之后不再被自动覆盖。
  void _togglePeriod(int p, Set<int> periods) {
    final next = <int>{...periods};
    if (next.contains(p)) {
      next.remove(p);
    } else {
      next.add(p);
    }
    setState(() {
      _periodsTouched = true;
      _periods
        ..clear()
        ..addAll(next);
    });
  }
  // ---------------- 模式 A：按时间找教室 ----------------

  List<Widget> _byTimeBody(
    BuildContext context,
    PublicQueryTerm? term,
    List<ClassroomInfo> infos, {
    required Set<int> periods,
    required ({int start, int end})? auto,
  }) {
    final request = _timeRequest(term);
    return [
      _whenCard(context, periods: periods, auto: auto),
      const SizedBox(height: 12),
      if (request == null)
        _noticeCard(
          context,
          Icons.touch_app_outlined,
          '先选一个校区',
          '教室是按校区排的 —— 选好校区（可选再选一栋楼）再挑周次和节次。',
        )
      else
        ..._timeResult(context, request, infos, periods: periods),
    ];
  }

  Widget _whenCard(
    BuildContext context, {
    required Set<int> periods,
    required ({int start, int end})? auto,
  }) {
    return Card(
      elevation: 0,
      shape: geCardShape(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            geCardTitle(
              context,
              text: '时间条件',
              accent: fp(context).publicQuery,
            ),
            const SizedBox(height: 6),
            _row(
              context,
              icon: Icons.calendar_view_week_outlined,
              label: '教学周',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const Key('classroomFreeWeek'),
                  isExpanded: true,
                  value: _week,
                  items: [
                    for (var w = 1; w <= kClassroomFreeWeeks; w++)
                      DropdownMenuItem(value: w, child: Text('第 $w 周')),
                  ],
                  onChanged: (v) => setState(() => _week = v ?? 1),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '星期（可多选，默认今天；选几个就要求这几天都空）',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: kClassroomChipGap,
              runSpacing: 4,
              children: [
                for (var d = 1; d <= 7; d++) _weekdayChip(context, d),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '节次（1-12 每节独立，可多选 —— 勾中的节次都空才列出）',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('classroomFreePeriodAuto'),
                  onPressed: _resetPeriodsToNow,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('按现在时间'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: kClassroomChipGap,
              runSpacing: 4,
              children: [
                for (final run in classroomPeriodRuns(periods))
                  _periodRun(context, run, periods),
              ],
            ),
            if (auto != null && !_periodsTouched) ...[
              const SizedBox(height: 6),
              Text(
                _autoPeriodHint(auto),
                key: const Key('classroomFreePeriodAutoHint'),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 报表失败时的文案。
  ///
  /// ⚠ 教务在**整个校区**那种超大报表上会翻车：实测同一会话打
  /// `dykb.GS1.jsp?kblx=jsikb`（不选楼房 = 整校区，1.7 MB）时服务端有时直接回
  /// 那张 `凭证已失效` 的 alert 页（「凭证已失效，请重新登录！」）——**登录并没有过期**
  /// （同一时刻 klass / course 报表都正常，选一栋楼房的教室课表也正常）。
  /// 所以这里必须把话说清楚，并直接给「先选楼房」这条可执行的路。
  String _reportErrorMessage(Object? error) {
    final text = '$error';
    if (_building.isEmpty && text.contains('凭证')) {
      return '教务这一趟没返回数据：整个校区的教室课表太大，服务端直接回了'
          '「凭证已失效」页（不是你的登录过期 —— 同一个会话查班级/课程课表都正常）。\n'
          '先在上面「楼房」里选一栋教学楼再查，或者点「重试」。';
    }
    return '教室课表加载失败：$text';
  }

  List<Widget> _timeResult(
    BuildContext context,
    PublicQueryRequest request,
    List<ClassroomInfo> infos, {
    required Set<int> periods,
  }) {
    final async = ref.watch(publicQueryReportProvider(request));
    final result = async.valueOrNull;
    if (result == null) {
      return [
        if (async.hasError)
          _errorNotice(context, _reportErrorMessage(async.error))
        else
          _noticeCard(
            context,
            Icons.hourglass_empty,
            '正在拉取教室课表…',
            _building.isEmpty && _campus.isNotEmpty
                ? '整个校区的教室课表比较大，第一次可能要几十秒；期间可以在上面换条件。'
                : '稍等一下。',
          ),
      ];
    }
    // 选了楼房时**只信报表**：教室清单接口的 `lf_m` 不生效（给的是全校区），
    // 灌进来会把别的楼的教室当成「空闲」。
    final occupancies = classroomOccupanciesOf(
      timetables: result.timetables,
      rooms: _building.isEmpty ? infos : const <ClassroomInfo>[],
    );
    final blocks = _periodBlocks(periods);
    final hits = freeClassroomsAt(
      rooms: occupancies,
      week: _week,
      weekdays: _weekdays,
      startPeriod: blocks.isEmpty ? 1 : blocks.first.$1,
      endPeriod: blocks.isEmpty ? 1 : blocks.last.$2,
      periodBlocks: blocks,
    );
    return [
      if (_weekdays.isEmpty)
        _noticeCard(
          context,
          Icons.error_outline,
          '至少选一个星期',
          '没有选星期就没有可查的时段。',
        )
      else if (blocks.isEmpty)
        _noticeCard(
          context,
          Icons.error_outline,
          '至少选一个节次',
          '节次可以多选（勾中的时段都空的教室才会列出）；一个都没勾就没法算。',
        )
      else
        ClassroomFreeListView(
          hits: hits,
          totalRooms: occupancies.length,
          week: _week,
          weekdays: _weekdays.toList()..sort(),
          periodLabel: classroomPeriodBlocksLabel(blocks),
          onPick: (room) => setState(() {
            _room = ClassroomInfo(
              code: room.code,
              name: room.name,
              capacity: room.capacity,
              kind: room.kind,
            );
            _mode = ClassroomFreeMode.byRoom;
          }),
        ),
      const SizedBox(height: 10),
      Text(
        _building.isEmpty
            ? '范围：${_scopeLabel()}（整个校区）。没有排课记录的教室按「整学期空闲」计入。'
            : '范围：${_scopeLabel()}。选了楼房时只列**该楼有排课记录**的教室'
                  '（从没排过课的教室不在教务报表里）。',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.5,
          color: AppColors.textMuted(context),
        ),
      ),
    ];
  }

  String _scopeLabel() {
    final campus = ref
        .read(publicQueryCampusesProvider)
        .valueOrNull
        ?.where((c) => c.code == _campus)
        .map((c) => c.displayName)
        .firstOrNull;
    final buildings = ref
        .read(publicQueryBuildingsProvider(_campus))
        .valueOrNull;
    final building = buildings
        ?.where((b) => b.code == _building)
        .map((b) => b.displayName)
        .firstOrNull;
    return [
      if (campus != null && campus.isNotEmpty) campus,
      if (building != null && building.isNotEmpty) building,
    ].join(' · ');
  }

  // ---------------- 模式 B：按教室查空闲 ----------------

  List<Widget> _byRoomBody(
    BuildContext context,
    PublicQueryTerm? term,
    List<ClassroomInfo> infos,
  ) {
    final room = _room;
    final request = _roomRequest(term, infos);
    return [
      Card(
        elevation: 0,
        shape: geCardShape(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              geCardTitle(
                context,
                text: '选教室',
                accent: fp(context).publicQuery,
                trailing: TextButton.icon(
                  key: const Key('classroomFreePickRoom'),
                  onPressed: _campus.isEmpty
                      ? null
                      : () => _pickRoom(context, infos),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('选择教室'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                room == null
                    ? '还没选教室 —— 点右上「选择教室」（可以按名称搜）。'
                    : [room.name, if (room.kind.isNotEmpty) room.kind]
                          .join(' · '),
                key: const Key('classroomFreeRoomLabel'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: room == null
                      ? AppColors.textMuted(context)
                      : AppColors.textBase(context),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _includeWeekend,
                onChanged: (v) => setState(() => _includeWeekend = v),
                title: const Text('把周末也算进来'),
              ),
              _row(
                context,
                icon: Icons.timelapse_outlined,
                label: '最短连续',
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    key: const Key('classroomFreeMinPeriods'),
                    isExpanded: true,
                    value: _minPeriods,
                    items: [
                      for (var n = 1; n <= 4; n++)
                        DropdownMenuItem(value: n, child: Text('$n 节')),
                    ],
                    onChanged: (v) => setState(() => _minPeriods = v ?? 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (request == null)
        _noticeCard(
          context,
          Icons.touch_app_outlined,
          room == null
              ? '先选一间教室'
              : _campus.isEmpty
              ? '先选校区'
              : '这间教室在教室列表里找不到编号',
          room == null
              ? '教室是按校区取数的：先选校区，再点「选择教室」。'
              : _campus.isEmpty
              ? '教室是按校区取数的：先选校区，再点「选择教室」。'
              : '教室名与教务清单对不上（可能是当年停用的教室）。点「选择教室」换一间。',
        )
      else
        ..._roomResult(context, request, room!),
    ];
  }

  List<Widget> _roomResult(
    BuildContext context,
    PublicQueryRequest request,
    ClassroomInfo info,
  ) {
    final async = ref.watch(publicQueryReportProvider(request));
    final result = async.valueOrNull;
    if (result == null) {
      return [
        if (async.hasError)
          _errorNotice(context, _reportErrorMessage(async.error))
        else
          _noticeCard(
            context,
            Icons.hourglass_empty,
            '正在拉取这间教室的课表…',
            '稍等一下。',
          ),
      ];
    }
    final parsed = classroomOccupanciesOf(
      timetables: result.timetables,
      rooms: [info],
    );
    final room = parsed.firstWhere(
      (o) => o.slots.isNotEmpty,
      orElse: () => parsed.isEmpty
          ? ClassroomOccupancy(name: info.name, kind: info.kind, capacity: info.capacity)
          : parsed.first,
    );
    final common = roomCommonFreeWindows(
      room: room,
      weeks: [for (var w = 1; w <= kClassroomFreeWeeks; w++) w],
      includeWeekend: _includeWeekend,
      minPeriods: _minPeriods,
    );
    return [
      ClassroomRoomFreeView(
        room: room,
        week: _week,
        lastWeek: kClassroomFreeWeeks,
        commonWindows: common,
        includeWeekend: _includeWeekend,
        minPeriods: _minPeriods,
        onWeekChanged: (w) => setState(() => _week = w),
      ),
    ];
  }

  Future<void> _pickRoom(
    BuildContext context,
    List<ClassroomInfo> infos,
  ) async {
    final async = ref.read(publicQueryClassroomsProvider('$_campus|'));
    if (async.isLoading && infos.isEmpty) {
      _toast('教室列表还在加载，稍等一下');
    }
    final picked = await showModalBottomSheet<ClassroomInfo>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RoomPickerSheet(
        rooms: infos,
        selectedCode: _room?.code ?? '',
      ),
    );
    if (picked == null) return;
    setState(() => _room = picked);
  }

  // ---------------- 小件 ----------------

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) => Row(
    children: [
      Icon(icon, size: 17, color: AppColors.textMuted(context)),
      const SizedBox(width: 8),
      SizedBox(
        width: 64,
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted(context)),
        ),
      ),
      Expanded(child: child),
    ],
  );

  Widget _noticeCard(
    BuildContext context,
    IconData icon,
    String title,
    String body,
  ) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorNotice(BuildContext context, String message) => Card(
    elevation: 0,
    shape: geCardShape(context),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            key: const Key('classroomFreeError'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('classroomFreeRetry'),
            onPressed: _refreshAll,
            child: const Text('重试'),
          ),
        ],
      ),
    ),
  );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

/// 教室选择面板（按名称 / 类型 / 楼房搜）。
class _RoomPickerSheet extends StatefulWidget {
  const _RoomPickerSheet({required this.rooms, this.selectedCode = ''});

  final List<ClassroomInfo> rooms;
  final String selectedCode;

  @override
  State<_RoomPickerSheet> createState() => _RoomPickerSheetState();
}

class _RoomPickerSheetState extends State<_RoomPickerSheet> {
  final _controller = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ClassroomInfo> get _filtered {
    final key = normalizePublicQueryName(_keyword);
    if (key.isEmpty) return widget.rooms;
    return widget.rooms
        .where(
          (r) =>
              normalizePublicQueryName(r.name).contains(key) ||
              normalizePublicQueryName(r.kind).contains(key),
        )
        .toList();
  }

  /// 把教室按「楼房 + 楼层」摊平成「组标题 + 教室行」的一条惰性列表。
  ///
  /// 用户 2026-09-19：「查找空教室功能，教室应该分楼层显示」——
  /// 分组口径与结果清单同一个（`domain/classroom_free.dart` 的 `groupClassroomsByFloor`）。
  List<Object> _roomRows(List<ClassroomInfo> rooms) {
    final rows = <Object>[];
    for (final group in groupClassroomsByFloor(rooms)) {
      rows.add(group);
      rows.addAll(group.items);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _filtered;
    final roomRows = _roomRows(rooms);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '选择教室',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('classroomFreeRoomSearch'),
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '搜教室名 / 类型，如 三教3101、机房',
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: rooms.isEmpty
                  ? Center(
                      child: Text(
                        widget.rooms.isEmpty
                            ? '这个校区还没取到教室列表'
                            : '没有匹配的教室',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('classroomFreeRoomList'),
                      itemCount: roomRows.length,
                      itemBuilder: (context, i) {
                        final row = roomRows[i];
                        // 组标题（楼房 + 楼层）与教室行同列在一条惰性列表里。
                        if (row is ClassroomFloorGroup<ClassroomInfo>) {
                          return classroomFloorHeader(
                            context,
                            label: row.label,
                            count: row.count,
                          );
                        }
                        final room = row as ClassroomInfo;
                        return ListTile(
                          key: Key('classroomFreeRoomOption-${room.code}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            room.name,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            room.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted(context),
                            ),
                          ),
                          trailing: room.code == widget.selectedCode
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: fp(context).publicQuery,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(room),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
