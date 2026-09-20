/// 数据中心「所属校区」→「我的校区」的**补空**接线。
///
/// 用户 2026-09-20 原话：「现在『设置』页的校区设置，改成直接用数据中心的数据，
/// 如果获取失败，再手动设置」。同日追问「数据中心与你手选的校区不一致时以谁为准」
/// 后裁定：**手动优先，数据中心只补空** ——
/// 手选过的以手选为准（临时去别的校区、转专业换校区都靠自己说了算），
/// 从没设过才自动用数据中心的值；数据中心取不到（未登录 / 会话失效 / 没有这一列）
/// 就什么都不做，设置页照常让用户手选。
///
/// 为什么单独一个文件：`my_campus_prefs.dart` 只管「内存缓存 + Hive 落盘」，
/// 不该知道数据中台；这里是两者之间**唯一**的接缝（一个 provider + 一个接线函数）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';

/// 数据中心那一列的中文列名（学工系统「基本信息」表单）。
const String dzjCampusFieldLabel = '所属校区';

/// 数据中心给出的校区；取不到 / 对不上统一口径（[MyCampus]）时为 `null`。
///
/// 实测回「麦庐园校区」，与 [MyCampus.label] 同名；名字对不上就返回 null
/// （宁可让用户手选，也不猜一个校区出来）。
final myCampusHintProvider = Provider<MyCampus?>((ref) {
  final info = ref.watch(dzjBasicInfoProvider).valueOrNull;
  return MyCampus.fromName(info?[dzjCampusFieldLabel]);
});

/// 把「数据中心 → 我的校区」的补空接线装到 [fillIfEmpty] 上。
///
/// `fireImmediately: true`：数据中心那一份是**异步**到的（一次会话 + 一次表单请求），
/// 首帧还没有值 → 先挂上监听，值到了（或失败回空表）再触发一次。
/// [fillIfEmpty] 自身幂等且「拿到值才落闸」，所以首帧必然的空不会被误当成「没设过」。
///
/// 直接听**异步源**（而不是中间的 [myCampusHintProvider]）：后者是给界面显示用的，
/// 它的重算依赖有人去读；补空是副作用，不能押在「恰好有页面在 watch 它」上。
void bindMyCampusCenterFill(Ref ref, void Function(MyCampus?) fillIfEmpty) {
  ref.listen<AsyncValue<Map<String, String>>>(
    dzjBasicInfoProvider,
    (_, next) =>
        fillIfEmpty(MyCampus.fromName(next.valueOrNull?[dzjCampusFieldLabel])),
    fireImmediately: true,
  );
}
