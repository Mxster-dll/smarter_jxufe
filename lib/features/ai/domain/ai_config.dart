/// 内置 AI 助手的配置模型（纯领域，不碰 Hive / 网络 / Flutter）。
///
/// 口径（改动前先读）：
/// - 接入形态统一为 **OpenAI 兼容** `/chat/completions`（用户 2026-09-19 拍板），
///   内置常见供应商预设（[aiPresets]），也可自定义 `baseUrl` + `model`；
/// - **多套配置并存**：`profiles` 是一个列表，`activeId` 指向当前生效的那套
///   —— 用户可以在 DeepSeek / 通义 / 本地 Ollama 之间来回切，不必重填；
/// - 所有 `fromJson` 一律**容错**：脏数据 / 缺字段 / 类型不对都回落默认值，
///   绝不让一次坏写入把设置页打崩（本仓既有约定，见 AGENTS.md §3）。
library;

/// 一份配置的默认值集中在这里，[AiConfig.fromJson] 与界面表单共用。
const String kAiDefaultBaseUrl = 'https://api.deepseek.com/v1';
const String kAiDefaultModel = 'deepseek-chat';
const double kAiDefaultTemperature = 0.3;
const int kAiDefaultMaxToolRounds = 6;

/// 温度的可选范围（界面滑动条与容错夹取共用）。
const double kAiMinTemperature = 0;
const double kAiMaxTemperature = 2;

/// 一次对话最多往返几轮工具调用。
///
/// 上限存在的意义：模型偶尔会陷入「反复查同一个工具」的循环，
/// 没有闸门就会一直烧 token。用户可在设置页调整，但夹在 1..12。
const int kAiMinToolRounds = 1;
const int kAiMaxToolRoundsLimit = 12;

/// 从任意 JSON 值取字符串（缺字段 / 类型不对 → [fallback]）。
String aiStrOf(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return fallback;
}

/// 从任意 JSON 值取 double（容错，可夹取范围）。
double aiDoubleOf(Object? value, double fallback, {double? min, double? max}) {
  double parsed;
  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value.trim()) ?? fallback;
  } else {
    parsed = fallback;
  }
  if (parsed.isNaN || parsed.isInfinite) return fallback;
  if (min != null && parsed < min) parsed = min;
  if (max != null && parsed > max) parsed = max;
  return parsed;
}

/// 从任意 JSON 值取 int（容错，可夹取范围）。
int aiIntOf(Object? value, int fallback, {int? min, int? max}) {
  int parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.round();
  } else if (value is String) {
    parsed = int.tryParse(value.trim()) ?? fallback;
  } else {
    parsed = fallback;
  }
  if (min != null && parsed < min) parsed = min;
  if (max != null && parsed > max) parsed = max;
  return parsed;
}

/// 从任意 JSON 值取 bool（`'true'` / `1` 都算真，容错）。
bool aiBoolOf(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
  }
  return fallback;
}

/// 归一化 baseUrl：去首尾空白、去尾部斜杠。
///
/// **不**在这里补 `/chat/completions`：有的端点（智谱 v4、Ollama）路径不同，
/// 且界面上要让用户看到自己填了什么。拼接统一由 [AiConfig.chatCompletionsUrl]
/// 负责，并且对「用户已经贴了完整端点」的情况做识别。
String aiNormalizeBaseUrl(String raw) {
  var value = raw.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

/// 一套 AI 配置。
class AiConfig {
  /// 稳定 id（多套配置的键；预设生成的配置也落一个 uuid）。
  final String id;

  /// 界面显示名（默认取预设名，可改）。
  final String name;

  /// 来源预设 id（[aiPresetOf] 用；自定义 = `'custom'`）。
  final String presetId;

  /// 接口根地址，如 `https://api.deepseek.com/v1`。
  final String baseUrl;

  /// 模型名，如 `deepseek-chat`。
  final String model;

  /// API Key（本机 Hive 私有目录，**不进云同步白名单**）。
  final String apiKey;

  /// 采样温度。
  final double temperature;

  /// 是否使用函数调用（tools）。
  ///
  /// 关掉 = 强制走「上下文注入」降级路径，适用于不支持 tools 的端点；
  /// 运行时若服务端明确拒绝 tools，也会自动降级（不写回本字段）。
  final bool useTools;

  /// 是否请求流式输出（打字机效果）。
  final bool stream;

  /// 是否把「轻量常驻快照」（我是谁 / 当下学期 / 今天几节课）塞进系统提示词。
  final bool includeSnapshot;

  /// 额外系统提示词（追加在内置提示词之后）。
  final String extraSystemPrompt;

  const AiConfig({
    required this.id,
    required this.name,
    required this.presetId,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.temperature = kAiDefaultTemperature,
    this.useTools = true,
    this.stream = true,
    this.includeSnapshot = true,
    this.extraSystemPrompt = '',
  });

  /// 由预设建一套配置（[id] 由调用方给 —— 领域层不依赖 uuid 包）。
  factory AiConfig.fromPreset(AiPreset preset, {required String id}) => AiConfig(
    id: id,
    name: preset.name,
    presetId: preset.id,
    baseUrl: preset.baseUrl,
    model: preset.defaultModel,
  );

  /// 空白配置（首次进设置页时的占位，不是可用配置）。
  factory AiConfig.blank({required String id}) => AiConfig(
    id: id,
    name: '未命名',
    presetId: 'custom',
    baseUrl: '',
    model: '',
  );

  /// 是否配好到「可以发请求」的程度。
  bool get ready =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  /// 缺哪一项（界面据此提示；已配好返回 null）。
  String? get missingField {
    if (baseUrl.trim().isEmpty) return '接口地址';
    if (model.trim().isEmpty) return '模型名';
    if (apiKey.trim().isEmpty) return 'API Key';
    return null;
  }

  /// 实际请求的 URL。
  ///
  /// 用户可能贴的是：
  /// - `https://api.deepseek.com/v1` → 补 `/chat/completions`；
  /// - `https://api.deepseek.com/v1/chat/completions`（已经贴全）→ 原样用；
  /// - `https://api.deepseek.com`（省略了 /v1）→ 补 `/v1/chat/completions`。
  ///
  /// 第三种是**实测最容易出错**的一种：DeepSeek / 硅基流动 / OpenAI 都要求
  /// 带 `/v1`，少了就 404。这里统一兜住，用户少填一层也能用。
  String get chatCompletionsUrl {
    var base = aiNormalizeBaseUrl(baseUrl);
    if (base.isEmpty) return '';
    if (base.endsWith('/chat/completions')) return base;
    // 已经带了版本段（/v1 /v2 /v4 /compatible-mode/v1 …）：只补端点。
    if (RegExp(r'/v\d+$').hasMatch(base) || base.endsWith('/compatible-mode')) {
      return '$base/chat/completions';
    }
    // 有路径但既不是版本段也不像端点（如智谱 `/api/paas/v4`）→ 尊重用户输入。
    final path = Uri.tryParse(base)?.path ?? '';
    if (path.isNotEmpty && path != '/') {
      return '$base/chat/completions';
    }
    return '$base/v1/chat/completions';
  }

  /// 模型列表接口（设置页「测试连接」只探到 401/200，不真发对话）。
  String get modelsUrl {
    final full = chatCompletionsUrl;
    if (full.endsWith('/chat/completions')) {
      return '${full.substring(0, full.length - '/chat/completions'.length)}/models';
    }
    return full;
  }

  AiConfig copyWith({
    String? id,
    String? name,
    String? presetId,
    String? baseUrl,
    String? model,
    String? apiKey,
    double? temperature,
    bool? useTools,
    bool? stream,
    bool? includeSnapshot,
    String? extraSystemPrompt,
  }) => AiConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    presetId: presetId ?? this.presetId,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    apiKey: apiKey ?? this.apiKey,
    temperature: temperature ?? this.temperature,
    useTools: useTools ?? this.useTools,
    stream: stream ?? this.stream,
    includeSnapshot: includeSnapshot ?? this.includeSnapshot,
    extraSystemPrompt: extraSystemPrompt ?? this.extraSystemPrompt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'presetId': presetId,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'temperature': temperature,
    'useTools': useTools,
    'stream': stream,
    'includeSnapshot': includeSnapshot,
    'extraSystemPrompt': extraSystemPrompt,
  };

  /// 容错解析：任何字段坏了都回落默认值，**绝不抛**。
  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final id = aiStrOf(json['id']).trim();
    return AiConfig(
      id: id.isEmpty ? 'default' : id,
      name: aiStrOf(json['name'], '未命名'),
      presetId: aiStrOf(json['presetId'], 'custom'),
      baseUrl: aiNormalizeBaseUrl(aiStrOf(json['baseUrl'])),
      model: aiStrOf(json['model']).trim(),
      apiKey: aiStrOf(json['apiKey']).trim(),
      temperature: aiDoubleOf(
        json['temperature'],
        kAiDefaultTemperature,
        min: kAiMinTemperature,
        max: kAiMaxTemperature,
      ),
      useTools: aiBoolOf(json['useTools'], true),
      stream: aiBoolOf(json['stream'], true),
      includeSnapshot: aiBoolOf(json['includeSnapshot'], true),
      extraSystemPrompt: aiStrOf(json['extraSystemPrompt']),
    );
  }

  /// 脱敏后的 key（设置页展示用：`sk-ab…cd12`）。
  String get maskedApiKey => maskAiApiKey(apiKey);

  @override
  String toString() => 'AiConfig($id, $name, $baseUrl, $model)';
}

/// key 脱敏：保留头 5 位与尾 4 位，中间一律 `…`；太短则整串打点。
String maskAiApiKey(String key) {
  final k = key.trim();
  if (k.isEmpty) return '';
  if (k.length <= 10) return '•' * k.length;
  return '${k.substring(0, 5)}…${k.substring(k.length - 4)}';
}

/// 一套供应商预设。
class AiPreset {
  final String id;
  final String name;

  /// 接口根地址（不带 `/chat/completions`）。
  final String baseUrl;

  /// 建议模型（第一个 = 默认选中的）。
  final List<String> models;

  /// 该供应商的 OpenAI 兼容端点是否支持 function calling。
  final bool supportsTools;

  /// 一句话说明（界面上给用户看，尤其「本地模型」这类要额外提示的）。
  final String note;

  const AiPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
    this.supportsTools = true,
    this.note = '',
  });

  /// 默认模型（[models] 为空时给空串 —— 自定义预设允许不预设模型）。
  String get defaultModel => models.isEmpty ? '' : models.first;
}

/// 内置预设表。**唯一出处** —— 界面下拉、[AiConfig.fromPreset] 都读这里。
///
/// `models` 只是「填得快」的建议值，用户永远可以手输别的模型名
/// （供应商上新的速度远快于客户端发版）。
const List<AiPreset> aiPresets = [
  AiPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    note: '支持函数调用；deepseek-reasoner 不支持 tools，选它会自动降级。',
  ),
  AiPreset(
    id: 'qwen',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-max', 'qwen-turbo'],
    note: '阿里云百炼的 OpenAI 兼容端点。',
  ),
  AiPreset(
    id: 'kimi',
    name: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: ['kimi-k2-0905-preview', 'moonshot-v1-32k', 'moonshot-v1-8k'],
  ),
  AiPreset(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-plus', 'glm-4-air', 'glm-4-flash'],
  ),
  AiPreset(
    id: 'siliconflow',
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: ['deepseek-ai/DeepSeek-V3', 'Qwen/Qwen2.5-72B-Instruct'],
    note: '聚合平台，模型名带厂商前缀。',
  ),
  AiPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4o-mini', 'gpt-4o'],
  ),
  AiPreset(
    id: 'ollama',
    name: 'Ollama（本地）',
    baseUrl: 'http://localhost:11434/v1',
    models: ['qwen2.5:7b', 'llama3.1:8b'],
    note: '本机跑模型；手机上填电脑局域网 IP。模型需支持 tools，否则自动降级。',
  ),
  AiPreset(
    id: 'custom',
    name: '自定义',
    baseUrl: '',
    models: [],
    note: '任何 OpenAI 兼容端点，自己填地址与模型名。',
  ),
];

/// 按 id 找预设；找不到返回「自定义」预设（**不返回 null** —— 界面少一处判空）。
AiPreset aiPresetOf(String id) {
  final key = id.trim();
  for (final p in aiPresets) {
    if (p.id == key) return p;
  }
  return aiPresets.last;
}

/// AI 助手的全部持久化设置（单 key JSON 进 Hive）。
class AiSettings {
  /// 保存的配置档（可多套）。
  final List<AiConfig> profiles;

  /// 当前生效配置的 id；为空或指向不存在的档时取第一套。
  final String activeId;

  /// 全局悬浮球是否显示。
  final bool floatingBall;

  /// 一次提问最多几轮工具调用。
  final int maxToolRounds;

  const AiSettings({
    this.profiles = const [],
    this.activeId = '',
    this.floatingBall = true,
    this.maxToolRounds = kAiDefaultMaxToolRounds,
  });

  /// 空设置（= 还没配过任何 API）。
  static const AiSettings empty = AiSettings();

  bool get hasAnyProfile => profiles.isNotEmpty;

  /// 当前生效配置；没有任何配置时返回 null。
  AiConfig? get active {
    if (profiles.isEmpty) return null;
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return profiles.first;
  }

  /// 当前配置是否可以直接开聊。
  bool get ready => active?.ready ?? false;

  AiSettings copyWith({
    List<AiConfig>? profiles,
    String? activeId,
    bool? floatingBall,
    int? maxToolRounds,
  }) => AiSettings(
    profiles: profiles ?? this.profiles,
    activeId: activeId ?? this.activeId,
    floatingBall: floatingBall ?? this.floatingBall,
    maxToolRounds: maxToolRounds ?? this.maxToolRounds,
  );

  /// 替换同 id 的配置（没有则追加）；并把 [activeId] 切到它 ——
  /// 「我刚编辑的那套」几乎总是想立刻用的那套。
  AiSettings upsertProfile(AiConfig profile) {
    final next = <AiConfig>[];
    var replaced = false;
    for (final p in profiles) {
      if (p.id == profile.id) {
        next.add(profile);
        replaced = true;
      } else {
        next.add(p);
      }
    }
    if (!replaced) next.add(profile);
    return copyWith(profiles: next, activeId: profile.id);
  }

  /// 删除一套配置；删掉的是当前生效档时，`activeId` 落到剩下的第一套。
  AiSettings removeProfile(String id) {
    final next = [
      for (final p in profiles)
        if (p.id != id) p,
    ];
    if (next.length == profiles.length) return this;
    final active = activeId == id ? (next.isEmpty ? '' : next.first.id) : activeId;
    return copyWith(profiles: next, activeId: active);
  }

  /// 切换生效配置（id 不在列表里则忽略）。
  AiSettings activate(String id) {
    for (final p in profiles) {
      if (p.id == id) return copyWith(activeId: id);
    }
    return this;
  }

  Map<String, dynamic> toJson() => {
    'profiles': [for (final p in profiles) p.toJson()],
    'activeId': activeId,
    'floatingBall': floatingBall,
    'maxToolRounds': maxToolRounds,
  };

  /// 容错解析：任何坏字段都回落默认；`profiles` 里坏掉的条目**逐条丢弃**
  /// （不整表丢弃 —— 一套配置坏了不该连累其它几套）。
  factory AiSettings.fromJson(Map<String, dynamic> json) {
    final rawProfiles = json['profiles'];
    final profiles = <AiConfig>[];
    if (rawProfiles is List) {
      for (final item in rawProfiles) {
        if (item is Map) {
          try {
            profiles.add(AiConfig.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // 单条坏 → 跳过，不影响其它配置
          }
        }
      }
    }
    return AiSettings(
      profiles: profiles,
      activeId: aiStrOf(json['activeId']),
      floatingBall: aiBoolOf(json['floatingBall'], true),
      maxToolRounds: aiIntOf(
        json['maxToolRounds'],
        kAiDefaultMaxToolRounds,
        min: kAiMinToolRounds,
        max: kAiMaxToolRoundsLimit,
      ),
    );
  }
}
