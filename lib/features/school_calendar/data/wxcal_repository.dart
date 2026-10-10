/// 小程序校历「合并数据源」仓库。
///
/// 优先实时（设置中填了平台 GUID）：POST getSchoolCalendar 拉当前全部学期；
/// 无 GUID 或实时失败时回退到内置离线快照 [wxcalOfflineTerms]。
library;

import 'package:smarter_jxufe/features/school_calendar/data/datasources/wxcal_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_offline_data.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 把内置离线快照（const 双层模型）转成运行时域模型。
List<WxSemesterArrangement> wxcalOfflineToDomain() => [
      for (final t in wxcalOfflineTerms)
        WxSemesterArrangement(
          id: t.id,
          term: t.term,
          start: DateTime.parse(t.start),
          end: DateTime.parse(t.end),
          style: _styleOf(t.style),
          events: [
            for (final e in t.events)
              WxCalEvent(
                from: DateTime.parse(e.from),
                to: DateTime.parse(e.to ?? e.from),
                text: e.text,
                category: e.category,
              ),
          ],
          notes: t.notes,
        ),
    ];

WxArrangementStyle _styleOf(String s) => switch (s) {
      'lines' => WxArrangementStyle.lines,
      'table' => WxArrangementStyle.table,
      'paragraph' => WxArrangementStyle.paragraph,
      _ => WxArrangementStyle.empty,
    };

/// 校历合并数据源仓库。
class WxcalRepository {
  /// 平台 GUID（用户设置）；为空则仅用离线快照。
  final String? guid;

  /// 平台 appSecret（构建参数注入，见 [bnSecretConfigured]）。
  ///
  /// 为空 = 签名算不出来 → 实时源不可用。2026-10-10 起它不再硬编码在仓库里，
  /// 因此「本地跑起来没有实时校历」是**预期行为**，不是 bug（离线快照照常用）。
  final String? secret;

  final WxcalRemoteDataSource live;

  const WxcalRepository({required this.guid, required this.live, this.secret});

  bool get hasGuid => guid != null && guid!.trim().isNotEmpty;

  /// 实时源是否可用 = **GUID 与 appSecret 都齐**（判据收在 [canUseLiveSource]）。
  ///
  /// 只看 [hasGuid] 是不够的：缺密钥时请求必然被服务端判「签名篡改」，
  /// 白跑一趟网络还多一条错误。**界面也用同一个判据**显示「实时 / 内置」角标。
  bool get hasLive => canUseLiveSource(guid);

  /// 拉取全部学期安排；实时失败自动回退离线（调用方可在 UI 提示源）。
  Future<List<WxSemesterArrangement>> fetchAll() async {
    if (hasLive) {
      try {
        // 密钥显式传下去：仓库手里的这份才是「本构建的 appSecret」。
        return await live.fetchAll(guid: guid!.trim(), secret: secret);
      } catch (_) {
        // 实时失败静默回退内置快照。
      }
    }
    return wxcalOfflineToDomain();
  }

  /// 在结果中找 (xn, xq) 对应的学期（无匹配返回 null，如暑期 xq=2）。
  static WxSemesterArrangement? findByTerm(
    List<WxSemesterArrangement> all, {
    required int xn,
    required int xq,
  }) {
    for (final a in all) {
      if (a.matches(xn: xn, xq: xq)) return a;
    }
    return null;
  }
}
