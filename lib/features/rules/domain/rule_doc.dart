/// 规章制度模块 —— 文档目录模型。
///
/// [RuleDoc] 对应一份规则文件（md 文本资产 + 可选 pdf 原件资产），
/// [RulesCatalog] 是 assets/rules/meta/rules_catalog.json 的运行时形态。
library;

enum RuleTemplate {
  /// 红头通知 + 办法/细则条文（章、条、正文、表格）。
  regulation,

  /// 分类目录大表（如学科竞赛目录：一、二、三、四类）。
  catalog,
}

class RuleDoc {
  final String id;
  final String file; // md 文件名（= PDF stem + .md）
  final String pdf; // pdf 文件名（= PDF stem + .pdf）
  final String title; // 列表/标题用短名
  final String group; // 分类名（学籍成绩 / 学科竞赛 / …）
  final RuleTemplate template;
  final String? wenhao; // 文号，如 江财字〔2024〕4号
  final String? date; // 印发日期 yyyy-MM-dd（curated 时才有）
  final String year; // 文件名中的年份（展示徽标用）

  /// 文档形态：notice=印发通知正文；attachment=从印发文件中拆出的附件；
  /// 未拆分文档（目录/纯通知）为 null。
  final RuleDocKind? kind;

  /// 附件所属的通知文档 id（kind==attachment 时非空）。
  final String? parentId;

  const RuleDoc({
    required this.id,
    required this.file,
    required this.pdf,
    required this.title,
    required this.group,
    required this.template,
    this.wenhao,
    this.date,
    this.year = '',
    this.kind,
    this.parentId,
  });

  String get mdAsset => 'assets/rules/text/$file';
  String get pdfAsset => 'assets/rules/pdf/$pdf';

  factory RuleDoc.fromJson(Map<String, dynamic> j) => RuleDoc(
        id: j['id'] as String,
        file: j['file'] as String,
        pdf: j['pdf'] as String,
        title: j['title'] as String,
        group: j['group'] as String,
        template: j['template'] == 'catalog'
            ? RuleTemplate.catalog
            : RuleTemplate.regulation,
        wenhao: j['wenhao'] as String?,
        date: j['date'] as String?,
        year: (j['year'] as String?) ?? '',
        kind: switch (j['kind'] as String?) {
          'notice' => RuleDocKind.notice,
          'attachment' => RuleDocKind.attachment,
          _ => null,
        },
        parentId: j['parent'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'file': file,
        'pdf': pdf,
        'title': title,
        'group': group,
        'template': template.name,
        if (wenhao != null) 'wenhao': wenhao,
        if (date != null) 'date': date,
        'year': year,
        if (kind != null) 'kind': kind!.name,
        if (parentId != null) 'parent': parentId,
      };
}

/// 文档拆分形态（拆分前无此概念，整份文档二者皆 null）。
enum RuleDocKind {
  /// “关于印发《xxx》的通知”拆出的正文（文号/主送/印发语/落款/版记）。
  notice,

  /// 从印发文件拆出的《xxx》正文（主附件或次附件），[RuleDoc.parentId] 指回通知。
  attachment,
}

/// 家族成员 = 一份具体文档 + 展示标签（如「2025年修订」「印发通知」）。
class FamilyMember {
  final RuleDoc doc;
  final String label;

  const FamilyMember({required this.doc, required this.label});
}

/// 同名家族：同一《规则核心名》下的全部文档（拆分件 + 跨年份版本），
/// 列表只显示一个入口；[defaultId] 为点击入口默认打开的成员（最新版正文）。
class RuleFamily {
  final String name; // 核心名（列表瓦片标题）
  final String group; // 分类名
  final String defaultId;
  final List<FamilyMember> members; // 版本条展示顺序（最新在前）

  const RuleFamily({
    required this.name,
    required this.group,
    required this.defaultId,
    required this.members,
  });

  RuleDoc get defaultDoc {
    for (final m in members) {
      if (m.doc.id == defaultId) return m.doc;
    }
    return members.first.doc;
  }

  RuleDoc? docById(String id) {
    for (final m in members) {
      if (m.doc.id == id) return m.doc;
    }
    return null;
  }

  String? labelOf(String docId) {
    for (final m in members) {
      if (m.doc.id == docId) return m.label;
    }
    return null;
  }

  /// 通知 → 其拆分出的附件成员（kind==attachment）。
  List<FamilyMember> attachmentsOf(String noticeId) => [
        for (final m in members)
          if (m.doc.kind == RuleDocKind.attachment &&
              m.doc.parentId == noticeId)
            m,
      ];
}

class RulesCatalog {
  final List<String> groups; // 分类展示顺序
  final List<RuleDoc> docs;
  final List<RuleFamily> families;

  const RulesCatalog({
    required this.groups,
    required this.docs,
    this.families = const [],
  });

  factory RulesCatalog.fromJson(Map<String, dynamic> j) {
    final docs = (j['docs'] as List<dynamic>)
        .map((e) => RuleDoc.fromJson(e as Map<String, dynamic>))
        .toList();
    RuleDoc? byId(String id) {
      for (final d in docs) {
        if (d.id == id) return d;
      }
      return null;
    }

    final rawFamilies = j['families'] as List<dynamic>? ?? const [];
    final families = <RuleFamily>[
      for (final raw in rawFamilies.cast<Map<String, dynamic>>())
        RuleFamily(
          name: raw['name'] as String,
          group: (raw['group'] as String?) ?? '',
          defaultId: raw['default'] as String,
          members: [
            for (final m in (raw['members'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
              FamilyMember(
                doc: byId(m['id'] as String)!,
                label: (m['label'] as String?) ?? '',
              ),
          ],
        ),
    ];
    return RulesCatalog(
      groups: (j['groups'] as List<dynamic>).cast<String>(),
      docs: docs,
      families: families,
    );
  }

  /// 按 [groups] 顺序分组的文档；未收录分类名追加到末尾。
  Map<String, List<RuleDoc>> groupDocs() {
    final map = <String, List<RuleDoc>>{};
    for (final d in docs) {
      map.putIfAbsent(d.group, () => []).add(d);
    }
    final out = <String, List<RuleDoc>>{};
    for (final g in groups) {
      if (map.containsKey(g)) out[g] = map.remove(g)!;
    }
    out.addAll(map);
    return out;
  }

  /// 同名家族按分类分组（分组键取家族 group 字段）。
  Map<String, List<RuleFamily>> groupFamilies() {
    final map = <String, List<RuleFamily>>{};
    for (final f in families) {
      map.putIfAbsent(f.group, () => []).add(f);
    }
    final out = <String, List<RuleFamily>>{};
    for (final g in groups) {
      if (map.containsKey(g)) out[g] = map.remove(g)!;
    }
    out.addAll(map);
    return out;
  }

  RuleDoc? byId(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// 某文档所属的同名家族（无 family 元数据时为 null）。
  RuleFamily? familyOf(String id) {
    for (final f in families) {
      for (final m in f.members) {
        if (m.doc.id == id) return f;
      }
    }
    return null;
  }

  /// 某文档的直接附件（kind==attachment 且 parentId==id，保持 catalog 顺序）。
  List<RuleDoc> childrenOf(String id) =>
      [for (final d in docs) if (d.parentId == id) d];
}
