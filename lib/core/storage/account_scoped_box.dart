import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 个人数据的**账号级** Hive box 名：`<base>_<账号>`；账号未确定时用
/// `<base>__none`（**不**回落到旧的无账号 box，避免未登录时就露出上一个
/// 账号的数据）。
String accountScopedBoxName(String base, String? account) {
  final key = (account ?? '').trim();
  return key.isEmpty ? '${base}__none' : '${base}_$key';
}

/// 打开账号级个人数据 box，并在**首次**打开时把历史版本的无账号 box 迁移过来。
///
/// 为什么按 box 隔离而不是给 key 加前缀：成绩缓存同时存在多份「不同查询参数」
/// 的副本、学籍是单键整表、调课是按学期分键——按 box 隔离后这些 key 格式
/// **一个字都不用改**，遍历 key 的聚合逻辑（如 `ge_prior_grades.dart`）也不会漏，
/// 更不会因为忘记加前缀而漏隔离一处。
///
/// 迁移只发生一次：旧 box 里写下认领标记（[claimedKey]），因此旧数据只会被
/// **第一个**打开的账号继承——切到别的账号不会继承他人数据。
///
/// 任何异常都不抛出：box 打不开时返回一个可用的（可能为空的）box，
/// 由调用方按"无缓存"处理，不能让缓存问题阻塞页面。
Future<Box<String>> openAccountScopedBox(String base, String? account) async {
  final box = await Hive.openBox<String>(accountScopedBoxName(base, account));
  final key = (account ?? '').trim();
  if (key.isEmpty || box.isNotEmpty) return box;
  try {
    await _migrateLegacy(base: base, account: key, target: box);
  } catch (e) {
    debugPrint('[accountScopedBox] $base → $key 迁移失败：$e');
  }
  return box;
}

/// 旧 box 里记录"已被某账号认领"的键。
@visibleForTesting
const claimedKey = '__migratedTo';

Future<void> _migrateLegacy({
  required String base,
  required String account,
  required Box<String> target,
}) async {
  final legacy = await Hive.openBox<String>(base);
  if (legacy.isEmpty) return;
  if ((legacy.get(claimedKey) ?? '').isNotEmpty) return;

  // 逐键复制（不用 Box.copyTo：行为更可控，也便于跳过标记键）。
  for (final k in legacy.keys) {
    final name = k.toString();
    if (name == claimedKey) continue;
    final value = legacy.get(k);
    if (value != null) await target.put(name, value);
  }
  await legacy.put(claimedKey, account);
  debugPrint('[accountScopedBox] $base → $account 已迁移 ${target.length} 条');
}
