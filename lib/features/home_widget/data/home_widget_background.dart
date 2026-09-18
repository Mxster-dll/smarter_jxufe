import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/widgets.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/home_widget/domain/home_widget_snapshot.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session_renewal.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/weighted_grade_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/weighted_grade_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

/// 后台刷新入口实现（真正的入口点在 `lib/main.dart` 的 `homeWidgetBackgroundMain`，
/// 因为 Flutter 只在 root library 里解析命名入口点）。
///
/// 原生侧通过**命名入口点**调用：
/// `DartEntrypoint(loader.findAppBundlePath(), "homeWidgetBackgroundMain")`
/// —— Flutter 3.38 的嵌入层已移除 `FlutterCallbackInformation` /
/// 回调句柄那套 API，命名入口点是当前唯一可行的方式。
///
/// 与主 isolate 的关键区别：**不碰 Hive**——两个 isolate 同时打开同一个
/// box 会有写冲突，因此后台所需的认证材料（学号 / 密码 / TGC / JSESSIONID /
/// 房间号）全部走原生 SharedPreferences，由 App 侧
/// `HomeWidgetSync.pushAuthSnapshot` 写入；这里也不依赖 Riverpod 与 UI，
/// 直接复用各 feature 的纯数据源与解析器。
@pragma('vm:entry-point')
Future<void> runHomeWidgetBackground() async {
  debugPrint('[home_widget] 后台入口 homeWidgetBackgroundMain 已启动');
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await refreshWidgetsInBackground();
  } catch (e, s) {
    debugPrint('[home_widget] 后台刷新异常: $e\n$s');
  } finally {
    // 通知原生：本次刷新结束，可以回收引擎 / 结束 JobService。
    await HomeWidgetBridge.notifyBackgroundDone();
    debugPrint('[home_widget] 后台刷新结束，已回报原生');
  }
}

/// 后台刷新主体：电费（免鉴权）+ 成绩（教务会话，失效则用 TGC 静默续期）。
Future<void> refreshWidgetsInBackground() async {
  final store = await HomeWidgetBridge.readStore();
  final auth = _decodeMap(store['auth']);
  final username = (auth['username'] as String?)?.trim() ?? '';
  if (username.isEmpty) {
    debugPrint('[home_widget] 后台刷新跳过：未登录');
    return;
  }

  final roomId = (auth['roomId'] as num?)?.toInt() ?? 0;
  String? balance;
  if (roomId > 0) {
    balance = await _refreshElectricity(username: username, roomId: roomId);
  } else {
    debugPrint('[home_widget] 电费：未绑定宿舍，跳过');
  }

  final grade = await _refreshGrades(auth);

  // 仪表盘最后刷：把刚拿到的电费 / 加权并进多格卡（其余格子沿用上次快照）。
  await _refreshDashboard(
    electricity: balance == null ? null : _shortNumber(balance, 1),
    grade: grade == null ? null : _shortNumber(grade.grade, 2),
  );
}

// ---------- 电费 ----------

/// 返回成功时的余额原文（供仪表盘复用），失败返回 null。
Future<String?> _refreshElectricity({
  required String username,
  required int roomId,
}) async {
  try {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://wxcourse.jxufe.cn',
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
        headers: {
          'User-Agent': const DeviceProfileRepository().userAgent,
          'Referer':
              'https://servicewechat.com/wx70c0beda0bb7b021/143/page-frame.html',
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    final response = await dio.get(
      '/electricity_charges/api/charges/findRoomBalance',
      queryParameters: {'username': username, 'roomId': roomId},
    );
    final data = response.data;
    if (data is! Map) throw Exception('响应异常');
    if ((data['code'] as num?)?.toInt() != 1) {
      throw Exception((data['message'] ?? '查询失败').toString());
    }
    final result = data['result'];
    if (result is! Map) throw Exception('缺少电量数据');

    final balance = (result['balance'] ?? '--').toString();
    final unit = (result['unit'] ?? '').toString();
    final roomNo = (result['roomNo'] ?? '').toString();

    await HomeWidgetBridge.updateSnapshot(
      HomeWidgetSnapshot(
        metric: HomeWidgetMetric.electricity,
        label: HomeWidgetMetric.electricity.defaultLabel,
        value: balance,
        valueShort: double.tryParse(balance)?.toStringAsFixed(1) ?? balance,
        unit: unit,
        sub1: roomNo.isEmpty ? '' : '房间 $roomNo',
        sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
        state: HomeWidgetState.ok,
        message: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        accent: '#F9A825',
      ),
    );
    debugPrint('[home_widget] 后台电费刷新成功: $balance $unit');
    return balance;
  } catch (e) {
    debugPrint('[home_widget] 后台电费刷新失败: $e');
    await _pushErrorUnlessStale(
      HomeWidgetMetric.electricity,
      '电费获取失败',
      '#F9A825',
    );
    return null;
  }
}

// ---------- 成绩 ----------

/// 返回成功时的加权成绩（供仪表盘复用），失败返回 null。
Future<WeightedGrade?> _refreshGrades(Map<String, Object?> auth) async {
  try {
    final grade = await _fetchWeightedGrade(auth);
    await HomeWidgetBridge.updateSnapshot(
      HomeWidgetSnapshot(
        metric: HomeWidgetMetric.grades,
        label: HomeWidgetMetric.grades.defaultLabel,
        value: grade.grade,
        valueShort:
            double.tryParse(grade.grade)?.toStringAsFixed(2) ?? grade.grade,
        unit: '分',
        sub1: grade.majorRank > 0 ? '专业排名 第 ${grade.majorRank} 名' : '未上榜',
        sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
        state: HomeWidgetState.ok,
        message: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        accent: '#2E7D32',
      ),
    );
    debugPrint('[home_widget] 后台成绩刷新成功: ${grade.grade}');
    return grade;
  } catch (e) {
    debugPrint('[home_widget] 后台成绩刷新失败: $e');
    await _pushErrorUnlessStale(HomeWidgetMetric.grades, '成绩获取失败', '#2E7D32');
    return null;
  }
}

// ---------- 仪表盘（数据一览） ----------

/// 把后台能拿到的两格（电费 / 加权）并进仪表盘快照。
///
/// 校园网（余额）/ 志愿时长 / 今日课程依赖 App 侧会话或本地课表缓存（后台 isolate
/// 不碰 Hive），后台不动它们 —— 沿用上一次快照里的值，等 App 前台刷新时更新。
Future<void> _refreshDashboard({String? electricity, String? grade}) async {
  try {
    final store = await HomeWidgetBridge.readStore();
    final previous = HomeWidgetSnapshot.decode(
      store[HomeWidgetMetric.dashboard.key] as String?,
    );
    final prev = <String, String>{
      for (final c in previous?.cells ?? const <HomeWidgetCell>[])
        c.label: c.value,
    };

    final values = <String, String?>{
      '电费': electricity ?? prev['电费'],
      '校园网': prev['校园网'],
      '加权': grade ?? prev['加权'],
      '志愿': prev['志愿'],
      '今日': prev['今日'],
    };
    if (values.values.every((v) => v == null || v.isEmpty)) {
      debugPrint('[home_widget] 仪表盘：无任何可用数据，跳过');
      return;
    }

    final now = DateTime.now();
    await HomeWidgetBridge.updateSnapshot(
      HomeWidgetSnapshot(
        metric: HomeWidgetMetric.dashboard,
        label: HomeWidgetMetric.dashboard.defaultLabel,
        value: '',
        unit: '',
        sub1: '',
        sub2: HomeWidgetSnapshot.updatedLabel(now),
        state: HomeWidgetState.ok,
        message: '',
        updatedAt: now.millisecondsSinceEpoch,
        accent: '#C3282E',
        cells: [
          for (final entry in values.entries)
            HomeWidgetCell(
              label: entry.key,
              value: (entry.value == null || entry.value!.isEmpty)
                  ? '—'
                  : entry.value!,
            ),
        ],
      ),
    );
    debugPrint(
      '[home_widget] 后台仪表盘刷新成功: '
      '${values.entries.map((e) => '${e.key}=${e.value ?? '—'}').join(' ')}',
    );
  } catch (e) {
    debugPrint('[home_widget] 后台仪表盘刷新失败: $e');
  }
}

/// 格子数值统一走短格式（与 App 侧 `HomeWidgetSync._shortValue` 同口径）：
/// 电费一位小数（`120.88` → `120.9`）、加权两位（`91.85965` → `91.86`），
/// 否则窄格子会被省略号截断。
String _shortNumber(String raw, int decimals) =>
    double.tryParse(raw.trim())?.toStringAsFixed(decimals) ?? raw;

/// 取课程加权（typeId=1）；会话失效时用 TGC 静默续期一次再试。
Future<WeightedGrade> _fetchWeightedGrade(Map<String, Object?> auth) async {
  var jsessionId = (auth['jsessionid'] as String?)?.trim() ?? '';
  final tgc = (auth['tgc'] as String?)?.trim() ?? '';
  if (jsessionId.isEmpty && tgc.isEmpty) {
    throw Exception('缺少教务会话，需在 App 内刷新');
  }

  final imsDio = _imsDio();
  final remote = WeightedGradeRemoteDataSource(imsDio);
  final parser = WeightedGradeHtmlParser();

  if (jsessionId.isNotEmpty) {
    try {
      return parser.parseHtml(
        await remote.fetchWeightedGradeHtml(jsessionId: jsessionId, typeId: 1),
      );
    } catch (e) {
      debugPrint('[home_widget] 教务会话失效，尝试静默续期: $e');
    }
  }

  final renewed = await _renewJsessionId(tgc);
  if (renewed == null) {
    throw Exception('教务会话续期失败，需在 App 内打开一次成绩页');
  }
  // 回写新会话，供下次后台刷新直接复用（App 侧也会自行续期，互不冲突）。
  await HomeWidgetBridge.setAuthSnapshot({...auth, 'jsessionid': renewed});

  return parser.parseHtml(
    await remote.fetchWeightedGradeHtml(jsessionId: renewed, typeId: 1),
  );
}

/// TGC → 新 JSESSIONID（纯 HTTP，无需 Hive / 用户在场）。
///
/// 取 CAS 回跳地址这一步是小组件特有的（只有 TGC、没有 App 的
/// `AuthRepository` 自动重登能力）；**换票与激活那两步与 App 内
/// `ImsSession.renew()` 共用同一实现**（`ims_session_renewal.dart`），
/// 免得教务改了口径后两边漂移。
Future<String?> _renewJsessionId(String tgc) async {
  if (tgc.isEmpty) return null;
  try {
    final (redirectUrl, gid) = await AuthRemoteDataSource(
      _casDio(),
    ).getRedirectImsUrl(tgc);
    final fresh = await fetchAndActivateJsessionId(
      imsDio: _imsDio(),
      redirectUrl: redirectUrl,
      gid: gid,
    );
    debugPrint('[home_widget] 教务会话已静默续期');
    return fresh;
  } catch (e) {
    debugPrint('[home_widget] 教务会话续期失败: $e');
    return null;
  }
}

// ---------- 基础设施 ----------

/// 教务侧 Dio（jwxt）：GBK 解码 + 超时，无拦截器（后台自己处理会话失效）。
Dio _imsDio() {
  final ua = const DeviceProfileRepository().userAgent;
  return Dio(
    BaseOptions(
      baseUrl: 'https://jwxt.jxufe.edu.cn',
      followRedirects: false,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
      headers: {
        'User-Agent': ua,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'http://ehall.jxufe.edu.cn/',
      },
      responseDecoder: (bytes, options, response) {
        final contentType = response.headers['Content-Type']?.first ?? '';
        final match = RegExp(
          r'charset=([^;]+)',
        ).firstMatch(contentType.toLowerCase());
        final charset = match?.group(1)?.trim() ?? '';
        return switch (charset) {
          'gbk' || 'gb2312' => gbk.decode(bytes),
          _ => utf8.decode(bytes, allowMalformed: true),
        };
      },
    ),
  );
}

/// CAS 侧 Dio（ssl）：仅用于拿 IMS 重定向 URL。
Dio _casDio() => Dio(
  BaseOptions(
    baseUrl: 'https://ssl.jxufe.edu.cn',
    followRedirects: false,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (_) => true,
    headers: {'User-Agent': const DeviceProfileRepository().userAgent},
  ),
);

/// 读取已有快照：失败时若桌面已有可用数据（state=ok）则保留，
/// 避免一次网络抖动把好数据覆盖成「获取失败」。
Future<void> _pushErrorUnlessStale(
  HomeWidgetMetric metric,
  String message,
  String accent,
) async {
  final store = await HomeWidgetBridge.readStore();
  final existing = HomeWidgetSnapshot.decode(store[metric.key] as String?);
  if (existing != null && existing.state == HomeWidgetState.ok) {
    debugPrint('[home_widget] 保留上次成功的数据（${metric.key}）');
    return;
  }
  await HomeWidgetBridge.updateSnapshot(
    HomeWidgetSnapshot(
      metric: metric,
      label: metric.defaultLabel,
      value: '',
      unit: '',
      sub1: '',
      sub2: HomeWidgetSnapshot.updatedLabel(DateTime.now()),
      state: HomeWidgetState.error,
      message: message,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      accent: accent,
    ),
  );
}

Map<String, Object?> _decodeMap(Object? raw) {
  if (raw is! String || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (e) {
    debugPrint('[home_widget] 认证快照解析失败: $e');
  }
  return const {};
}
