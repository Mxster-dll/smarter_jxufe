/// 学习通 · 签到解析（活动清单 JSON + 单活动详情页 HTML）。
///
/// 实测（2026-10-09，真机）：
/// ```
/// POST https://mobilelearn.chaoxing.com/widget/pcpick/stu/activeList
///      form: courseId / classId / puid
/// → {"result":1,"msg":"获取列表成功",
///    "data":{"startList":[…进行中…],"startCount":0,
///            "endList":[…已结束…],"endCount":6}}
///
/// GET https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/preSign
///     ?activeId=…&classId=…&courseId=…
/// → 200 HTML：`<span class="greenColor">签到成功</span><em id="st">2026-10-08 18:26:25</em>`
/// ```
///
/// ⚠ 三条实测口径（别再猜）：
/// 1. 清单项里的 **`userStatus` 恒为 `null`**（加 `stuid` / `uid` / `studentId` /
///    `showUserStatus` 都不变）→ 我的状态**只能**从详情页拿；
/// 2. 一个活动是签到还是别的（选人 / 抢答 / 投票…）看 **`activeType == 2`**；
/// 3. 详情页里 `activeStatus` 是**活动**的状态（`2` = 已结束），**不是**我的签到状态 ——
///    要挑的是那个带 `Color` 类名的 `<span>` 文案（实测「签到成功」）。
library;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';

/// 清单接口的响应是不是「成功」（`result == 1`）。
bool chaoxingSignListOk(Object? json) {
  if (json is! Map) return false;
  final r = json['result'];
  return r == 1 || r == '1' || r == true;
}

/// 解析 `activeList` 的响应 → 签到活动列表（已结束 + 进行中，按开始时间倒序）。
///
/// 只保留 [chaoxingSignActiveType]（签到）——同一接口也返回选人 / 抢答 / 投票等
/// 别的活动，本模块不关心（混进来会把「签到记录」说成几十条不相关活动）。
/// 容错：非 Map / 缺 `data` / 单条不是 Map / 缺 `id` → 跳过，不抛。
List<ChaoxingSign> parseChaoxingSigns(
  Object? json, {
  required String courseId,
  required String courseName,
}) {
  final data = json is Map ? json['data'] : null;
  final out = <ChaoxingSign>[];
  for (final key in const ['startList', 'endList']) {
    final raw = data is Map ? data[key] : null;
    if (raw is! List) continue;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final sign = chaoxingSignFromItem(
        map,
        courseId: courseId,
        courseName: courseName,
      );
      if (sign == null) continue;
      out.add(sign);
    }
  }
  out.sort((a, b) {
    final da = a.startAt, db = b.startAt;
    if (da == null && db == null) return b.activeId.compareTo(a.activeId);
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return out;
}

/// 单条活动（`activeList` 里的一项）；不是签到或缺 id 时返回 null。
ChaoxingSign? chaoxingSignFromItem(
  Map<String, dynamic> item, {
  required String courseId,
  required String courseName,
}) {
  final type = _int(item['activeType']);
  if (type != chaoxingSignActiveType) return null;
  final id = _str(item['id']);
  if (id.isEmpty) return null;
  return ChaoxingSign(
    activeId: id,
    courseId: courseId,
    classId: _str(item['clazzid']),
    courseName: courseName,
    typeName: _str(item['name']),
    startAt: _date(_str(item['starttimeStr'])) ?? _date(_str(item['createtimeStr'])),
    endAt: _date(_str(item['endtimeStr'])),
    attendCount: _int(item['attendNum']),
    // ⚠ 即使服务端某天开始给 userStatus，也按码值认；给 null 就是「还没查」。
    status: ChaoxingSignStatus.fromCode(item['userStatus']),
    statusLoaded: ChaoxingSignStatus.fromCode(item['userStatus']).isKnown,
  );
}

/// 从详情页 HTML 抠「我的状态 + 签到时刻」，补进 [base]。
///
/// 认不出状态时保持 [ChaoxingSignStatus.unknown]（界面说「状态未知」），
/// **不要**退化成「未签」——那会把「没查到」说成「没签到」。
ChaoxingSign chaoxingSignDetailFromPage(String html, {required ChaoxingSign base}) {
  final text = _statusText(html);
  final status = ChaoxingSignStatus.fromText(text);
  final signedAt = _date(
    RegExp(r'''id="st"[^>]*>\s*([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:]{5,8})''')
            .firstMatch(html)
            ?.group(1) ??
        '',
  );
  // 详情页里的 `var setDate = '…'` 是活动开始时刻（清单缺 `starttimeStr` 时的兜底）。
  final start = base.startAt ??
      _date(
        RegExp(r"""var\s+setDate\s*=\s*'([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:]{5,8})'""")
                .firstMatch(html)
                ?.group(1) ??
            '',
      );
  return base.copyWith(
    status: status,
    signedAt: signedAt,
    startAt: start,
    statusLoaded: status.isKnown,
  );
}

/// 详情页里「我的状态」那句文案（带 `Color` 类名的 span / em）。
///
/// 实测形如 `<span class="greenColor">签到成功</span>`；未签那档的类名与文案未知，
/// 所以这里**按文案字典**匹配，而不是按类名。
String _statusText(String html) {
  for (final re in [
    RegExp(r'''class="[^"]*Color[^"]*"[^>]*>\s*([^<>{}]{2,12})\s*<'''),
    RegExp(r'<span[^>]*>\s*(签到成功|已签到|未签到|缺勤|迟到|早退|请假|病假|事假|代签|签到已过期)\s*</span>'),
  ]) {
    for (final m in re.allMatches(html)) {
      final text = m.group(1)?.trim() ?? '';
      if (ChaoxingSignStatus.fromText(text).isKnown) return text;
    }
  }
  return '';
}

String _str(Object? value) => value == null ? '' : value.toString().trim();

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(_str(value)) ?? 0;
}

DateTime? _date(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t) ?? DateTime.tryParse(t.replaceAll('/', '-'));
}
