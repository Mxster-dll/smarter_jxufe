/// 学习通取数的**风控预算**常量（**纯 Dart：不 import flutter**）。
///
/// 为什么单独一个文件：反侧命令脚本 `tool/chaoxing_smoke.dart` 也要用这些数，
/// 而它是 `dart run` 跑的纯 Dart 程序 —— 一旦 import 了 `chaoxing_repository.dart`
/// （依赖 `flutter/foundation` 的 `debugPrint`），就会把 Flutter SDK 源码拖进编译，
/// 报一堆 `The getter 'Radius' isn't defined` 之类的错。
///
/// 实测口径与推导过程见 `reverse_engineering/学习通接口.md` §8 与模块 README。
library;

/// 每轮最多扫几门课的作业（**分批轮转**的窗口大小）。
///
/// 风控的触发量是**累计请求数（≈60 个/窗口）**而不是速率 —— 实测 2 请求/秒匀速扫完
/// 35 门课（70 个请求），仍在第 31 门（≈62 个请求）起整段变成验证码页；首版并发 4
/// 更快，同样在末尾 6 门中招。所以一次全扫**必然撞墙**：20 门 ≈ 40 个请求，留够余量，
/// 游标滚动 → 两轮覆盖 35 门。
const int chaoxingMaxCoursesPerScan = 20;

/// 业务请求之间的最小间隔（≈3.8 请求/秒上限）。
///
/// ⚠ 只是**辅助**手段：真正决定能不能过的是 [chaoxingMaxCoursesPerScan] 那个预算。
/// 实测稳态 1 请求/秒 × 20 个请求 → 0 次风控，但那是因为只发了 20 个请求、没到预算。
const Duration chaoxingMinRequestInterval = Duration(milliseconds: 260);

/// 命中风控后的冷却时长（实测风控窗口 ≥ 60 秒，取一倍余量）。
const Duration chaoxingChallengeCooldown = Duration(seconds: 120);
