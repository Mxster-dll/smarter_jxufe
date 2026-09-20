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
/// 前五个维度与 [DataCenterOverview.peerCounts]（`lib/features/data_center/data/models/data_center_models.dart`）
/// 的键**一一对应**；后六个来自「相关人员」页，键自带 `related` 前缀以免撞车。
enum DzjPeerDimension {
  grade('grade', '同年级', DzjPeerSource.relation, 0),
  classGroup('class', '同班同学', DzjPeerSource.relation, 1),
  major('major', '同年级同专业', DzjPeerSource.relation, 2),
  dorm('dorm', '舍友', DzjPeerSource.relation, 3),
  college('college', '同学院同生日', DzjPeerSource.relation, 4),

  /// 同年级 **+ 本人学院**（用户 2026-09-20 立项）：「同年级」行集再按 `ssdw` 过滤。
  ///
  /// 服务端组件没有这一维（内置 SQL 只有五路），但 `filterConfig` 认 SQL 谓词
  /// （[filterSql]）→ 仍然是**一次请求**，`total` 就是人数（实测 726）。
  /// 它的键**不在** `DataCenterOverview.peerCounts` 里（那个 map 来自服务端五路聚合），
  /// 所以人数要单独问一次（见 `dzjGradeCollegeCountProvider`），界面也单独画它那一枚胶囊。
  gradeCollege(
    'gradeCollege',
    '同年级同学院',
    DzjPeerSource.relation,
    0,
    filterSql: dzjCollegeFilterSql,
    limit: dzjMaxPeerPageSize,
  ),

  relatedDorm('relatedDorm', '同宿舍同学', DzjPeerSource.related, 0),
  relatedCollege('relatedCollege', '同学院同学', DzjPeerSource.related, 1),
  relatedMajor('relatedMajor', '同专业同学', DzjPeerSource.related, 2),
  relatedClass('relatedClass', '同班级同学', DzjPeerSource.related, 3),
  enrollDay('enrollDay', '同天入校同学', DzjPeerSource.related, 4),
  birthday('birthday', '同天生日同学', DzjPeerSource.related, 5);

  const DzjPeerDimension(
    this.key,
    this.label,
    this.source,
    this.slot, {
    this.filterSql,
    this.limit = 300,
  });

  /// `peerCounts` / 服务端指标位用的键。
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

  /// 「校内关系」五维（键与 `peerCounts` 一一对应）。
  ///
  /// ⚠ 刻意**不含** [gradeCollege]：它是客户端按 [filterSql] 筛出来的一维，
  /// 键不在 `peerCounts` 里（人数单独问），与这一组「一格一人数」的口径不同。
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
