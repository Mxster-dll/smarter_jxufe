import 'package:riverpod/riverpod.dart';

/// 当前登录账户卡号（学号），切换账户时更新此值。
///
/// ⚠️ 单独成文件（而不是留在 `dio_providers.dart`）是为了打断循环依赖：
/// `imsSessionProvider`（features/ims/auth）要 watch 它，而 `dio_providers.dart`
/// 又要 import `imsSessionProvider` 来提供 `currentImsDioProvider`。
/// `dio_providers.dart` 已 `export` 本文件，因此既有 `import 'dio_providers.dart'`
/// 的调用方无需改动。
final currentAccountProvider = StateProvider<String>((ref) => '');
