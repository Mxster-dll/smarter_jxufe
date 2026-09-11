/// 账号头像的文件名规范与三级回退判定。
///
/// 纯逻辑（无 IO、无 Flutter 依赖），便于单测：
/// 文件名生成 / 扩展名归一 / 回退形态判定都收在这里，
/// 界面与存储层只调用，不各自拼规则。
library;

/// 头像目录名（位于应用私有目录下）。
const String kAvatarDirName = 'avatars';

/// 允许的图片扩展名（小写）；不在表内一律归一为 `png`。
const Set<String> kAvatarExtensions = {
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
/// （`ImageSource.camera` 会抛 `StateError`，除非注入 `cameraDelegate`），
/// 所以「拍照」入口只在移动端出现；桌面端保留文件选择一项。
const Set<String> kAvatarMobilePlatforms = {'android', 'ios'};

/// 是否移动端（纯函数，便于单测）：
/// 决定「拍照」入口是否出现，以及取图项文案是「从相册选择」还是「选择图片文件」。
bool avatarMobilePlatformOn(String platformName) =>
    kAvatarMobilePlatforms.contains(platformName.toLowerCase());

/// 卡号 → 文件名主干：只保留字母数字，其余替换为 `_`；空卡号兜底 `account`。
///
/// （卡号是学号/工号，正常全数字；清洗是为了防止路径分隔符等意外字符。）
String avatarBaseName(String cardNumber) {
  final cleaned = cardNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  return cleaned.isEmpty ? 'account' : cleaned;
}

/// 选中的图片路径 → 存入账户记录的文件名（`主干.扩展名`）。
String avatarFileName(String cardNumber, String sourcePath) {
  final dot = sourcePath.lastIndexOf('.');
  var ext = dot == -1 ? '' : sourcePath.substring(dot + 1).toLowerCase();
  // 带路径分隔符的“扩展名”不是扩展名（如 `...\no-ext`）
  if (ext.contains('/') || ext.contains(r'\')) ext = '';
  if (!kAvatarExtensions.contains(ext)) ext = 'png';
  return '${avatarBaseName(cardNumber)}.$ext';
}

/// 头像取图来源（相册/文件对话框 = gallery，相机拍照 = camera）。
enum AvatarSource { gallery, camera }

/// 头像展现形态（回退顺序：本地图片 → 姓名首字 → 通用图标）。
enum AvatarKind { image, initial, placeholder }

/// 三级回退判定。
///
/// [hasFile] = 本地头像文件确实存在；[displayName] 为空即“连首字都没有”。
/// 返回的 [initial] 在 `image` 形态下也会照常给出，
/// 用作图片加载失败时 CircleAvatar 的底层兜底字符。
({AvatarKind kind, String initial}) resolveAvatarKind({
  required bool hasFile,
  required String displayName,
}) {
  final name = displayName.trim();
  final initial = name.isEmpty ? '' : name[0];
  if (hasFile) return (kind: AvatarKind.image, initial: initial);
  if (initial.isEmpty) return (kind: AvatarKind.placeholder, initial: '');
  return (kind: AvatarKind.initial, initial: initial);
}
