import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/tice/data/models/tice_models.dart';
import 'package:smarter_jxufe/features/tice/data/providers/tice_providers.dart';
import 'package:smarter_jxufe/features/tice/data/tice_remote_datasource.dart';
import 'package:smarter_jxufe/features/tice/data/tice_stu_num.dart';

/// 体测成绩页（仅查当前登录账号本人）。
///
/// 数据源为微信小程序「赛康精益」后端（www.skjycx.com），零鉴权接口；
/// 学号自动取自当前登录账号，页面只提供测试年度切换。
/// 视觉遵循 App 同源语言（白卡细描边圆角 8 + 主色浅底图标盒）。
class TiceScreen extends ConsumerStatefulWidget {
  const TiceScreen({super.key});

  @override
  ConsumerState<TiceScreen> createState() => _TiceScreenState();
}

class _TiceScreenState extends ConsumerState<TiceScreen> {
  /// 查询年度（窗口日期取该年 11-01），默认去年（当季秋季体测通常次年才出）。
  late int _year = DateTime.now().year - 1;

  /// 入学年份（体测查询下界）；解析出前为 null（回退固定近 5 年窗口）。
  int? _enrollYear;

  bool _loading = true;
  String? _error;
  TiceResult? _result;

  /// 请求序号：切年度/重试时自增，过期响应丢弃。
  int _requestSeq = 0;

  TiceRemoteDataSource get _dataSource =>
      ref.read(ticeRemoteDataSourceProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _resolveEnrollYear();
  }

  /// 解析入学年份：成功后年度条按「入学年…今年」渲染；
  /// 若默认学年早于入学年（如刚入学新生），校正默认学年并重查。
  Future<void> _resolveEnrollYear() async {
    final enrollYear = await resolveTiceEnrollYear(ref);
    if (!mounted) return;
    final now = DateTime.now().year;
    final inRange = enrollYear == null || (enrollYear <= now && _year >= enrollYear);
    setState(() => _enrollYear = enrollYear);
    if (enrollYear == null) return;
    if (!inRange && _year < enrollYear && enrollYear <= now) {
      _year = enrollYear;
      await _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });

    // 学号优先取教务学生信息（7 位学号，登录时已缓存），
    // 登录账号（一卡通/统一身份）≠ 体测库学号，仅作兜底。
    final stuNum = await resolveTiceStuNum(ref);
    if (stuNum.isEmpty) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = '未获取到学号，请先登录后重试';
      });
      return;
    }

    try {
      final result = await _dataSource.query(stuNum, _year);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _result = result;
      });
    } on TiceRequestException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = '查询出错：$e';
      });
    }
  }

  void _selectYear(int year) {
    if (year == _year) return;
    setState(() => _year = year);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('体测成绩'), centerTitle: true),
      body: Column(
        children: [
          _buildYearBar(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 测试年度切换条（入学年份…今年；入学年未知时回退近 5 年窗口）。
  Widget _buildYearBar() {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final enroll = _enrollYear;
    final first = (enroll != null && enroll <= now.year) ? enroll : now.year - 4;
    final years = [for (var y = first; y <= now.year; y++) y];
    return Container(
      color: Theme.of(context).cardTheme.color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final y in years) ...[
                    ChoiceChip(
                      label: Text('$y 学年'),
                      selected: y == _year,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _selectYear(y),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在查询体测成绩…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return _buildStatus(
        icon: Icons.cloud_off_outlined,
        title: '查询失败',
        message: _error!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return _buildStatus(
        icon: Icons.help_outline,
        title: '无法查询',
        message: '未取得有效响应',
      );
    }
    if (!result.ok) {
      return _buildStatus(
        icon: Icons.event_busy_outlined,
        title: '暂无该学年成绩',
        message: result.message,
        action: TextButton.icon(
          onPressed: () => _selectYear(_year - 1),
          icon: const Icon(Icons.history),
          label: const Text('查看上一学年'),
        ),
      );
    }
    return _buildContent(result);
  }

  Widget _buildStatus({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // ---------- 数据内容 ----------

  Widget _buildContent(TiceResult result) {
    final latest = result.years.last; // 命中窗口通常仅一条
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (result.info != null) _buildInfoCard(result.info!),
        const SizedBox(height: 12),
        _buildTotalCard(latest),
        const SizedBox(height: 20),
        _buildSectionTitle('分项成绩'),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: _buildLegendRow(),
        ),
        const SizedBox(height: 6),
        _buildItemsCard(latest.items),
        const SizedBox(height: 8),
        Text(
          '数据来源：赛康精益体测平台 · 仅展示第 ${latest.year} 学年成绩\n'
          '耐力跑男生 1000 米、女生 800 米；末项男生为引体向上、女生为仰卧起坐',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.6,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  /// 学生档案卡。
  Widget _buildInfoCard(TiceStuInfo info) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      scheme,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              info.stuName.isEmpty ? '生' : info.stuName.characters.first,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        info.stuName.isEmpty ? '（未返回姓名）' : info.stuName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (info.stuSex.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _sexChip(info.stuSex),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '学号 ${info.stuNum}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: info.deptName.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.account_balance_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      info.deptName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sexChip(String sex) {
    final isMale = sex == '男';
    final color = isMale
        ? const Color(0xFF1565C0)
        : const Color(0xFFAD1457);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        sex,
        style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 总分大字卡。
  Widget _buildTotalCard(TiceYearResult latest) {
    final scheme = Theme.of(context).colorScheme;
    final totalScore = latest.totalScore;
    return _card(
      scheme,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${latest.year} 学年总分',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        totalScore == null
                            ? '--'
                            : totalScore.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '分',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (latest.totalGrade.isNotEmpty) _gradeChip(latest.totalGrade),
        ],
      ),
    );
  }

  /// 分级图例（<60 不及格 / 60-79 及格 / 80-89 良好 / ≥90 优秀）。
  Widget _buildLegendRow() {
    final scheme = Theme.of(context).colorScheme;
    const legend = [
      (Color(0xFFC62828), '不及格'),
      (Color(0xFFEF6C00), '及格'),
      (Color(0xFF0288D1), '良好'),
      (Color(0xFF2E7D32), '优秀'),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final (color, name) in legend)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                name,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 分项迷你定位条：<60 不及格 / 60-79 及格 / 80-89 良好 / ≥90 优秀
  /// 按真实宽度比例分段，白点标记该项得分位置。
  Widget _buildItemBar(double score) {
    const segments = [
      (60, Color(0xFFC62828)),
      (20, Color(0xFFEF6C00)),
      (10, Color(0xFF0288D1)),
      (10, Color(0xFF2E7D32)),
    ];
    final value = score.clamp(0.0, 100.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final maxDot = w < 12 ? 6.0 : w - 6.0;
        final dotX = (w * value / 100).clamp(6.0, maxDot);
        return SizedBox(
          height: 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 色段轨道：固定高度 8，杜绝无约束塌陷
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      for (final (flex, color) in segments)
                        Expanded(
                          flex: flex,
                          child: Container(color: color, height: 8),
                        ),
                    ],
                  ),
                ),
              ),
              // 白点定位标记：固定尺寸，跨轨道上下各溢出 2px
              Positioned(
                left: dotX - 5,
                top: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.35),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }

  /// 分项明细卡：每行 名称+原始值 | 得分 | 等级 chip。
  Widget _buildItemsCard(List<TiceItem> items) {
    final scheme = Theme.of(context).colorScheme;
    return _card(
      scheme,
      padding: EdgeInsets.zero,
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '该学年无分项明细',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  _itemRow(items[i]),
                ],
              ],
            ),
    );
  }

  Widget _itemRow(TiceItem item) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = item.result.isNotEmpty || item.score.isNotEmpty;
    final gradeColor = TiceGradeStyle.colorOf(item.grade);
    final scoreVal = double.tryParse(item.score);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasValue && item.grade.isEmpty
                      ? scheme.outline
                      : gradeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name.isEmpty ? item.code : item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.result.isEmpty ? '未记录' : '原始：${item.result}',
                      style:
                          TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.score.isEmpty ? '--' : '${item.score} 分',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: hasValue ? scheme.onSurface : scheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (item.grade.isNotEmpty) _gradeChip(item.grade),
                ],
              ),
            ],
          ),
          if (scoreVal != null) ...[
            const SizedBox(height: 8),
            _buildItemBar(scoreVal),
          ],
        ],
      ),
    );
  }

  /// 等级小胶囊（优秀/良好/及格/不及格 语义色）。
  Widget _gradeChip(String grade) {
    final color = TiceGradeStyle.colorOf(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        grade,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// App 同源白卡：细描边圆角 8，可选 [padding] 与 [bottom] 追加区。
  Widget _card(
    ColorScheme scheme, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    Widget? bottom,
  }) {
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: padding, child: child),
          ?bottom,
        ],
      ),
    );
  }
}
