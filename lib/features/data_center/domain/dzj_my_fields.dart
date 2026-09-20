/// 「我的」页 × 学校个人数据中心（竹简）的字段合并口径。
///
/// 用户 2026-09-20 七轮原话：「我的页不显示从数据中心添加的信息，我希望这部分数据要换
/// 个颜色显示，如果原来的地方就有数据，则不覆盖，如果与已有数据冲突，则显示为『冲突』，
/// 然后点击显示冲突详情」。
///
/// 三条规则（[dzjMergeFields] 的唯一实现，别在界面层各写一套）：
/// 1. **本地优先**：本地（学籍缓存）有值就显示本地值，**数据中心的值绝不覆盖**；
/// 2. **本地空 → 用数据中心的值**，并且用 [FeaturePalette.dzjSource] 那个颜色显示，
///    让用户一眼看出「这条不是学籍里的」；
/// 3. **两边都有且不一样 → 显示本地值 + 一枚「冲突」胶囊**，点开看两份值各自的来源。
///
/// ⚠ 学校「基本信息」页（`13ba9ece95a8`）从前取不到数（唯一组件 `u:73ab7f26af38` 的
/// SQL 是占位符 `select * from t_sys_user`）。**2026-09-20 八轮已打通**：真实端点是
/// `POST /api/app/component/tsa/getFormData`（见 `dzj_basic_info.dart` 的 [DzjBasicField]），
/// 39 项字段全有真值 —— 「我的」页现在把这一份也一起合并。
library;

import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';

/// 数据中心能取到、且「我的」页有落位的字段。
///
/// `label` = **「我的」页那一行的标签**（合并按它对位）；`source` = 界面上标注的来源。
enum DzjMyField {
  name('姓名', 'u:97019a44a735', 'username', '个人首页'),
  cardNo('一卡通号', 'u:6e8a5f94005d', 'userid', '个人首页'),
  college('院系', 'u:a56e2d07cc33', 'ssdw', '个人首页'),
  headTeacher('班主任', 'u:ee1581a17fe0', 'bzrxm', '个人首页'),
  headTeacherPhone('班主任电话', 'u:3acfa51c6b45', 'bzrsjh', '个人首页'),
  dormScore('宿舍评分', 'u:07f890f5688a', 'fs', '住宿信息');

  const DzjMyField(this.label, this.componentId, this.valueKey, this.source);

  /// 「我的」页那一行的标签（也是合并的键）。
  final String label;

  /// 竹简组件 id。
  final String componentId;

  /// 组件回包里的字段名。
  final String valueKey;

  /// 页面上标注的来源（数据中心里的位置）。
  final String source;
}

/// 一行字段的合并结果。
enum DzjFieldState {
  /// 两边都空 —— 不显示任何东西。
  empty,

  /// 只有数据中心有值（本地没有）：用它，标成数据中心色。
  fromCenter,

  /// 两边一致：显示本地值，不做任何装饰（「不覆盖」的直接体现）。
  same,

  /// 两边都是值但不一样：显示本地值 + 「冲突」胶囊。
  conflict,
}

/// 一行「我的」页字段的最终形态。
class DzjFieldMerge {
  const DzjFieldMerge({
    required this.label,
    required this.local,
    required this.remote,
    this.source = '',
  });

  /// 枚举驱动的那一份（[DzjMyField] 的六个字段：个人首页 / 住宿信息）。
  factory DzjFieldMerge.of(
    DzjMyField f, {
    required String local,
    required String remote,
  }) => DzjFieldMerge(
    label: f.label,
    local: local,
    remote: remote,
    source: f.source,
  );

  /// 「我的」页那一行的标签（也是合并的键）。
  final String label;

  /// 本地（学籍缓存 / 账号）里的值。
  final String local;

  /// 学校数据中心返回的值。
  final String remote;

  /// 数据中心那一份的出处（界面上标注「数据中心 · <来源>」）。
  final String source;

  String get localValue => _clean(local);

  String get remoteValue => _clean(remote);

  DzjFieldState get state {
    if (localValue.isEmpty && remoteValue.isEmpty) return DzjFieldState.empty;
    if (localValue.isEmpty) return DzjFieldState.fromCenter;
    if (remoteValue.isEmpty) return DzjFieldState.same;
    return dzjSameValue(localValue, remoteValue)
        ? DzjFieldState.same
        : DzjFieldState.conflict;
  }

  /// 界面上最终显示的值（**本地优先**）。
  String get value => localValue.isNotEmpty ? localValue : remoteValue;

  /// 本地空、数据中心有 → 该换色显示。
  bool get usesCenterValue => state == DzjFieldState.fromCenter;

  bool get isConflict => state == DzjFieldState.conflict;

  /// 这一行要不要出现在页面上（两边都空就不占版面）。
  bool get visible => state != DzjFieldState.empty;
}

/// 值等价判定：去首尾空白、全角空格、压缩中间空白、忽略大小写，另外两条例外：
///
/// - **尾部残留的分隔符不算差异**：学籍 XML 里籍贯常写成「江西省\」（实测该账号就是），
///   逐字符比会把「江西省」和「江西省\」标成冲突；
/// - **明确等价的两种写法不算差异**：性别「男」↔「男性」（学籍写「男」、学工系统写
///   「男性」）。这不是「两个来源说法冲突」，标成冲突只会让用户点开一个没有信息的弹窗。
///
/// ⚠ 只收**明确等价**的写法（见 [_dzjValueAliases]），别把不同说法混为一谈：学院名
/// 「计算机与人工智能学院」vs「计算机学院」、班级名「计算机科学与技术252」vs
/// 「25计算机2班」、手机号两份不同 —— 这些**必须**继续报冲突（实测该账号正是这三条）。
bool dzjSameValue(String a, String b) {
  final na = _norm(a), nb = _norm(b);
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  final ka = _dzjValueAliases[na];
  return ka != null && ka == _dzjValueAliases[nb];
}

/// 同义写法 → 归一化键（只收明确等价的一对，新增前先问「这两种写法会不会指向不同的
/// 事实」）。
const Map<String, String> _dzjValueAliases = <String, String>{
  '男': 'sex:male',
  '男性': 'sex:male',
  '女': 'sex:female',
  '女性': 'sex:female',
};

String _norm(String s) {
  var t = s
      .replaceAll('\u3000', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  // 尾部残留的分隔符（`江西省\` / `25计算机2班/`）——
  t = t.replaceAll(RegExp(r'[\\/|,，、;；:：]+$'), '').trim();
  return t;
}

/// 去掉首尾空白与全角空格（值本身保留原样，只用于「有没有值」与等值比较）。
/// 中间的空白**不压缩** —— 那会改掉显示出来的值；压缩只发生在 [dzjSameValue] 的比较里。
String _clean(String s) =>
    s.replaceAll('\u3000', ' ').trim();

/// 合并：`local` 是「我的」页各行的本地值、`remote` 是数据中心取回的值，键都用行标签。
///
/// [labels] 缺省 = [DzjMyField] 的六个标签；「我的」页会把**「基本信息」表单的 39 项**
/// （[DzjBasicField.label]）一并传进来 —— 那 39 项的值来自另一个端点
/// （`tsa/getFormData`，见 `dzj_basic_info.dart`），但合并/换色/冲突的口径完全一样，
/// 所以走同一个函数（用户 2026-09-20 八轮：「基本信息页有大量的信息没有并入我的页」）。
///
/// 返回顺序 = 传入标签的顺序（界面按卡片分组取用，顺序只保证稳定）。
List<DzjFieldMerge> dzjMergeFields({
  required Map<String, String> local,
  required Map<String, String> remote,
  Iterable<String>? labels,
}) {
  String pick(Map<String, String> m, String k) => (m[k] ?? '').trim();
  final all = <String>{
    if (labels == null)
      for (final f in DzjMyField.values) f.label
    else
      ...labels,
  };
  return <DzjFieldMerge>[
    for (final label in all)
      DzjFieldMerge(
        label: label,
        local: pick(local, label),
        remote: pick(remote, label),
        source: dzjFieldSourceOf(label),
      ),
  ];
}

/// 某个行标签对应的**数据中心出处**（冲突详情里要写清楚是哪一份）：
/// 枚举里那六个来自个人首页 / 住宿信息，其余（基本信息表单）来自学工系统。
String dzjFieldSourceOf(String label) {
  for (final f in DzjMyField.values) {
    if (f.label == label) return f.source;
  }
  return dzjBasicInfoSource;
}

/// 按标签取一行（界面里 `merges['姓名']`）。
Map<String, DzjFieldMerge> dzjMergeMap(List<DzjFieldMerge> merges) => <String, DzjFieldMerge>{
  for (final m in merges) m.label: m,
};

/// 冲突详情里的两份值（[localSource] 只有标注用途）。
class DzjConflictDetail {
  const DzjConflictDetail({
    required this.label,
    required this.local,
    required this.remote,
    required this.source,
  });

  final String label;
  final String local;
  final String remote;
  final String source;
}

DzjConflictDetail dzjConflictOf(DzjFieldMerge m) => DzjConflictDetail(
  label: m.label,
  local: m.local,
  remote: m.remote,
  source: m.source,
);
