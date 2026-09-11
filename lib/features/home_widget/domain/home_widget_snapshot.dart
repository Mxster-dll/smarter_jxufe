import 'dart:convert';

/// 桌面小组件的指标种类（与原生 `res/xml/home_widget_*_info.xml` 一一对应）。
enum HomeWidgetMetric {
  /// 仪表盘：一卡汇总首页「数据一览」的多项指标（走 [HomeWidgetSnapshot.cells]）。
  dashboard('dashboard', '数据一览'),
  electricity('electricity', '电费余额'),
  grades('grades', '课程加权');

  const HomeWidgetMetric(this.key, this.defaultLabel);

  final String key;
  final String defaultLabel;

  static HomeWidgetMetric? fromKey(String? key) {
    for (final m in HomeWidgetMetric.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// 「指标:尺寸」键 —— 某个（指标 × 尺寸）档位在桌面上的唯一标识。
///
/// 与原生 `HomeWidgetBridge.pinKey` **必须完全一致**（守卫测试盯着两处）：
/// 设置页用它查「这一档已经在桌面放了几个」，以及做「刚请求的那次到底
/// 落桌面没有」的检测（华为桌面不触发 requestPinAppWidget 的 PendingIntent
/// 回调，只能靠已绑定实例数差值判断）。
String homeWidgetPinKey(HomeWidgetMetric metric, String size) =>
    '${metric.key}:$size';

/// 仪表盘里的一格：短标题 + 短数值（如「电费 120.9」「今日 3 节」）。
///
/// 标签一律取两字短名：最窄的 2×1 档每格只有约 55dp，四字标签放不下。
class HomeWidgetCell {
  final String label;
  final String value;

  const HomeWidgetCell({required this.label, required this.value});

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  static HomeWidgetCell? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = (raw['label'] as String?) ?? '';
    final value = (raw['value'] as String?) ?? '';
    if (label.isEmpty && value.isEmpty) return null;
    return HomeWidgetCell(label: label, value: value);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetCell && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label=$value';
}

/// 小组件数据状态。
enum HomeWidgetState {
  /// 有可用数值。
  ok('ok'),

  /// 数据源正常但暂无内容（未绑定宿舍 / 暂无成绩）。
  empty('empty'),

  /// 拉取失败或登录态失效。
  error('error');

  const HomeWidgetState(this.key);

  final String key;

  static HomeWidgetState fromKey(String? key) {
    for (final s in HomeWidgetState.values) {
      if (s.key == key) return s;
    }
    return HomeWidgetState.error;
  }
}

/// 一份小组件快照 —— Flutter 算好、原生只负责渲染。
///
/// 原生渲染约定（`RemoteViews`）：
/// - 单值卡（电费 / 成绩）[state] == ok：大字 [value] + 小字 [unit]，
///   下方 [sub1]、[sub2]；其他状态：正文显示 [message]（[value] 不显示）；
/// - 仪表盘：读 [cells]（最多 5 格），非 ok 时整卡显示 [message]；
/// - [accent] 为 `#RRGGBB`，非 ok 状态由原生置灰。
///
/// 注：原生实际取色以 `values(-night)/colors.xml` 为准（深色模式要自动提亮），
/// [accent] 作为兜底并充当「Dart 调色板 ↔ 原生资源」漂移守卫的锚点。
class HomeWidgetSnapshot {
  final HomeWidgetMetric metric;
  final String label;
  final String value;
  final String unit;

  /// 窄尺寸（2×1）用的短数值；空则回退 [value]。
  final String valueShort;

  /// 第二行副文本（如「房间 05602」「专业排名 第 3 名」）。
  final String sub1;

  /// 第三行副文本（通常是更新时间）。
  final String sub2;
  final HomeWidgetState state;

  /// 非 ok 状态的说明文案。
  final String message;

  /// 数据时间戳（毫秒）。
  final int updatedAt;

  /// 品牌点缀色 `#RRGGBB`（取自 `lib/design/feature_palette.dart`）。
  final String accent;

  /// 仪表盘的格子列表（其余指标为空）。网格容量小的尺寸档由原生取前 N 格。
  final List<HomeWidgetCell> cells;

  const HomeWidgetSnapshot({
    required this.metric,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub1,
    required this.sub2,
    required this.state,
    required this.message,
    required this.updatedAt,
    required this.accent,
    this.valueShort = '',
    this.cells = const [],
  });

  Map<String, Object?> toJson() => {
    'metric': metric.key,
    'label': label,
    'value': value,
    'valueShort': valueShort,
    'unit': unit,
    'sub1': sub1,
    'sub2': sub2,
    'state': state.key,
    'message': message,
    'updatedAt': updatedAt,
    'accent': accent,
    'cells': [for (final c in cells) c.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static HomeWidgetSnapshot? fromJson(Map<String, Object?> json) {
    final metric = HomeWidgetMetric.fromKey(json['metric'] as String?);
    if (metric == null) return null;
    return HomeWidgetSnapshot(
      metric: metric,
      label: (json['label'] as String?) ?? metric.defaultLabel,
      value: (json['value'] as String?) ?? '',
      valueShort: (json['valueShort'] as String?) ?? '',
      unit: (json['unit'] as String?) ?? '',
      sub1: (json['sub1'] as String?) ?? '',
      sub2: (json['sub2'] as String?) ?? '',
      state: HomeWidgetState.fromKey(json['state'] as String?),
      message: (json['message'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      accent: (json['accent'] as String?) ?? '#9E9E9E',
      cells: cellsFromJson(json['cells']),
    );
  }

  /// 容错解析格子列表：非列表 → 空；单格损坏 / 空 → 丢弃该格。
  static List<HomeWidgetCell> cellsFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <HomeWidgetCell>[];
    for (final item in raw) {
      final cell = HomeWidgetCell.fromJson(item);
      if (cell != null) out.add(cell);
    }
    return out;
  }

  static HomeWidgetSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {
      return null;
    }
  }

  /// 「更新于 09-11 02:30」——统一在此格式化，原生不再处理日期。
  static String updatedLabel(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '更新于 ${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
  }
}
