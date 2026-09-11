// 账号头像：文件名规范 + 三级回退 + 私有目录文件存储单测。
//
// 用户口径（2026-09 裁定）：
// - 头像**绑定账号、存本机**：账户记录里只存文件名，选图时把原图拷进
//   应用私有目录 `avatars/`（原图随后删/移都不影响）；
// - 回退顺序：本地图片 → 姓名首字 → 通用图标（连首字都没有才退图标）；
// - 提供「移除头像」→ 删文件 + 清字段 → 回到首字头像。

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smarter_jxufe/features/auth/data/account_avatar_controller.dart';
import 'package:smarter_jxufe/features/auth/data/account_avatar_store.dart';
import 'package:smarter_jxufe/features/auth/domain/account_avatar.dart';

void main() {
  group('avatarBaseName（卡号 → 文件名主干）', () {
    test('纯数字学号原样保留', () {
      expect(avatarBaseName('0000000'), '0000000');
    });

    test('非字母数字替换为下划线（路径分隔符不会漏进文件名）', () {
      expect(avatarBaseName(r'a/b\c:d'), 'a_b_c_d');
    });

    test('空卡号兜底 account', () {
      expect(avatarBaseName(''), 'account');
    });
  });

  group('avatarFileName（扩展名归一）', () {
    test('白名单扩展名保留并转小写', () {
      expect(avatarFileName('0000000', r'D:\pic\IMG.JPEG'), '0000000.jpeg');
      expect(avatarFileName('0000000', '/tmp/a.webp'), '0000000.webp');
    });

    test('非白名单扩展名归一为 png（heic / 无扩展名）', () {
      expect(avatarFileName('0000000', r'D:\pic\IMG.heic'), '0000000.png');
      expect(avatarFileName('0000000', r'D:\pic\noext'), '0000000.png');
    });

    test('路径里的点不算扩展名', () {
      expect(avatarFileName('0000000', r'D:\my.dir\noext'), '0000000.png');
    });
  });

  group('resolveAvatarKind（三级回退）', () {
    test('有本地图片 → image（仍给出首字作图片加载失败的底层兜底）', () {
      final r = resolveAvatarKind(hasFile: true, displayName: '张三');
      expect(r.kind, AvatarKind.image);
      expect(r.initial, '张');
    });

    test('无图片但有名字 → initial 取首字', () {
      final r = resolveAvatarKind(hasFile: false, displayName: '李四');
      expect(r.kind, AvatarKind.initial);
      expect(r.initial, '李');
    });

    test('无图片且没名字（含全空白）→ placeholder', () {
      expect(
        resolveAvatarKind(hasFile: false, displayName: '').kind,
        AvatarKind.placeholder,
      );
      expect(resolveAvatarKind(hasFile: false, displayName: '   ').initial, '');
    });

    test('有图片但没名字 → image 且首字为空', () {
      final r = resolveAvatarKind(hasFile: true, displayName: '');
      expect(r.kind, AvatarKind.image);
      expect(r.initial, '');
    });
  });

  group('AccountAvatarStore（私有目录文件）', () {
    late Directory root;
    late Directory source;
    late AccountAvatarStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('sjx_avatar_store_');
      source = Directory(p.join(root.path, 'src'))..createSync(recursive: true);
      store = AccountAvatarStore(Directory(p.join(root.path, 'avatars')));
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    File makeSource(String name) =>
        File(p.join(source.path, name))..writeAsBytesSync([1, 2, 3]);

    test('保存后 resolve 命中，且文件落在私有目录内', () async {
      final fileName = await store.save('0000000', makeSource('me.png').path);
      expect(fileName, '0000000.png');

      final resolved = store.resolve(fileName);
      expect(resolved, isNotNull);
      expect(File(resolved!).existsSync(), isTrue);
      expect(p.isWithin(store.directory.path, resolved), isTrue);
    });

    test('换扩展名时清掉旧文件（一个账号只留一个）', () async {
      final first = await store.save('0000000', makeSource('a.png').path);
      final second = await store.save('0000000', makeSource('b.jpg').path);
      expect(first, '0000000.png');
      expect(second, '0000000.jpg');
      expect(File(store.pathOf(first)).existsSync(), isFalse);
      expect(store.directory.listSync().whereType<File>().length, 1);
    });

    test('不同账号互不干扰', () async {
      await store.save('0000000', makeSource('a.png').path);
      await store.save('0252514', makeSource('b.png').path);
      expect(store.directory.listSync().whereType<File>().length, 2);

      await store.removeAllOf('0000000');
      expect(store.resolve('0000000.png'), isNull);
      expect(store.resolve('0252514.png'), isNotNull);
    });

    test('remove 后 resolve 返回 null（→ 界面回退首字）', () async {
      final fileName = await store.save('0000000', makeSource('a.png').path);
      await store.remove(fileName);
      expect(store.resolve(fileName), isNull);
    });

    test('源文件就是已存头像 → 不自我删除', () async {
      final fileName = await store.save('0000000', makeSource('a.png').path);
      final again = await store.save('0000000', store.pathOf(fileName));
      expect(again, fileName);
      expect(store.resolve(fileName), isNotNull);
    });

    test('空文件名 / 文件缺失 / 目录缺失都安静返回，不抛', () async {
      expect(store.resolve(''), isNull);
      expect(store.resolve('nope.png'), isNull);
      await store.remove('nope.png');
      await store.removeAllOf('0000000');
    });
  });

  group('avatarMobilePlatformOn（拍照入口是否出现）', () {
    // image_picker 在 Windows / macOS / Linux 没有相机实现
    // （ImageSource.camera 抛 StateError）→ 只有移动端给「拍照」入口。
    test('Android / iOS 为真（大小写不敏感，TargetPlatform.name 是 iOS）', () {
      expect(avatarMobilePlatformOn('android'), isTrue);
      expect(avatarMobilePlatformOn('iOS'), isTrue);
      expect(avatarMobilePlatformOn('ANDROID'), isTrue);
    });

    test('桌面三平台为假', () {
      expect(avatarMobilePlatformOn('windows'), isFalse);
      expect(avatarMobilePlatformOn('macOS'), isFalse);
      expect(avatarMobilePlatformOn('linux'), isFalse);
    });

    test('白名单就是这两个平台（防止顺手加进没有相机的平台）', () {
      expect(kAvatarMobilePlatforms, {'android', 'ios'});
    });
  });

  group('avatarResultForPickError（选图异常 → 结果）', () {
    test('相机权限被拒单独区分（合并清单里有 CAMERA，插件会先请求运行时权限）', () {
      expect(
        avatarResultForPickError(
          PlatformException(
            code: 'camera_access_denied',
            message: 'The user did not allow camera access.',
          ),
        ),
        AvatarActionResult.permissionDenied,
      );
    });

    test('其它异常一律 failed（含插件自身其它错误码与非 PlatformException）', () {
      expect(
        avatarResultForPickError(PlatformException(code: 'multiple_request')),
        AvatarActionResult.failed,
      );
      expect(
        avatarResultForPickError(StateError('no camera on this platform')),
        AvatarActionResult.failed,
      );
    });
  });
}
