/// 学生个人数据中心 —— **子页面清单**（动态发现，不在 App 里写死 pageKey）。
///
/// 学校那套「竹简」中台的页面树由服务端下发：
///
/// ```
/// POST /api/page/manageTreeByVersion
/// body = {"url": "<应用地址 66eef481a9a3>", "accessFlag": 1, "type": "web"}
/// → {"tree": [
///      {"menuName": "个人首页", "pageKey": "82e98baafb40", "menuType": "C"},
///      {"menuName": "个人数据", "pageKey": "c62ddfc1d7b4", "menuType": "M",
///       "children": [
///          {"menuName": "基本信息",  "pageKey": "13ba9ece95a8", "menuType": "C"},
///          {"menuName": "关联同学",  "pageKey": "228583a5077f", "menuType": "C"},
///          … 共十个 …]}]}
/// ```
///
/// **入参抄自学校前端调用点**（`js_umi.c9aa3507.js` 的 `o6` →
/// `/api/page/manageTreeByVersion`：`R.o6({url, accessFlag: 1, type: 'web'})`
/// `→ res.data.tree`）——注意「应用唯一标识」这个字段名是 **`url`**：
/// `appId` / `appUrl` / `appUniqueId` / `appCode` 一律被服务端判「应用唯一标识不能为空」。
/// `accessFlag` 传数字 `1`、字符串 `"1"` 都行；`type` 传 `web` / `mobile` 回包一致。
///
/// 之所以动态拉：学校往「个人数据」里再加一个子页面时，App 不必改代码就会出现
/// （`manageTree` 里还有「个人首页（研）/ 基本信息（研）/ 指导教师2（研）…」等
/// 未发布页，**只有 `manageTreeByVersion` 回的是当前发布版**，故必须用它）。
library;

/// 个人数据中心的**首页** pageKey（`82e98baafb40`）——不是子页面。
const String dzjHomePageKey = '82e98baafb40';

/// 「基本信息」子页面 pageKey（`13ba9ece95a8`）。
///
/// 用户 2026-09-19 五轮裁定：**该页不单独做 App 子页面**，而是把它的字段
/// （一卡通号 / 学号 / 姓名 / 性别 / 出生日期 / 民族 / 政治面貌 / 籍贯 / 证件 /
/// 所属单位-专业-班级 / 所在年级 / 学制 / 培养层次 / 考生类别 / 录取专业 /
/// 手机号码 / 电子邮箱 / 考生号 / 宿舍地址）并进「我的」页的既有卡片
/// （`student_info_screen.dart`）——「除非必要，不然不开新卡片」。
///
/// 顺带记录：该页唯一组件 `u:73ab7f26af38`（`form-assembly-renderer`「基本信息」）
/// 的 `selectArea` 是占位符 `select * from t_sys_user`，`data/search` 恒回
/// `total = 0` —— **服务端根本没给数据**，所以 App 侧取「我的」的学籍缓存。
const String dzjBasicInfoPageKey = '13ba9ece95a8';

/// 「基本信息」的标题（用于从子页面列表里剔除时对名）。
const String dzjBasicInfoTitle = '基本信息';

/// 页面树上的一个节点（菜单容器 `menuType == 'M'` 或内容页 `menuType == 'C'`）。
class DzjPageNode {
  const DzjPageNode({
    required this.pageKey,
    required this.title,
    this.menuType = '',
    this.children = const <DzjPageNode>[],
  });

  final String pageKey;
  final String title;
  final String menuType;
  final List<DzjPageNode> children;

  /// 菜单容器（「个人数据」那一层）：不指向具体页面。
  bool get isContainer => menuType == 'M' || pageKey.isEmpty;

  /// 深度优先展开（自己 + 全部后代）。
  List<DzjPageNode> get flat {
    final out = <DzjPageNode>[this];
    for (final c in children) {
      out.addAll(c.flat);
    }
    return out;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pageKey': pageKey,
    'title': title,
    'menuType': menuType,
    'children': children.map((c) => c.toJson()).toList(),
  };

  /// 容错解析：非 Map / 无 pageKey 的节点直接丢弃（脏数据不让界面崩）。
  static DzjPageNode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['pageKey']?.toString().trim() ?? '';
    final title = (raw['menuName'] ?? raw['title'] ?? raw['name'] ?? '')
        .toString()
        .trim();
    final type = raw['menuType']?.toString().trim() ?? '';
    final kids = <DzjPageNode>[];
    final rawKids = raw['children'];
    if (rawKids is List) {
      for (final k in rawKids) {
        final node = DzjPageNode.fromJson(k);
        if (node != null) kids.add(node);
      }
    }
    if (key.isEmpty && kids.isEmpty) return null;
    return DzjPageNode(
      pageKey: key,
      title: title.isEmpty ? key : title,
      menuType: type,
      children: kids,
    );
  }
}

/// 整棵页面树 + 过滤好的**子页面清单**。
class DzjPageTree {
  const DzjPageTree({required this.roots, required this.subPages});

  final List<DzjPageNode> roots;

  /// 数据中台里要做的子页面（**已剔除首页与「基本信息」**，顺序 = 服务端顺序）。
  final List<DzjPageNode> subPages;

  bool get isEmpty => subPages.isEmpty;

  int get totalPages =>
      roots.expand((r) => r.flat).where((n) => !n.isContainer).length;

  /// 解析 `{tree: [...]}` / 裸数组 / 单节点；认不出就是空树（界面给空态）。
  static DzjPageTree parse(Object? data) {
    final rawList = switch (data) {
      List() => data,
      Map() => switch (data['tree'] ?? data['list'] ?? data['data']) {
        List() => (data['tree'] ?? data['list'] ?? data['data']) as List,
        final Object? single => <Object?>[single],
      },
      _ => const <Object?>[],
    };
    final roots = <DzjPageNode>[];
    for (final raw in rawList) {
      final node = DzjPageNode.fromJson(raw);
      if (node != null) roots.add(node);
    }
    return DzjPageTree(roots: roots, subPages: dzjSubPagesOf(roots));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roots': roots.map((r) => r.toJson()).toList(),
    'subPages': subPages.map((n) => n.toJson()).toList(),
  };
}

/// 从（可能嵌套的）页面树里挑出**要做成 App 子页面**的那些内容页。
///
/// 规则（顺序即服务端顺序，界面按此铺排）：
/// 1. 只取内容页（`menuType != 'M'` 且 pageKey 非空）；
/// 2. 剔除首页 [dzjHomePageKey]（它就是「数据一览」本身）；
/// 3. 剔除「基本信息」[dzjBasicInfoPageKey]（已并入「我的」页，见其文档注释）；
/// 4. 同名/同 key 只保留第一次出现。
List<DzjPageNode> dzjSubPagesOf(List<DzjPageNode> roots) {
  final seen = <String>{};
  final out = <DzjPageNode>[];
  for (final node in roots.expand((r) => r.flat)) {
    if (node.isContainer) continue;
    if (node.pageKey == dzjHomePageKey) continue;
    if (node.pageKey == dzjBasicInfoPageKey) continue;
    if (node.title.trim() == dzjBasicInfoTitle) continue;
    if (!seen.add(node.pageKey)) continue;
    out.add(node);
  }
  return out;
}
