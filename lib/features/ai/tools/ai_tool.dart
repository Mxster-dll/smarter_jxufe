/// AI 工具框架：工具契约、参数读取、写操作闸门、JSON Schema 构造助手。
///
/// 放在 `tools/` 而不是 `domain/`：工具实现要读 Riverpod provider（即要联网/读缓存），
/// 天生不是纯领域。`domain/` 只放不碰 IO 的模型。
///
/// 设计口径（改前先读）：
/// - 工具**返回值是给模型看的文本**，不是给 UI 看的对象 —— 所以一律紧凑中文、
///   能省的字都省（token 是要花钱的），结构化数据放 [AiToolResult.ui] 供界面展示；
/// - 参数读取一律走 [AiArgs]，**不写 `args['x'] as String`**（模型给错类型会直接崩，
///   本仓已因同类写法踩过 `type 'String' is not a subtype of type 'num?'`）；
/// - 写操作工具必须 `mutating => true` 并在执行前过 [AiWriteGate] —— 用户拍板的
///   「只读 + 写操作二次确认」就落在这个闸门上。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一个工具的声明（会原样塞进请求体的 `tools`）。
class AiToolSpec {
  final String name;

  /// 给模型看的功能说明。**写得越清楚，模型选错工具的概率越低** ——
  /// 尤其要写清「什么时候用」和「返回什么」，而不仅是「这是什么」。
  final String description;

  /// JSON Schema（`{type:'object', properties:{...}, required:[...]}`）。
  final Map<String, dynamic> parameters;

  const AiToolSpec({
    required this.name,
    required this.description,
    this.parameters = const {'type': 'object', 'properties': <String, dynamic>{}},
  });

  Map<String, dynamic> toWire() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };

  @override
  String toString() => 'AiToolSpec($name)';
}

/// 工具执行结果。
class AiToolResult {
  /// 是否成功（失败时 [content] 依然要有内容 —— 它是给模型看的错误说明，
  /// 模型据此决定「换个参数重试」还是「如实告诉用户」）。
  final bool ok;

  /// 给模型的文本。
  final String content;

  /// 给界面的结构化数据（可选；界面用它渲染卡片 / 生成跳转按钮）。
  final Map<String, dynamic>? ui;

  const AiToolResult.ok(this.content, {this.ui}) : ok = true;

  const AiToolResult.fail(this.content, {this.ui}) : ok = false;

  @override
  String toString() => 'AiToolResult(ok=$ok, ${content.length}字)';
}

/// 一次写操作的确认请求（弹给用户看的内容）。
class AiWriteRequest {
  final String toolName;

  /// 一句话标题，如「修改课表显示设置」。
  final String title;

  /// 具体做什么（人话，不是 JSON）。
  final String detail;

  final Map<String, dynamic> args;

  const AiWriteRequest({
    required this.toolName,
    required this.title,
    required this.detail,
    this.args = const {},
  });
}

/// 写操作闸门。由 UI 层实现（弹确认框）；不接 UI 时用 [AiDenyWriteGate] 兜底。
abstract class AiWriteGate {
  Future<bool> confirm(AiWriteRequest request);
}

/// 默认闸门：一律拒绝。
///
/// 这是**安全默认值** —— 万一某个入口忘了接 UI 闸门，写操作会失败而不是静默执行。
class AiDenyWriteGate implements AiWriteGate {
  const AiDenyWriteGate();

  @override
  Future<bool> confirm(AiWriteRequest request) async => false;
}

/// 工具执行上下文。
class AiToolContext {
  /// Riverpod 容器引用（工具靠它读既有 provider 取数）。
  final Ref ref;

  /// 写操作闸门。
  final AiWriteGate gate;

  /// 当前时刻（**注入时钟**：无课时间、今天第几周都要用，测试里要能固定）。
  final DateTime now;

  const AiToolContext({required this.ref, required this.gate, required this.now});
}

/// 一个工具。
abstract class AiTool {
  const AiTool();

  AiToolSpec get spec;

  /// 是否是写操作（true = 执行前必须过闸门）。
  bool get mutating => false;

  /// 当前是否可用。false 时**不会**下发给模型（避免模型去调一个必然失败的工具）。
  bool available(AiToolContext ctx) => true;

  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args);
}

/// 参数读取器：容错 + 一次性收集错误。
///
/// 用法：
/// ```dart
/// final a = AiArgs(args);
/// final name = a.str('teacher_name');
/// final week = a.intOf('week', fallback: 0);
/// if (a.hasError) return AiToolResult.fail(a.errorText);
/// ```
class AiArgs {
  final Map<String, dynamic> raw;
  final List<String> _errors = [];

  AiArgs(this.raw);

  /// 是否有参数问题。
  bool get hasError => _errors.isNotEmpty;

  /// 给模型看的错误说明（列全所有问题，让模型一次改对）。
  String get errorText => '参数有误：${_errors.join('；')}';

  /// 手工记一条参数错误。
  ///
  /// 给「跨字段组合校验」用（例如 `xn` 与 `xq` 只能取某个范围）——
  /// 这类判据读不出单个字段就下结论，所以走这个出口，而不是另写一套错误通道。
  void noteError(String text) => _errors.add(text);

  /// 必填字符串。
  String str(String key, {String fallback = ''}) {
    final v = raw[key];
    if (v == null) {
      if (fallback.isEmpty) _errors.add('缺少参数 $key');
      return fallback;
    }
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty && fallback.isEmpty) _errors.add('参数 $key 不能为空');
      return t.isEmpty ? fallback : t;
    }
    if (v is num || v is bool) return '$v';
    _errors.add('参数 $key 类型不对');
    return fallback;
  }

  /// 可选字符串（缺 / 空 → null）。
  String? optStr(String key) {
    final v = raw[key];
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    if (v is num || v is bool) return '$v';
    _errors.add('参数 $key 类型不对');
    return null;
  }

  /// 整数（缺 → [fallback]；给了但类型不对 → 记错误并回落）。
  int intOf(String key, {int fallback = 0, bool clampToPositive = false}) {
    final v = raw[key];
    if (v == null) return fallback;
    int parsed;
    if (v is int) {
      parsed = v;
    } else if (v is num) {
      parsed = v.round();
    } else if (v is String) {
      final p = int.tryParse(v.trim());
      if (p == null) {
        _errors.add('参数 $key 不是整数');
        return fallback;
      }
      parsed = p;
    } else {
      _errors.add('参数 $key 类型不对');
      return fallback;
    }
    if (clampToPositive && parsed < 0) parsed = 0;
    return parsed;
  }

  /// 布尔（认 `'true'` / `1`）。
  bool boolOf(String key, {bool fallback = false}) {
    final v = raw[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      if (t == 'true' || t == '1' || t == 'yes') return true;
      if (t == 'false' || t == '0' || t == 'no') return false;
    }
    _errors.add('参数 $key 不是布尔值');
    return fallback;
  }

  /// 字符串列表（也吃「单个字符串」与「用逗号/顿号分隔的字符串」——
  /// 模型经常把数组写成一个字符串）。
  List<String> strList(String key) {
    final v = raw[key];
    if (v == null) return const [];
    if (v is List) {
      return [
        for (final item in v)
          if (item != null) '$item'.trim(),
      ].where((s) => s.isNotEmpty).toList();
    }
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return const [];
      return [
        for (final part in t.split(RegExp(r'[,，、;；\s]+')))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    _errors.add('参数 $key 应为字符串列表');
    return const [];
  }

  /// 整数列表（同上，容忍单值 / 逗号分隔）。
  List<int> intList(String key) {
    final v = raw[key];
    if (v == null) return const [];
    if (v is num) return [v.round()];
    if (v is List) {
      final out = <int>[];
      for (final item in v) {
        if (item is num) {
          out.add(item.round());
        } else if (item is String) {
          final p = int.tryParse(item.trim());
          if (p != null) out.add(p);
        }
      }
      return out;
    }
    if (v is String) {
      return [
        for (final part in v.split(RegExp(r'[,，、;；\s]+')))
          if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
      ];
    }
    _errors.add('参数 $key 应为整数列表');
    return const [];
  }
}

// ─────────────────────────── JSON Schema 构造助手 ───────────────────────────
// 手写 schema 太啰嗦，而工具描述的质量直接决定模型选工具的准确率 —— 这组
// 助手把「写一个清晰 schema」的成本压到最低。

/// 组装一个 object schema。
Map<String, dynamic> aiObjectSchema(
  Map<String, dynamic> properties, {
  List<String> required = const [],
  String? description,
}) {
  final schema = <String, dynamic>{'type': 'object', 'properties': properties};
  if (required.isNotEmpty) schema['required'] = required;
  if (description != null) schema['description'] = description;
  return schema;
}

/// 字符串字段。
Map<String, dynamic> aiStrProp(
  String description, {
  List<String>? enums,
  String? fallbackHint,
}) {
  final prop = <String, dynamic>{
    'type': 'string',
    'description': fallbackHint == null ? description : '$description（$fallbackHint）',
  };
  if (enums != null) prop['enum'] = enums;
  return prop;
}

/// 整数字段。
Map<String, dynamic> aiIntProp(String description, {int? min, int? max}) {
  final prop = <String, dynamic>{'type': 'integer', 'description': description};
  if (min != null) prop['minimum'] = min;
  if (max != null) prop['maximum'] = max;
  return prop;
}

/// 布尔字段。
Map<String, dynamic> aiBoolProp(String description) => {
  'type': 'boolean',
  'description': description,
};

/// 字符串数组字段。
Map<String, dynamic> aiStrListProp(String description) => {
  'type': 'array',
  'description': description,
  'items': {'type': 'string'},
};

/// 整数数组字段。
Map<String, dynamic> aiIntListProp(String description) => {
  'type': 'array',
  'description': description,
  'items': {'type': 'integer'},
};
