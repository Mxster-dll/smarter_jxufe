import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smarter_jxufe/features/auth/data/account_avatar_store.dart';
import 'package:smarter_jxufe/features/auth/data/account_repository.dart';
import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

/// 头像操作结果。
enum AvatarActionResult {
  /// 已更换 / 已移除。
  updated,

  /// 用户取消（或本来就没有可移除的头像）。
  cancelled,

  /// 失败（选图异常、拷贝失败、落盘失败）。
  failed,

  /// 相机权限被拒 —— 单独区分，否则用户只会看到「请重试」而无从下手。
  permissionDenied,
}

/// 选图抛出的异常 → 操作结果。
///
/// 拍照要走系统相机：本应用的合并清单里有 `android.permission.CAMERA`
/// （由 `com.journeyapps:zxing-android-embedded` 带入），
/// 因此 image_picker 会先请求运行时权限，被拒时抛
/// `PlatformException(code: 'camera_access_denied')`。
AvatarActionResult avatarResultForPickError(Object error) {
  if (error is PlatformException && error.code == 'camera_access_denied') {
    return AvatarActionResult.permissionDenied;
  }
  return AvatarActionResult.failed;
}

/// 当前账号头像控制器 —— 本地文件 + 账户记录字段（`Account.avatar`）。
///
/// 用 [ChangeNotifier] 即时广播：首页顶栏与「我的」页读同一个实例，
/// 换图/移除**同帧**生效。不用 `FutureProvider` —— 那中间有异步空窗，
/// 界面会先闪一次旧头像（见会话级 AGENTS.md §3 的偏好存储约定）。
class AccountAvatarController extends ChangeNotifier {
  AccountAvatarStore? _store;
  AccountRepository? _repository;
  String _cardNumber = '';
  String _fileName = '';
  String? _filePath;
  bool _busy = false;

  /// 当前账号卡号（空 = 未登录）。
  String get cardNumber => _cardNumber;

  /// 账户记录里存的文件名（空 = 未设置头像）。
  String get fileName => _fileName;

  /// 本地头像绝对路径；null = 无头像（界面回退首字 / 图标）。
  String? get filePath => _filePath;

  bool get hasImage => _filePath != null;

  /// 正在选图/落盘（界面可显示进度）。
  bool get busy => _busy;

  /// 依赖齐备且已登录（否则换图入口应视为不可用）。
  bool get ready =>
      _store != null && _repository != null && _cardNumber.isNotEmpty;

  /// 当前平台是否有相机（Android / iOS）。
  ///
  /// 界面据此决定「拍照」项是否出现 —— 桌面端 image_picker 只有文件对话框，
  /// `ImageSource.camera` 会抛 `StateError`（见 AGENTS.md §11.3）。
  bool get isMobile => avatarMobilePlatformOn(defaultTargetPlatform.name);

  /// 绑定依赖并同步当前账号头像（provider 在存储/账户就绪、账号切换时调用）。
  void bind({
    required AccountAvatarStore store,
    required AccountRepository repository,
    required String cardNumber,
  }) {
    _store = store;
    _repository = repository;
    _cardNumber = cardNumber;
    _fileName = _fileNameOf(repository, cardNumber);
    _filePath = store.resolve(_fileName);
    notifyListeners();
  }

  /// 取图 → 拷贝进私有目录 → 文件名写进账户记录。
  ///
  /// [source]：[AvatarSource.gallery] = 相册（桌面端即文件对话框），
  /// [AvatarSource.camera] = 拍照（**仅移动端**，桌面无相机实现 → `failed`）。
  /// 头像不需要原图分辨率，统一压到 1080px / 质量 90 以省私有目录空间。
  Future<AvatarActionResult> pick({
    AvatarSource source = AvatarSource.gallery,
  }) async {
    final store = _store;
    final repository = _repository;
    if (store == null || repository == null || _cardNumber.isEmpty || _busy) {
      return AvatarActionResult.failed;
    }
    if (source == AvatarSource.camera && !isMobile) {
      return AvatarActionResult.failed;
    }

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source == AvatarSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 90,
      );
    } catch (error) {
      return avatarResultForPickError(error);
    }
    if (picked == null) {
      return AvatarActionResult.cancelled;
    }
    final sourcePath = picked.path;
    if (sourcePath.isEmpty) {
      return AvatarActionResult.failed;
    }

    _busy = true;
    notifyListeners();
    try {
      final fileName = await store.save(_cardNumber, sourcePath);
      final saved = await repository.updateAvatar(_cardNumber, fileName);
      if (saved.isLeft()) return AvatarActionResult.failed;
      _fileName = fileName;
      _filePath = store.resolve(fileName);
      return AvatarActionResult.updated;
    } catch (_) {
      return AvatarActionResult.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 移除头像：账户字段清空 + 删本地文件 → 回退姓名首字。
  Future<AvatarActionResult> clear() async {
    final store = _store;
    final repository = _repository;
    if (store == null || repository == null || _cardNumber.isEmpty || _busy) {
      return AvatarActionResult.failed;
    }
    if (_fileName.isEmpty && _filePath == null) {
      return AvatarActionResult.cancelled;
    }

    _busy = true;
    notifyListeners();
    try {
      final saved = await repository.updateAvatar(_cardNumber, '');
      if (saved.isLeft()) return AvatarActionResult.failed;
      final oldFileName = _fileName;
      _fileName = '';
      _filePath = null;
      await store.remove(oldFileName);
      return AvatarActionResult.updated;
    } catch (_) {
      return AvatarActionResult.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 从账户列表里取该卡号的头像文件名（账户缺失 / 未登录 → 空串）。
  String _fileNameOf(AccountRepository repository, String cardNumber) {
    if (cardNumber.isEmpty) return '';
    final accounts = repository.getAccounts().fold(
      (_) => const <Account>[],
      (list) => list,
    );
    for (final account in accounts) {
      if (account.cardNumber == cardNumber) return account.avatar;
    }
    return '';
  }
}
