/// 校内关系**名单**：来源组件 + 维度定义 + 一个人的解析/排序。
///
/// 用户 2026-09-19 二轮原话（两个页面都要）：
/// 「数据中心有两个可以查看相关同学的地方，一个是
/// https://dzj.jxufe.edu.cn/app/66eef481a9a3/228583a5077f ；一个是
/// https://dzj.jxufe.edu.cn/app/66eef481a9a3/82e98baafb40 点击校内关系后会弹窗显示的，
/// 这两个部分的同学名单我都要，但是后者可以查看学号班级和年级，前者只能看姓名学院；
/// 我希望都放入学生数据中心」
///
/// 对应到服务端就是**两个不同的组件**（[DzjPeerSource]）：
/// - `u:fcd2d17a9131`「校内关系」（页面 82e98baafb40）= 5 维，带学号/年级/班级/专业/校区；
/// - `u:af43933a919c`「相关人员」（页面 228583a5077f）= 6 维，只有姓名/性别/校园卡号/学院。
///
/// 为什么合成一个枚举：两边的**交互完全相同**（点人数 → 看名单），差别只在
/// `componentId` + `index` 两个数（[DzjPeerDimension.source] / [DzjPeerDimension.slot]），
/// 界面层、provider、弹层、行渲染全都共用一份实现 —— 拆两套必然分叉。
library;

/// 名单来源组件。
///
/// ⚠ 组件接口是**组件绑定**的：请求体里的 `sql` 一律被忽略，服务端用组件自带的 SQL，
/// 所以「从哪个组件取」只能靠 `componentId` 说清楚，不能自己写查询。
enum DzjPeerSource {
  /// 学生个人数据中心的「校内关系」组件（`school-relation-renderer`）。
  /// 行带 `ykth` 学号 / `username` 姓名 / `sznj` 年级 / `sex` 性别，
  /// 外加随维度走的一列：学院 `ssdw` / 班级 `ssbj` / 专业 `sszy` / 校区 `ssxq`。
  relation('u:fcd2d17a9131', '校内关系'),

  /// 「相关人员」页的组件（`data-xiangguan-render`，页面 `228583a5077f`）。
  /// 行只有 `username` / `sex` / `userid`|`kh`（校园卡号）/ `dept`（所属学院）。
  related('u:af43933a919c', '相关人员');

  const DzjPeerSource(this.componentId, this.title);

  /// 服务端组件 id。
  final String componentId;

  /// 界面文案（弹层副标题里标注名单出处）。
  final String title;
}

/// 一次名单查询 = 一个组件 + 一个指标位。
///
/// 前五个维度与「校内关系」五维人数（`dzjPeerCountsProvider` 那一份 map，
/// 见 `lib/features/data_center/data/providers/data_center_providers.dart`）
/// 的键**一一对应**；后六个来自「相关人员」页，键自带 `related` 前缀以免撞车。
enum DzjPeerDimension {
  grade('grade', '同年级', DzjPeerSource.relation, 0),
  classGroup(
    'class',
    '同班同学',
    DzjPeerSource.relation,
    1,
    gradeScoped: true,
  ),
  major(
    'major',
    '同年级同专业',
    DzjPeerSource.relation,
    2,
    gradeScoped: true,
  ),
  dorm('dorm', '舍友', DzjPeerSource.relation, 3),
  college('college', '同学院同生日', DzjPeerSource.relation, 4),

  /// 同年级 **+ 本人学院**（用户 2026-09-20 立项）：「同年级」行集再按 `ssdw` 过滤。
  ///
  /// 服务端组件没有这一维（内置 SQL 只有五路），但 `filterConfig` 认 SQL 谓词
  /// （[filterSql]）→ 仍然是**一次请求**，`total` 就是人数（实测 726）。
  /// 它的键**不在**「校内关系」五维人数那一份 map 里（那份来自服务端五路聚合），
  /// 所以人数要单独问一次（见 `dzjGradeCollegeCountProvider`），界面也单独画它那一枚胶囊。
  gradeCollege(
    'gradeCollege',
    '同年级同学院',
    DzjPeerSource.relation,
    0,
    filterSql: dzjCollegeFilterSql,
    limit: dzjMaxPeerPageSize,
    gradeScoped: true,
  ),

  relatedDorm('relatedDorm', '同宿舍同学', DzjPeerSource.related, 0),
  relatedCollege('relatedCollege', '同学院同学', DzjPeerSource.related, 1),
  relatedMajor('relatedMajor', '同专业同学', DzjPeerSource.related, 2),
  relatedClass(
    'relatedClass',
    '同班级同学',
    DzjPeerSource.related,
    3,
    gradeScoped: true,
  ),
  enrollDay('enrollDay', '同天入校同学', DzjPeerSource.related, 4),
  birthday('birthday', '同天生日同学', DzjPeerSource.related, 5);

  const DzjPeerDimension(
    this.key,
    this.label,
    this.source,
    this.slot, {
    this.filterSql,
    this.limit = 300,
    this.gradeScoped = false,
  });

  /// 服务端指标位用的键（也是「校内关系」五维人数 map 的键）。
  final String key;

  /// 界面文案。
  final String label;

  /// 名单来自哪个组件。
  final DzjPeerSource source;

  /// 组件内的指标位（`data/get` / `data/search` 的 `index`）。
  final int slot;

  /// 追加在服务端 WHERE 上的过滤谓词（`filterConfig` 的 `filterType:'sql'` 值）；
  /// `null` = 不加过滤（用组件内置 SQL 的原样行集）。
  final String? filterSql;

  /// 取行时的 `pageSize`（服务端上限 [dzjMaxPeerPageSize]）。
  final int limit;

  /// 这一维的行集**逻辑上是「同年级」的子集** → 可以拿「同年级」人数当分母
  /// 画占比条（[dzjPeerGradeRatio]）。
  ///
  /// 只有四维成立：同班同学 / 同年级同专业 / 同年级同学院 / 同班级同学
  /// （同班必然同年级）。舍友、同学院、同专业、同天入校、同天生日都会跨年级
  /// —— 拿同年级当分母会算出 >100% 的假比例，宁可不画。
  ///
  /// ⚠ 配对（一个关系两份口径）**不在这一层**，在 [DzjPeerRelation] ——
  /// 维度是「查哪一路」，关系目才是「界面上的一格」。
  final bool gradeScoped;

  /// 「校内关系」五维（键与那一份人数 map 一一对应）。
  ///
  /// ⚠ 刻意**不含** [gradeCollege]：它是客户端按 [filterSql] 筛出来的一维，
  /// 键不在那份 map 里（人数单独问），与这一组「一格一人数」的口径不同。
  static List<DzjPeerDimension> get relationDims => values
      .where((d) => d.source == DzjPeerSource.relation && d.filterSql == null)
      .toList();

  /// 需要服务端额外过滤的维度（目前只有 [gradeCollege]）。
  static List<DzjPeerDimension> get filteredDims =>
      values.where((d) => d.filterSql != null).toList();

  /// 「相关人员」六维。
  static List<DzjPeerDimension> get relatedDims =>
      values.where((d) => d.source == DzjPeerSource.related).toList();

  static DzjPeerDimension? fromKey(String key) {
    for (final d in values) {
      if (d.key == key) return d;
    }
    return null;
  }
}

/// **融合后的「关系目」**：一个关系在界面上**只出现一次**。
///
/// 用户 2026-10-09 原话：「这两个功能本身就很极高的相似度，那不如直接融合为一个功能。
/// 所有的卡片统一样式，然后重复的卡片不重复显示，可以归并的信息就归并显示」
/// —— 从前「校内关系」五维 + 派生一维与「相关人员」六维各铺一遍。现在按**关系**收敛：
///
/// | 关系目 | 主口径（行里带学号 / 班级 / 年级） | 另一份口径（只有姓名 / 学院） |
/// |---|---|---|
/// | 同班同学 | `class` | `relatedClass` |
/// | 舍友 | `dorm` | `relatedDorm` |
///
/// ⚠ **只有这两对能并**（用户 2026-10-09 当面纠正）：归并的判据是**同义**，
/// 不是"看起来像" ——
/// - ✅ 同班 = 同班级（同一个班必然同一个年级，两套系统只是给的列不同）；
/// - ✅ 舍友 = 同宿舍（同一个宿舍就是同一个宿舍）；
/// - ❌ 「同年级同专业」≠「同专业同学」：前者是**同年级 ∧ 同专业**，后者**不限年级**
///   （是两个行集，人数可以差一个数量级）；
/// - ❌ 「同学院同生日」≠「同学院同学」：前者同样多一个生日约束。
///   后两对**各占一目**（[major] / [relatedMajor]、[college] / [relatedCollege]），
///   并起来就是把口径偷换成另一个数。
///
/// 两份口径是**两个组件、两条写死的 SQL**，即便同义人数也可能不一样 —— 归并的是
/// **入口**（一个关系只点一次），不是数字：方格显示主口径的人数（主口径没取到才回落
/// 另一份），点开弹层可切换看另一份，切换后标题 / 出处 / 人数全按那一份走。
enum DzjPeerRelation {
  grade('grade', '同年级', DzjPeerDimension.grade),
  gradeCollege('gradeCollege', '同年级同学院', DzjPeerDimension.gradeCollege),
  classGroup(
    'class',
    '同班同学',
    DzjPeerDimension.classGroup,
    twin: DzjPeerDimension.relatedClass,
  ),
  major('major', '同年级同专业', DzjPeerDimension.major),
  relatedMajor('relatedMajor', '同专业同学', DzjPeerDimension.relatedMajor),
  dorm(
    'dorm',
    '舍友',
    DzjPeerDimension.dorm,
    twin: DzjPeerDimension.relatedDorm,
  ),
  college('college', '同学院同生日', DzjPeerDimension.college),
  relatedCollege(
    'relatedCollege',
    '同学院同学',
    DzjPeerDimension.relatedCollege,
  ),
  enrollDay('enrollDay', '同天入校同学', DzjPeerDimension.enrollDay),
  birthday('birthday', '同天生日同学', DzjPeerDimension.birthday);

  const DzjPeerRelation(this.key, this.label, this.primary, {this.twin});

  /// 界面 key（与主口径维度的 key 一致 —— `Key('dzjPeer-<key>')` 与守卫都认它）。
  final String key;

  /// 界面文案（取主口径的措辞：它更窄、更准）。
  final String label;

  /// 主口径维度：人数取它，行里带学号 / 班级 / 年级。
  final DzjPeerDimension primary;

  /// 同一关系的另一份口径（没有 → null）。
  final DzjPeerDimension? twin;

  /// 这一目的行集是否不跨年级（决定能不能画占比条，判据在主口径上）。
  bool get gradeScoped => primary.gradeScoped;

  /// 这一目的两份名单要不要**合并**成一份（用户 2026-10-09：「同班和同宿舍，
  /// 你不用做成切换式的，而是做成信息归并式的」）。
  ///
  /// 判据 = 有另一份口径（= 同义的两对）。其余目只有一份名单，谈不上合并。
  bool get merges => twin != null;

  static DzjPeerRelation? fromKey(String key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }

  /// 反查：这个维度（主口径或另一份）属于哪个关系目（名单弹层要用它决定
  /// 「拉一份还是拉两份合并」）。
  static DzjPeerRelation? ofDimension(DzjPeerDimension d) {
    for (final r in values) {
      if (r.primary == d || r.twin == d) return r;
    }
    return null;
  }
}

/// 服务端 `data/search` 的 `pageSize` 上限（实测：再大就回
/// `50000 分数数据量不能大于500`）。
const int dzjMaxPeerPageSize = 500;

/// 「同年级同学院」的过滤谓词（[DzjPeerDimension.filterSql] 用）。
///
/// 抄学校自己那套：谓词里的 `#{U_用户名}` 由**服务端**按当前会话解析成本人，
/// 于是「我的学院」不必在客户端拼名字 —— 这一步是必需的，因为同一所学院在
/// 两套数据里叫法不同：学籍 XML 写「计算机与人工智能学院」，学工系统写「计算机学院」，
/// 拿本地名字去 filter 实测回 **0 人**（`ssdw='计算机学院'` 回 726 人）。
///
/// ⚠ 谓词值必须是**列名 + 比较**的完整 SQL 片段，且只能引用该维行集已暴露的列
/// （`ssdw` 在「同年级」行里就有）。
const String dzjCollegeFilterSql =
    'ssdw=(select ssdw from t_xssj_bzks where userid=#{U_用户名})';

/// 名单里的一个人（服务端 `data/search` 一行）。
///
/// **列名随维度、随组件变**，所以这里只做「能填就填」的稀疏对象，界面按
/// [subtitle] 拼接非空部分；行解析走 [fromRow] 的候选列名表（英文缩写 / 拼音 / 中文）。
class DzjPeer {
  /// 学号 / 校园卡号（`ykth`、`userid`、`kh`）；取不到时为空串。
  final String userId;

  /// 姓名；服务端取不到时**回落成学号**（宁可显示学号，也不要一行空白）。
  ///
  /// ⚠「相关人员」的「同天生日同学」维度姓名是**脱敏**的（`甲**`），照原样显示。
  final String name;

  /// 年级（`sznj`）—— 用户明确要看的「年级」。
  final String grade;

  final String className;
  final String major;
  final String dorm;

  /// 校区（`ssxq`）—— 舍友维度唯一附带的定位信息。
  final String campus;

  /// 学院（`ssdw` / `dept`）。
  final String college;

  final String sex;

  const DzjPeer({
    this.userId = '',
    this.name = '',
    this.grade = '',
    this.className = '',
    this.major = '',
    this.dorm = '',
    this.campus = '',
    this.college = '',
    this.sex = '',
  });

  static const _idKeys = [
    'ykth',
    'userid',
    'user_id',
    'kh',
    'xh',
    'sid',
    'stuno',
    '学号',
  ];
  static const _nameKeys = [
    'username',
    'xm',
    'xingming',
    'cnname',
    'name',
    'realname',
    'stuname',
    '姓名',
  ];
  static const _classKeys = ['ssbj', 'bj', 'classname', 'class_name', '班级'];
  static const _majorKeys = ['sszy', 'zy', 'majorname', 'major', '专业'];
  static const _dormKeys = ['ssdz', 'dz', 'dorm', 'dormitory', '宿舍'];
  static const _campusKeys = ['ssxq', 'xq', 'campus', '校区'];
  static const _collegeKeys = [
    'ssdw',
    'dept',
    'dw',
    'collegename',
    'college',
    '学院',
    'yx',
  ];
  static const _gradeKeys = ['sznj', 'nj', 'grade', '年级'];
  static const _sexKeys = ['sex', 'xb', 'gender', '性别'];

  /// 行 → [DzjPeer]；连姓名与学号都没有 → null（这行没用）。
  static DzjPeer? fromRow(Map<String, dynamic> row) {
    final flat = <String, String>{};
    row.forEach((k, v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      flat[k.toString().toLowerCase()] = s;
    });

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = flat[k];
        if (v != null) return v;
      }
      return '';
    }

    final userId = pick(_idKeys);
    final rawName = pick(_nameKeys);
    final name = rawName.isNotEmpty ? rawName : userId;
    if (name.isEmpty) return null;

    return DzjPeer(
      userId: userId,
      name: name,
      grade: pick(_gradeKeys),
      className: pick(_classKeys),
      major: pick(_majorKeys),
      dorm: pick(_dormKeys),
      campus: pick(_campusKeys),
      college: pick(_collegeKeys),
      sex: pick(_sexKeys),
    );
  }

  /// 副标题：年级 / 班级 / 专业 / 宿舍 / 校区 / 学院 / 性别 里能拿到的部分。
  ///
  /// 顺序按「越能定位到这个人越靠前」排：年级 → 班级 → 专业 → 宿舍 → 校区 → 学院，
  /// 性别垫底（它不是身份而是属性）。「校内关系」维度各给一两列、「相关人员」
  /// 只给学院 + 性别 —— 同一条拼接规则两边都正好读得通。
  String get subtitle => [
    grade,
    className,
    major,
    dorm,
    campus,
    college,
    sex,
  ].where((s) => s.isNotEmpty).join(' · ');

  /// 名单排序：姓名 → 学号兜底（`List.sort` 不稳定，同姓名要有确定顺序）。
  static List<DzjPeer> sorted(Iterable<DzjPeer> peers) {
    final list = [...peers];
    list.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      return a.userId.compareTo(b.userId);
    });
    return list;
  }
}

/// 合并后的一行：人 + 这一行出现在哪几份名单里。
class DzjPeerRow {
  const DzjPeerRow({required this.peer, required this.sources});

  final DzjPeer peer;

  /// 这一行出现在哪几份名单里（两份都有 = 同一个人被两个系统都收录了）。
  final Set<DzjPeerSource> sources;

  /// **只在「相关人员」那一份里**出现 → 行里只有姓名 / 学院（界面据此给个小标）。
  bool get relatedOnly =>
      sources.length == 1 && sources.first == DzjPeerSource.related;
}

/// 两份**同义**名单合并去重后的结果（用户 2026-10-09：「做成信息归并式的」）。
class DzjPeerMerged {
  const DzjPeerMerged({
    required this.rows,
    required this.primaryRows,
    required this.twinRows,
  });

  /// 合并去重、按姓名（学号兜底）排好的行。
  final List<DzjPeerRow> rows;

  /// 主口径那一份取回多少行（弹层副标题要如实写两份各多少行）。
  final int primaryRows;

  /// 另一份取回多少行。
  final int twinRows;

  /// **合并后**的人数（方格上那个数就用它 —— 与点开的名单永远一致）。
  int get count => rows.length;
}

/// 把「校内关系」与「相关人员」两份**同义**名单并成一份。
///
/// 三条口径：
/// - **同一个人的判据 = 学号**；两边都没有学号才回落到姓名（脱敏姓名如 `甲**` 照用）；
/// - **字段取并集**：同一个人两份都有时逐字段取第一个非空值 —— 合并后的行比任何
///   单独一份都全（学号 / 班级 / 年级来自校内关系，学院 / 性别来自相关人员）；
/// - **来源可追溯**：每行记下它出现在哪几份名单里，界面据此给「只在相关人员里」的行
///   加个小标（是信息归并，不是二选一）。
///
/// ⚠ 只对**同义**的两对用（[DzjPeerRelation.merges]）。子集关系（同年级同专业 /
/// 同学院同生日）合并会把两个不同的行集混成一个数，**不许调这个函数**。
DzjPeerMerged dzjPeerMerge({
  required List<DzjPeer> primary,
  required DzjPeerSource primarySource,
  required List<DzjPeer> twin,
  required DzjPeerSource twinSource,
}) {
  final byKey = <String, DzjPeerRow>{};
  void put(DzjPeer p, DzjPeerSource source) {
    final key = p.userId.isNotEmpty ? 'id:${p.userId}' : 'name:${p.name}';
    final old = byKey[key];
    byKey[key] = old == null
        ? DzjPeerRow(peer: p, sources: {source})
        : DzjPeerRow(
            peer: _mergePeers(old.peer, p),
            sources: {...old.sources, source},
          );
  }

  for (final p in primary) {
    put(p, primarySource);
  }
  for (final p in twin) {
    put(p, twinSource);
  }

  final rows = [...byKey.values]
    ..sort((a, b) {
      final byName = a.peer.name.compareTo(b.peer.name);
      if (byName != 0) return byName;
      return a.peer.userId.compareTo(b.peer.userId);
    });
  return DzjPeerMerged(
    rows: rows,
    primaryRows: primary.length,
    twinRows: twin.length,
  );
}

/// 同一个人的两份记录 → 逐字段取非空（信息归并：宁可多留一列，也不要丢）。
DzjPeer _mergePeers(DzjPeer a, DzjPeer b) => DzjPeer(
  userId: a.userId.isNotEmpty ? a.userId : b.userId,
  name: a.name.isNotEmpty ? a.name : b.name,
  grade: a.grade.isNotEmpty ? a.grade : b.grade,
  className: a.className.isNotEmpty ? a.className : b.className,
  major: a.major.isNotEmpty ? a.major : b.major,
  dorm: a.dorm.isNotEmpty ? a.dorm : b.dorm,
  campus: a.campus.isNotEmpty ? a.campus : b.campus,
  college: a.college.isNotEmpty ? a.college : b.college,
  sex: a.sex.isNotEmpty ? a.sex : b.sex,
);

/// 一个关系目在**当前数据**下的实际展示：用哪一份口径、人数多少、另一份多少。
class DzjPeerEntry {
  const DzjPeerEntry({
    required this.relation,
    required this.dimension,
    required this.count,
    this.twinCount,
  });

  final DzjPeerRelation relation;

  /// 实际取数的那一份（弹层**默认就看它** —— 保证「数字来自谁，点开就是谁」）。
  final DzjPeerDimension dimension;

  /// 这一目显示的人数。
  final int count;

  /// 另一份口径的人数（有就画 ⇄ 与「另一份 N 人」）。
  final int? twinCount;

  /// 同一关系的另一份口径维度（没有 → null）。
  DzjPeerDimension? get otherDimension =>
      relation.primary == dimension ? relation.twin : relation.primary;

  static int? _countOf(
    DzjPeerDimension d, {
    required Map<String, int>? relationCounts,
    required Map<String, int>? relatedCounts,
    required int? gradeCollege,
  }) {
    final int? raw;
    if (d == DzjPeerDimension.gradeCollege) {
      // 派生维：人数来自它自己那条过滤查询，不在任何一份 map 里。
      // ⚠ 0 与「没拿到」一样当作没有（口径同 2026-09-20 那轮）：谓词里的学院由服务端
      // 解析，学籍 / 学工两套学院名对不上时会稳定回 0 —— 画一枚「0 人」是误导。
      if (gradeCollege == null || gradeCollege <= 0) return null;
      return gradeCollege;
    } else if (d.source == DzjPeerSource.relation) {
      raw = relationCounts?[d.key];
    } else {
      raw = relatedCounts?[d.key];
    }
    // `-1` = 这一路服务端没给数（见数据源），与「没这个键」一样当作没有；
    // `0` 是**真·0 人**，照铺（灰显）。
    if (raw == null || raw < 0) return null;
    return raw;
  }

  /// 两份人数 map → 要铺的关系目（**按人数降序**，同人数保持目序）。
  ///
  /// 三条口径：
  /// - 两份口径都没拿到人数的目**不铺**（不谎报 0 人）；
  /// - 人数 0 照铺（灰显）——「0 人」本身是信息；
  /// - 主口径优先，缺了才回落另一份（回落时 [dimension] 指向回落的那一份）。
  static List<DzjPeerEntry> build({
    required Map<String, int>? relationCounts,
    required Map<String, int>? relatedCounts,
    int? gradeCollege,
  }) {
    int? countOf(DzjPeerDimension d) => _countOf(
      d,
      relationCounts: relationCounts,
      relatedCounts: relatedCounts,
      gradeCollege: gradeCollege,
    );

    final entries = <DzjPeerEntry>[];
    final order = <String, int>{};
    for (final r in DzjPeerRelation.values) {
      order[r.key] = order.length;
      final primary = countOf(r.primary);
      final twin = r.twin == null ? null : countOf(r.twin!);
      if (primary != null) {
        entries.add(
          DzjPeerEntry(
            relation: r,
            dimension: r.primary,
            count: primary,
            twinCount: twin,
          ),
        );
      } else if (twin != null) {
        entries.add(
          DzjPeerEntry(relation: r, dimension: r.twin!, count: twin),
        );
      }
    }
    // 同人数保持目序：`List.sort` 不稳定，不兜底的话方格每次重建都可能换位置。
    entries.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return order[a.relation.key]!.compareTo(order[b.relation.key]!);
    });
    return entries;
  }
}

/// 这一维的人数占「同年级」人数的比例（0..1），用于卡片上的占比条。
///
/// 回 `null` = **不画条**，四种情形：这一维不在 [DzjPeerDimension.gradeScoped]
/// 里（行集会跨年级）；人数 ≤ 0；「同年级」人数没拿到或为 0；算出来 > 1
/// （口径异常 —— 行集不该比同年级还大，宁可没有条也不要一条满格的假条）。
///
/// ⚠ 分母用的是**「校内关系」那份同年级人数**；「相关人员」的 [DzjPeerDimension.relatedClass]
/// 虽然不是同一组件，但「同班必然同年级」成立，故共用这一个分母（界面文案里
/// 写明「占同年级」而不写百分比来源组件）。
double? dzjPeerGradeRatio(
  DzjPeerDimension dimension, {
  required int count,
  required int? gradeCount,
}) {
  if (!dimension.gradeScoped) return null;
  if (count <= 0) return null;
  final total = gradeCount ?? 0;
  if (total <= 0) return null;
  final ratio = count / total;
  if (ratio > 1) return null;
  return ratio;
}
