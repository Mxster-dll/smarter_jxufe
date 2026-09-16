/// 分数估计 · 课程备忘录（一段文字 + 若干图片）。
///
/// 设计口径（用户 2026-09-15 拍板）：
/// - **单块**：一门课只有一个备忘录 = 可编辑文字 + 图片网格（可追加/删除/看大图）；
/// - 图片**拷进应用私有目录**（`ge_memos/<账号>/<课程 id>/`），课程 JSON 里
///   **只存文件名**（同头像做法，见 `account_avatar_store.dart`）——
///   原图随后被删/移动/换机都不影响，卸载应用才会清掉；
/// - 导入时统一压到最长边 [geMemoMaxEdge]；单课最多 [geMemoMaxImages] 张、
///   单张导入上限 [geMemoImportMaxBytes]。
///
/// 本文件是**纯逻辑**（无 IO、无 Flutter 依赖），文件名清洗 / 扩展名归一 /
/// 体积文案 / 摘要文案都收在这里，界面与存储层只调用，不各自拼规则。
library;

/// 备忘录图片目录名（位于应用私有目录下）。
const String kGeMemoDirName = 'ge_memos';

/// 单门课程最多几张图片（超出后「添加」入口禁用并提示）。
const int geMemoMaxImages = 20;

/// 单张图片的导入上限（字节）：选中的文件超过它**在读取前**就被跳过。
const int geMemoImportMaxBytes = 20 * 1024 * 1024;

/// 导入压缩后的最长边（像素）：够看清板书/截图，又不至于占爆私有目录。
const int geMemoMaxEdge = 1600;

/// 已经满足「最长边 ≤ [geMemoMaxEdge]」且不超过这个体积时**原样保留**，
/// 不再二次编码（免得把本来就小的图越压越糊）。
const int geMemoKeepMaxBytes = 1536 * 1024;

/// JPEG 重编码质量。
const int geMemoJpegQuality = 88;

/// 允许的图片扩展名（小写）；不在表内一律归一为 `png`。
const Set<String> geMemoImageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
};

/// 有相机 / 相册的移动端平台（`TargetPlatform.name` 的小写形式）。
///
/// image_picker 在 Windows / macOS / Linux **没有相机实现**
/// （`ImageSource.camera` 会抛 `StateError`），所以「拍照」只在移动端出现。
const Set<String> kGeMemoMobilePlatforms = {'android', 'ios'};

/// 是否移动端（决定「拍照」入口是否出现、取图项文案）。
bool geMemoMobilePlatformOn(String platformName) =>
    kGeMemoMobilePlatforms.contains(platformName.toLowerCase());

/// 路径片段清洗：只保留字母数字与 `-`、`_`，其余（含路径分隔符）替换为 `_`。
///
/// 账号是学号、课程 id 是 uuid，正常都安全；清洗是为了防止意外字符
/// 拼出越界路径（`../` 之类）。
String geMemoSafeSegment(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'none' : cleaned;
}

/// 文件名 / 路径 → 归一化扩展名（带路径分隔符的「扩展名」不算扩展名）。
String geMemoNormalizeExt(String pathOrName) {
  final dot = pathOrName.lastIndexOf('.');
  var ext = dot == -1 ? '' : pathOrName.substring(dot + 1).toLowerCase();
  if (ext.contains('/') || ext.contains(r'\')) ext = '';
  if (!geMemoImageExtensions.contains(ext)) ext = 'png';
  return ext;
}

/// 体积文案：`0` / 未知 → 空串（调用方自行省略这段）。
String geMemoSizeText(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 容错取整数：类型不对（字符串 / null / 列表…）一律回退，**绝不抛**。
///
/// 直接用 `as num?` 遇到脏数据会抛 `type 'String' is not a subtype of type
/// 'num?'`，旧 JSON 一旦写坏整页就崩——备忘录是随手记的东西，必须容错。
int geMemoIntOf(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// 容错取字符串（非字符串 → 空串）。
String geMemoStringOf(Object? value) => value is String ? value : '';

/// 备忘录里的一张图片（只记文件名，文件本体在私有目录里）。
class GeMemoImage {  /// 私有目录内的文件名（不含目录），如 `3f2b….jpg`。
  final String fileName;

  /// 加入时间（epoch ms）。
  final int addedAt;

  /// 落盘后的字节数（0 = 未知，界面省略体积文案）。
  final int bytes;

  /// 落盘后的像素尺寸（0 = 未知）。
  final int width;
  final int height;

  const GeMemoImage({
    required this.fileName,
    this.addedAt = 0,
    this.bytes = 0,
    this.width = 0,
    this.height = 0,
  });

  /// 体积文案（空串 = 未知）。
  String get sizeText => geMemoSizeText(bytes);

  /// 像素文案（`2400×1080`；未知时空串）。
  String get pixelText =>
      (width > 0 && height > 0) ? '$width×$height' : '';

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'addedAt': addedAt,
    'bytes': bytes,
    'width': width,
    'height': height,
  };

  factory GeMemoImage.fromJson(Map<String, dynamic> json) => GeMemoImage(
    fileName: geMemoStringOf(json['fileName']),
    addedAt: geMemoIntOf(json['addedAt']),
    bytes: geMemoIntOf(json['bytes']).clamp(0, 1 << 40),
    width: geMemoIntOf(json['width']).clamp(0, 1 << 20),
    height: geMemoIntOf(json['height']).clamp(0, 1 << 20),
  );

  GeMemoImage copyWith({String? fileName, int? addedAt, int? bytes}) =>
      GeMemoImage(
        fileName: fileName ?? this.fileName,
        addedAt: addedAt ?? this.addedAt,
        bytes: bytes ?? this.bytes,
        width: width,
        height: height,
      );

  @override
  bool operator ==(Object other) =>
      other is GeMemoImage &&
      other.fileName == fileName &&
      other.addedAt == addedAt &&
      other.bytes == bytes &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode =>
      Object.hash(fileName, addedAt, bytes, width, height);

  @override
  String toString() => 'GeMemoImage($fileName, ${sizeText.isEmpty ? '?' : sizeText})';
}

/// 一门课的备忘录。
class GeMemo {
  /// 自由文字（可为空串）。
  final String text;

  /// 图片（顺序即展示顺序）。
  final List<GeMemoImage> images;

  const GeMemo({this.text = '', this.images = const []});

  /// 空备忘录（新建课程 / 旧数据无 `memo` 字段时使用）。
  static const GeMemo empty = GeMemo();

  /// 文字全为空白且没有任何图片 → 视为「没有备忘录」。
  bool get isEmpty => text.trim().isEmpty && images.isEmpty;

  bool get isNotEmpty => !isEmpty;

  bool get hasText => text.trim().isNotEmpty;

  bool get hasImages => images.isNotEmpty;

  int get imageCount => images.length;

  /// 还能再加几张（0 = 已满）。
  int get remainingSlots =>
      (geMemoMaxImages - images.length).clamp(0, geMemoMaxImages);

  bool get isFull => images.length >= geMemoMaxImages;

  /// 图片总字节（未知的按 0 计）。
  int get totalBytes =>
      images.fold(0, (sum, image) => sum + (image.bytes > 0 ? image.bytes : 0));

  GeMemo copyWith({String? text, List<GeMemoImage>? images}) =>
      GeMemo(text: text ?? this.text, images: images ?? this.images);

  Map<String, dynamic> toJson() => {
    'text': text,
    'images': [for (final image in images) image.toJson()],
  };

  /// 容错解析：缺字段 / 类型不对 → 空（绝不让旧数据崩页面）；
  /// `fileName` 为空的图片条目直接丢弃。
  factory GeMemo.fromJson(Object? json) {
    if (json is! Map) return GeMemo.empty;
    final rawImages = json['images'];
    final images = <GeMemoImage>[];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is! Map) continue;
        final image = GeMemoImage.fromJson(Map<String, dynamic>.from(item));
        if (image.fileName.isEmpty) continue;
        images.add(image);
        if (images.length >= geMemoMaxImages) break;
      }
    }
    return GeMemo(text: geMemoStringOf(json['text']), images: images);
  }

  @override
  bool operator ==(Object other) {
    if (other is! GeMemo) return false;
    if (other.text != text || other.images.length != images.length) {
      return false;
    }
    for (var i = 0; i < images.length; i++) {
      if (other.images[i] != images[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(images));

  @override
  String toString() => 'GeMemo(text: ${text.length} 字, images: ${images.length})';
}

/// 列表页小图标的提示 / 摘要文案（空备忘录 → 空串，调用方据此决定是否显示图标）。
String geMemoSummary(GeMemo memo) {
  if (memo.isEmpty) return '';
  final parts = <String>[
    if (memo.hasText) '文字',
    if (memo.hasImages) '${memo.imageCount} 张图片',
  ];
  return '备忘录：${parts.join(' + ')}';
}
