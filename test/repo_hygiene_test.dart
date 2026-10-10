/// 仓库卫生守卫（2026-09-20 立 · 架构审查 ① 工程卫生）。
///
/// 守的是**只有本地才看得见、编译器管不到**的那一类问题：
///
/// - `*.g.dart` / `*.freezed.dart` 曾是 `.gitignore` 的常客（Flutter 模板默认写法），
///   而本仓**没有 CI**、也没有「克隆后先跑 build_runner」的强制步骤 →
///   一旦被忽略，全新克隆会因为 `part '…'` 找不到目标而**连编译都过不去**。
///   编译器只能守住「本地文件在不在」，守不住「它有没有进 git」→ 故有此测。
/// - 生成物**孤儿**（源文件已删、`.g.dart` 还留在磁盘上）编译器也不管，
///   它会被一次次提交进仓库。这里用「part 指令 ↔ 生成物」双向集合相等来兜。
/// - **未用依赖**：`pubspec.yaml` 里多一个包，`pub get` 就会多拉一整棵依赖树
///   （2026-09-20 清理时实测：删 20 个直接依赖 → lock 从 **215 掉到 158**），
///   而**编译器完全不会抱怨**一个没人 import 的包。故用「每个运行期依赖都要
///   在源码里真的出现 `package:<名字>/`」来守（白名单 = 有理由的例外）。
///
/// ⚠ 本测试**只读文本、不跑 git**（源码包 `git archive` 里没有 `.git`，跑 git 会误红）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 运行期依赖白名单 =「没有源码 import、但确实必须在 pubspec 里」的包。
///
/// 新增一条必须写明**为什么**；白名单本身也有守卫（见下方「白名单不许陈旧」）。
const Map<String, String> _dependencyAllowList = <String, String>{
  'json_annotation':
      'freezed 注解层：生成的 `*.freezed.dart` 里写着 `@JsonSerializable()`，而注解由 '
          '`freezed_annotation.dart` 以 `export` 转发出来；用 `part of` 的 `.g.dart` '
          '不算 import，纯 import 统计必然漏判，故它没有任何源码 import 也必须留着。',
};

/// `pubspec.yaml` 的运行期依赖名（`dependencies:` 块，跳过 `flutter: sdk: flutter`）。
///
/// 只取**恰好两空格缩进**的 `名字: 约束` 行 —— 注释行（`  # …`）与块内更深的
/// 缩进天然不匹配；块在遇到第一个顶格行时结束。
/// ⚠ **必须先归一化行尾**：本仓 `pubspec.yaml` 是 **CRLF**，若按 `split('\n')`
/// 切分，空行会剩成 `'\r'` → 「非空且不以空格开头」成立 → 解析在第一个空行处
/// 就 break（实测只认出 `flutter` 一个）。用 `RegExp(r'\r?\n')` 一次切干净。
/// `dev_dependencies:` **刻意不管**：那里全是 CLI 调用的 codegen 工具
/// （build_runner / freezed / hive_generator / riverpod_generator / flutter_lints…），
/// 按设计就没有任何源码 import，扫了只会得到一份全量白名单、等于没守。
List<String> _runtimeDependencies() {
  final out = <String>[];
  var inDeps = false;
  for (final line in File('pubspec.yaml').readAsStringSync().split(RegExp(r'\r?\n'))) {
    if (line.startsWith('dependencies:')) {
      inDeps = true;
      continue;
    }
    if (!inDeps) continue;
    if (line.isNotEmpty && !line.startsWith(' ')) break; // 离开该块
    final m = RegExp(r'^  ([a-z0-9_]+):\s*(\S.*)?$').firstMatch(line);
    if (m == null) continue;
    if ((m.group(2) ?? '').startsWith('sdk:')) continue;
    out.add(m.group(1)!);
  }
  return out;
}

/// 一个包被 `lib/` `test/` `tool/` 的 `.dart` 源码 **import/export** 到的文件
/// （含生成物；`lib/old/` 是 gitignore 的历史存档，跳过）。
///
/// ⚠ 必须匹配**指令**而不是裸子串：`contains('package:http/')` 会被
/// `package:http_parser/…` 命中（审计时真的误判过一次），也会被
/// 注释/文档/本文件的白名单理由串命中（实测把 `json_annotation` 误判成
/// 「已被 import」）。只认行首的 `import` / `export` 就都没有这些问题。
Set<String> _importsOf(String package) {
  final pattern = RegExp(
    "^\\s*(?:import|export)\\s+'package:${RegExp.escape(package)}/",
    multiLine: true,
  );
  final hits = <String>{};
  for (final dir in const ['lib', 'test', 'tool']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.contains('/old/')) continue;
      if (pattern.hasMatch(f.readAsStringSync())) hits.add(path);
    }
  }
  return hits;
}

/// 仓库根下的 `lib/`（`flutter test` 的工作目录就是包根）。
Directory get _libDir => Directory('lib');

/// 判断一个文件名是不是代码生成产物。
bool _isGenerated(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

/// `lib/` 下全部 `.dart`（跳过 `lib/old/`：那是 gitignore 掉的历史存档）。
List<File> _dartFiles() => _libDir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.replaceAll(r'\', '/').contains('/old/'))
    .toList();

/// 一个文件里声明的 `part '…'` 目标（相对路径，已解析成归一化形式）。
///
/// 只认 `^part '…';` —— `part of '…';` 不会被这条正则命中（`of` 挡在引号前）。
List<String> _partTargets(File file) {
  final source = file.readAsStringSync();
  final base = file.parent.path.replaceAll(r'\', '/');
  return [
    for (final m in RegExp(
      "^part\\s+'([^']+)';",
      multiLine: true,
    ).allMatches(source))
      '$base/${m.group(1)!}'.replaceAll('//', '/'),
  ];
}

/// `.gitignore` 里**真的会命中文件**的规则（跳过注释与空行）。
///
/// 只实现本仓用到的那些形态：`/锚定`、`目录/`（任意深度）、`*.后缀`、`名字`、
/// `**/x/y`、`a*b` 通配。够用即可 —— 它的用途是「别把源码吞掉」这条断言，
/// 不是重写 git。
List<String> _ignoreRules() => [
  for (final raw in File('.gitignore').readAsStringSync().split(RegExp(r'\r?\n')))
    if (raw.trim().isNotEmpty && !raw.trimLeft().startsWith('#')) raw.trim(),
];

/// 单条 gitignore 规则是否命中某个**已归一化**的相对路径（`a/b/c.dart`）。
///
/// ⚠ 关键语义（就是 2026-09-27 踩的那个坑）：**不带前导斜杠的规则在任意深度生效**
/// —— `tools/` 会命中 `lib/features/ai/tools/`，必须写成 `/tools/` 才只指仓库根。
bool _ruleMatches(String rule, String path) {
  final anchored = rule.startsWith('/');
  final body = anchored ? rule.substring(1) : rule;
  final dirOnly = body.endsWith('/');
  final pattern = dirOnly ? body.substring(0, body.length - 1) : body;
  if (pattern.isEmpty) return false;

  final regex = RegExp(
    '^${RegExp.escape(pattern).replaceAll(r'\*\*', '§').replaceAll(r'\*', '[^/]*').replaceAll('§', '.*')}'
        r'(/|$)',
  );
  if (anchored) return regex.hasMatch(path);
  // 未锚定：逐段起头都算（`a/b/c` 上试 `a/b/c`、`b/c`、`c`）
  final parts = path.split('/');
  for (var i = 0; i < parts.length; i++) {
    if (regex.hasMatch(parts.sublist(i).join('/'))) return true;
  }
  return false;
}

/// `lib/` 下被 `.gitignore` 命中的源码文件（正常应当是空的）。
List<String> _ignoredSources() {
  final rules = _ignoreRules();
  return [
    for (final f in _dartFiles())
      if (rules.any((r) => _ruleMatches(r,
          f.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^\./'), ''))))
        f.path.replaceAll(r'\', '/'),
  ];
}

void main() {
  final allDart = _dartFiles();
  final generated = [
    for (final f in allDart)
      if (_isGenerated(f.path.replaceAll(r'\', '/'))) f.path.replaceAll(r'\', '/'),
  ];
  final declared = <String>[
    // 生成物自己只写 `part of`，扫它们没有意义（也没有 `part` 指令）。
    for (final f in allDart)
      if (!_isGenerated(f.path.replaceAll(r'\', '/'))) ..._partTargets(f),
  ];

  test('.gitignore 不得忽略代码生成产物（本仓无 CI，缺了全新克隆编译不过）', () {
    final lines = File('.gitignore')
        .readAsStringSync()
        .split('\n')
        .map((l) => l.trim())
        .toList();
    expect(
      lines.contains('*.g.dart'),
      isFalse,
      reason: '`.gitignore` 又忽略了 `*.g.dart` —— 生成物不入库，全新克隆会编译失败。'
          '本仓无 CI，产物必须与源码一起提交（见 README「注意事项」）。',
    );
    expect(
      lines.contains('*.freezed.dart'),
      isFalse,
      reason: '`.gitignore` 又忽略了 `*.freezed.dart` —— 同上，产物必须入库。',
    );
  });

  test('生成物齐备：每个 part 指令都有对应文件', () {
    expect(
      declared,
      isNotEmpty,
      reason: '一个 part 指令都没扫到 —— 正则或目录口径失效了，别让守卫静默空转。',
    );
    final missing = [
      for (final p in declared)
        if (!File(p).existsSync()) p,
    ];
    expect(missing, isEmpty, reason: '缺失的生成物（跑 `dart run build_runner build '
        '--delete-conflicting-outputs` 重新生成）：\n${missing.join('\n')}');
  });

  test('无孤儿生成物：磁盘上每个生成物都被某个 part 指令引用', () {
    final declaredSet = declared.toSet();
    final orphans = [
      for (final g in generated)
        if (!declaredSet.contains(g)) g,
    ];
    expect(orphans, isEmpty, reason: '这些生成物没有任何源文件 `part` 它们'
        '（源文件已删/改名？）：\n${orphans.join('\n')}');
  });

  test('生成物数量与 part 指令数量一致（1:1，无重复引用）', () {
    expect(declared.length, declared.toSet().length,
        reason: '有 part 指令被重复声明（同一生成物被两个源文件 part）。');
    expect(generated.length, declared.length,
        reason: '生成物 ${generated.length} 个 vs part 指令 ${declared.length} 条 —— '
            '两者必须 1:1（多 = 孤儿，少 = 缺失）。');
  });

  test('★ 源码不被 .gitignore 吞掉（2026-09-27 · 实测踩过）', () {
    // 实测事故：`.gitignore` 写的是 `tools/`（**不带前导斜杠 = 任意深度生效**）→
    // `lib/features/ai/tools/`（整个 AI 工具层，10 个 .dart / ~109 KB）被静默忽略，
    // `git ls-files lib/features/ai/tools/` = 空：本地编译测试全绿，**全新克隆却缺一整层源码**。
    // 编译器管不到「文件在不在 git 里」，所以只能在这里守。
    final ignored = _ignoredSources();
    expect(
      ignored,
      isEmpty,
      reason: '这些 `lib/` 下的源码被 `.gitignore` 命中了（`git check-ignore -v <路径>` '
          '可看是哪条规则）：\n  ${ignored.join('\n  ')}\n'
          '多半是某条**没锚定**的目录规则（如 `tools/` 会命中任意深度的 `tools/`）—— '
          '改成 `/tools/` 这种仓库根写法。',
    );
    // 反向自检：匹配器本身不许静默失效（拿真出过事的那条规则验一次）。
    expect(
      _ruleMatches('tools/', 'lib/features/ai/tools/life_tools.dart'),
      isTrue,
      reason: '匹配器没认出「未锚定的 `tools/` 会命中任意深度」—— 这条守卫就成了空转。',
    );
    expect(
      _ruleMatches('/tools/', 'lib/features/ai/tools/life_tools.dart'),
      isFalse,
      reason: '`/tools/` 是仓库根锚定，不该命中 `lib/feature/ai/tools/`。',
    );
    expect(_ruleMatches('/tools/', 'tools/smoke.dart'), isTrue);
    expect(_ruleMatches('*.log', 'lib/a.log'), isTrue);
    expect(_ruleMatches('*.log', 'lib/a.dart'), isFalse);
  });

  test('★ 敏感资产不得用目录通配声明（2026-10-10 · 实测踩过）', () {
    // 实测事故：`pubspec.yaml` 写的是 `- assets/capture_certs/`（整个目录）。
    // `.gitignore` 只挡得住「**入库**」（`assets/capture_certs/*.key`，git 侧确实干净），
    // 却挡不住「**打包**」—— Flutter 会把该目录下所有文件塞进 asset bundle，
    // 于是两个正式 APK 里都躺着 `assets/flutter_assets/assets/capture_certs/ca.key`
    // 与 `leaf.key`（sha256 与本地私钥逐字节相同，已实证）。
    // 同剂量的坑还害过源码：`.gitignore` 的裸 `tools/` 吞掉整个 AI 工具层（见上一例）。
    // 故：凡是「目录里混着不该分发的东西」的资产，一律**逐个列文件**。
    //
    // ⚠ 口径：`leaf.key` 目前**仍必须随包分发**（`guid_capture_session.dart` 的
    // `_buildServerContext()` 要 `ctx.usePrivateKeyBytes(...)`，去掉它「平台标识」抓包
    // 直接不可用）—— 这个测试不假装包里没有私钥，只防止「无意中多带一个 `ca.key`」
    // 与「用目录写法把新加的文件悄悄带进去」这两类**回归**。
    final lines = File('pubspec.yaml').readAsStringSync().split(RegExp(r'\r?\n'));
    var inAssets = false;
    final dirEntries = <String>[];
    final certEntries = <String>[];
    for (final line in lines) {
      // 顶层 `assets:`（两个空格缩进）开块；遇到下一个顶层键即离开该块。
      if (RegExp(r'^  assets:\s*$').hasMatch(line)) {
        inAssets = true;
        continue;
      }
      if (!inAssets) continue;
      if (line.isNotEmpty && !line.startsWith('    ')) break;
      final m = RegExp(r'^    - (\S+)\s*$').firstMatch(line);
      if (m == null) continue; // 注释与更深缩进天然不匹配
      final entry = m.group(1)!;
      if (entry.startsWith('assets/capture_certs/')) certEntries.add(entry);
      if (entry.endsWith('/')) dirEntries.add(entry);
    }
    // ① capture_certs 必须逐个列文件。
    expect(
      certEntries,
      isNotEmpty,
      reason: '`pubspec.yaml` 的 assets 里找不到任何 `assets/capture_certs/<文件>` 条目 —— '
          '要么整段被删（「平台标识」抓包会挂），要么又被写回目录形式。',
    );
    expect(
      certEntries.every((e) => !e.endsWith('/')),
      isTrue,
      reason: 'capture_certs 又用目录通配了：${certEntries.where((e) => e.endsWith('/')).toList()}\n'
          '目录写法会把同目录的 `*.key` 一起打进 APK / Windows 安装包。',
    );
    // ② 任何 assets 目录条目都不得回溯命中 `*.key`（当前只有 capture_certs 有这风险）。
    final offenders = <String>[];
    for (final entry in dirEntries) {
      if (!entry.startsWith('assets/')) continue;
      final dir = Directory(entry.substring(0, entry.length - 1));
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File && e.path.replaceAll('\\', '/').endsWith('.key')) {
          offenders.add('$entry → ${e.path}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些 assets 目录条目会连带把 `.key` 打进安装包（实测两个 APK 都中过）：\n'
          '  ${offenders.join('\n  ')}\n'
          '改成逐个列公开证书文件（见 `pubspec.yaml` 该段的注释）。',
    );
    // ③ 反向自检：解析器本身不许空转 —— 目录写法必须被判成「以 / 结尾」。
    final probe = RegExp(r'^    - (\S+)\s*$').firstMatch('    - assets/capture_certs/');
    expect(probe?.group(1), 'assets/capture_certs/');
    expect(probe!.group(1)!.endsWith('/'), isTrue);
  });

  group('依赖都被真的 import（2026-09-20 · 架构审查 ①）', () {
    final deps = _runtimeDependencies();
    final hits = {for (final d in deps) d: _importsOf(d)};

    test('pubspec 的每个运行期依赖都在源码里被 import（白名单除外）', () {
      expect(deps, isNotEmpty,
          reason: '一个运行期依赖都没解析出来 —— 解析口径失效了，别让守卫静默空转。');
      final unused = [
        for (final d in deps)
          if ((hits[d] ?? const <String>{}).isEmpty &&
              !_dependencyAllowList.containsKey(d))
            d,
      ];
      expect(
        unused,
        isEmpty,
        reason: '这些包在 lib/test/tool 里一次都没被 import（`import/export '
            '\'package:<名字>/…\'` 零命中）：\n'
            '  ${unused.join('\n  ')}\n'
            '要么删掉（`flutter pub get` 后 lock 会跟着瘦），要么加进 '
            '`_dependencyAllowList` **并写明理由**。\n'
            '⚠ 判据是 import 指令、不是子串，所以 `http_parser` 不会把 `http` 带进来；'
            '反过来说，本文件的白名单理由里随便写包名也不会自证自话。',
      );
    });

    test('白名单不许陈旧：允许的包必须真在 pubspec 里、且真没被 import', () {
      for (final entry in _dependencyAllowList.entries) {
        expect(deps, contains(entry.key),
            reason: '${entry.key} 在允许清单里，却不是运行期依赖了 —— 把它从 '
                '`_dependencyAllowList` 删掉。');
        expect(hits[entry.key], isEmpty,
            reason: '${entry.key} 已经被源码 import 了 —— 不再是「白名单例外」，'
                '把它从 `_dependencyAllowList` 删掉（理由也要删）。');
      }
    });

    test('白名单每一条都写了理由（不是空壳）', () {
      for (final entry in _dependencyAllowList.entries) {
        expect(entry.value.trim().length, greaterThan(20),
            reason: '${entry.key} 的理由太短/为空 —— 白名单是「有理由的例外」，'
                '没理由就该删依赖。');
      }
    });
  });
}
