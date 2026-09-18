/// 网络服务（智慧江财「生活 > 网络服务」= 广州热点 Dr.COM「用户自助服务系统」）领域模型。
///
/// 数据来源见 `reverse_engineering/网络服务接口.md`。所有 `fromJson` 一律**容错**：
/// 服务端是 Java 老系统，字段缺失 / 类型漂移 / 值为 null 都要能扛住（旧数据不崩）。
///
/// 时间口径：JSON 里的时间有四种形态 —— 毫秒数（`loginTime`）、`yyyy-MM-dd HH:mm:ss`
/// 字符串（`getOnlineList.loginTime`）、纯数字「分钟/秒」（`useTime`）、
/// 以及账单行的毫秒数组；解析统一走 [networkMillis] / [networkDateTime] / [networkNum]。
library;

/// 网络服务账号概览（首页 `/dashboard` 内嵌 `window.user`）。
class NetworkAccount {
  const NetworkAccount({
    required this.userName,
    required this.realName,
    required this.leftMoney,
    required this.useFlow,
    required this.useTime,
    required this.leftFlow,
    required this.leftTime,
    required this.planName,
    required this.planArea,
    required this.planGroupName,
    required this.planGroupDesc,
    required this.payStyle,
    required this.active,
    required this.startAt,
    required this.expireAt,
    required this.macs,
    required this.ipCount,
    required this.ipMaxCount,
    required this.password,
    required this.idNumber,
    required this.internalUserId,
    required this.multiLogin,
  });

  /// 上网账号（= 学号，如 `2000000000`）。
  final String userName;

  /// 实名（如「某同学」）。
  final String realName;

  /// 账户余额（元）。
  final double leftMoney;

  /// 当前计费周期已用流量（MB）。
  final double useFlow;

  /// 当前计费周期已用时长（分钟）。
  final int useTime;

  /// 剩余流量（MB）/ 剩余时长（分钟）—— 包月套餐恒为 0。
  final double leftFlow;
  final int leftTime;

  /// 当前套餐名（`serviceDefault.defaultName`，如「GPON学生12.5元/月」）。
  final String planName;

  /// 套餐适用区域说明（`serviceDefault.extend`）。
  final String planArea;

  /// 套餐分组名 / 描述（`userGroup.userGroupName` / `userGroupDescription`）。
  final String planGroupName;
  final String planGroupDesc;

  /// 套餐计费方式（`userGroup.payStyle`：1 时长 / 2 流量 / 3 包月）。
  final int payStyle;

  /// 账号是否正常（`useFlag == 1`；0 = 停机）。
  final bool active;

  final DateTime? startAt;

  /// 账号失效日期（`stopDate`）。
  final DateTime? expireAt;

  /// 已绑定设备 MAC（分号分隔）。
  final List<String> macs;

  /// 已用 IP 数 / 允许的最大在线数。
  final int ipCount;
  final int ipMaxCount;

  /// 上网密码（明文，服务端原样下发；App 侧一律掩码显示）。
  final String password;

  /// 证件号码（身份证）。
  final String idNumber;

  /// Dr.COM 内部用户 id（非学号）。
  final String internalUserId;

  /// 是否允许多终端在线。
  final bool multiLogin;

  static const NetworkAccount empty = NetworkAccount(
    userName: '',
    realName: '',
    leftMoney: 0,
    useFlow: 0,
    useTime: 0,
    leftFlow: 0,
    leftTime: 0,
    planName: '',
    planArea: '',
    planGroupName: '',
    planGroupDesc: '',
    payStyle: 0,
    active: true,
    startAt: null,
    expireAt: null,
    macs: [],
    ipCount: 0,
    ipMaxCount: 0,
    password: '',
    idNumber: '',
    internalUserId: '',
    multiLogin: false,
  );

  /// 账号状态文案（服务页口径：`正常` / `停机`）。
  String get statusLabel => active ? '正常' : '停机';

  /// 计费方式文案（服务页「套餐计费方式」）。
  String get payStyleLabel => switch (payStyle) {
    1 => '时长',
    2 => '流量',
    3 => '包月',
    _ => '—',
  };

  /// 从 `/dashboard` 内嵌的 `window.user` 对象构造。
  factory NetworkAccount.fromUserJson(Map<String, dynamic> json) {
    final group = networkMap(json['userGroup']);
    final plan = networkMap(json['serviceDefault']);
    final macs = (json['macAddress']?.toString() ?? '')
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return NetworkAccount(
      userName: networkStr(json['userName']),
      realName: networkStr(json['userRealName']),
      leftMoney: networkNum(json['leftMoney']),
      useFlow: networkNum(json['useFlow']),
      useTime: networkNum(json['useTime']).round(),
      leftFlow: networkNum(json['leftFlow']),
      leftTime: networkNum(json['leftTime']).round(),
      planName: networkStr(plan['defaultName']),
      planArea: networkStr(plan['extend']),
      planGroupName: networkStr(group['userGroupName']),
      planGroupDesc: networkStr(group['userGroupDescription']),
      // ⚠ 顶层 payStyle（0）不是套餐计费方式，套餐计费方式在 userGroup.payStyle。
      payStyle: networkNum(group['payStyle']).round(),
      active: networkNum(json['useFlag']).round() == 1,
      startAt: networkMillis(json['startDate']),
      expireAt: networkMillis(json['stopDate']),
      macs: macs,
      ipCount: networkNum(json['ipCount']).round(),
      ipMaxCount: networkNum(group['ipMaxCount']).round(),
      password: networkStr(json['userPassword']),
      idNumber: networkStr(json['userIdNumber']),
      internalUserId: networkStr(json['userId']),
      multiLogin: networkNum(json['multiLogin']).round() == 1,
    );
  }
}

/// 在线会话（`dashboard/getOnlineList`），可强制下线。
class NetworkOnlineSession {
  const NetworkOnlineSession({
    required this.sessionId,
    required this.ip,
    required this.mac,
    required this.loginAt,
    required this.loginAtText,
    required this.useSeconds,
    required this.upFlow,
    required this.downFlow,
    required this.terminalType,
  });

  final String sessionId;
  final String ip;
  final String mac;

  /// 上线时间（服务端已给 `yyyy-MM-dd HH:mm:ss` 文本，原样保留展示；解析失败为 null）。
  final DateTime? loginAt;
  final String loginAtText;

  /// 已用时长（秒）。
  final int useSeconds;

  /// 上行 / 下行流量（字节，服务端以字符串给）。
  final int upFlow;
  final int downFlow;

  /// 终端类型（`#PC` / `#移动终端`，`#` 是服务端前缀，展示时去掉）。
  final String terminalType;

  /// 展示用终端名（去掉服务端 `#` 前缀）。
  String get terminalLabel =>
      terminalType.startsWith('#') ? terminalType.substring(1) : terminalType;

  factory NetworkOnlineSession.fromJson(Map<String, dynamic> json) {
    final text = networkStr(json['loginTime']);
    return NetworkOnlineSession(
      sessionId: networkStr(json['sessionId']),
      ip: networkStr(json['ip']),
      mac: networkStr(json['mac']),
      loginAt: networkParseDateTime(text),
      loginAtText: text,
      useSeconds: networkNum(json['useTime']).round(),
      upFlow: networkNum(json['upFlow']).round(),
      downFlow: networkNum(json['downFlow']).round(),
      terminalType: networkStr(json['terminalType']),
    );
  }
}

/// 近期上网记录（`dashboard/getLoginHistory`，数组行）。
class NetworkLoginRecord {
  const NetworkLoginRecord({
    required this.loginAt,
    required this.logoutAt,
    required this.ip,
    required this.mac,
    required this.minutes,
    required this.flowMb,
    required this.payStyle,
    required this.costMoney,
    required this.hostName,
    required this.terminalType,
  });

  final DateTime? loginAt;
  final DateTime? logoutAt;
  final String ip;
  final String mac;

  /// 使用时长（分钟）。
  final int minutes;

  /// 使用流量（MB）。
  final double flowMb;

  /// 计费方式（1 时长 / 2 流量 / 3 包月）。
  final int payStyle;

  /// 计费金额（元）。
  final double costMoney;

  final String hostName;
  final String terminalType;

  String get payStyleLabel => networkPayStyleLabel(payStyle);

  String get terminalLabel =>
      terminalType.startsWith('#') ? terminalType.substring(1) : terminalType;

  /// 行格式：`[上线时间ms, 注销时间ms, IP, MAC, 时长(分), 流量(MB), 计费方式, 计费金额,
  /// 主机名, 终端类型, …]`（列定义见 dashboard 表的 field 0..9）。
  factory NetworkLoginRecord.fromRow(List<dynamic> row) {
    dynamic at(int i) => i < row.length ? row[i] : null;
    return NetworkLoginRecord(
      loginAt: networkMillis(at(0)),
      logoutAt: networkMillis(at(1)),
      ip: networkStr(at(2)),
      mac: networkStr(at(3)),
      minutes: networkNum(at(4)).round(),
      flowMb: networkNum(at(5)),
      payStyle: networkNum(at(6)).round(),
      costMoney: networkNum(at(7)),
      hostName: networkStr(at(8)),
      terminalType: networkStr(at(9)),
    );
  }

  /// 是否仍在线上（服务端未给注销时间 = 本次会话还在进行）。
  bool get online => logoutAt == null;
}

/// 上网记录明细（`bill/getUserOnlineLog` rows，需日期范围）。
class NetworkUsageRecord {
  const NetworkUsageRecord({
    required this.loginAt,
    required this.logoutAt,
    required this.minutes,
    required this.flowMb,
    required this.costMoney,
    required this.internetUpFlow,
    required this.internetDownFlow,
    required this.chinanetUpFlow,
    required this.chinanetDownFlow,
    required this.userIp,
    required this.mac,
    required this.nasIp,
    required this.nasPort,
    required this.realName,
  });

  final DateTime? loginAt;
  final DateTime? logoutAt;

  /// 使用时长（分钟）。
  final int minutes;

  /// 使用流量（MB）。
  final double flowMb;

  /// 计费金额（元）。
  final double costMoney;

  /// 国际上行 / 下行、国内上行 / 下行（MB）。
  final double internetUpFlow;
  final double internetDownFlow;
  final double chinanetUpFlow;
  final double chinanetDownFlow;

  final String userIp;
  final String mac;
  final String nasIp;
  final int nasPort;
  final String realName;

  factory NetworkUsageRecord.fromJson(Map<String, dynamic> json) {
    return NetworkUsageRecord(
      loginAt: networkMillis(json['loginTime']),
      logoutAt: networkMillis(json['logoutTime']),
      minutes: networkNum(json['time']).round(),
      flowMb: networkNum(json['flow']),
      costMoney: networkNum(json['costMoney']),
      internetUpFlow: networkNum(json['internetUpFlow']),
      internetDownFlow: networkNum(json['internetDownFlow']),
      chinanetUpFlow: networkNum(json['chinanetUpFlow']),
      chinanetDownFlow: networkNum(json['chinanetDownFlow']),
      userIp: networkStr(json['userIp']),
      mac: networkStr(json['macAddress']),
      nasIp: networkStr(json['nasIp']),
      nasPort: networkNum(json['nasPort']).round(),
      realName: networkStr(json['userRealName']),
    );
  }
}

/// 历史账单（`bill/getMonthPay?year=`）：明细 + 年度汇总。
class NetworkMonthBills {
  const NetworkMonthBills({
    required this.year,
    required this.items,
    required this.summary,
  });

  final int year;
  final List<NetworkMonthBill> items;
  final NetworkMonthBillSummary summary;
}

/// 一条账单（`rows` 数组：`[开始ms, 结束ms, 套餐, 基本月租, 时长/流量计费, 时长, 流量, 出账ms]`）。
class NetworkMonthBill {
  const NetworkMonthBill({
    required this.startAt,
    required this.endAt,
    required this.planName,
    required this.baseMoney,
    required this.usageMoney,
    required this.minutes,
    required this.flowMb,
    required this.billedAt,
  });

  final DateTime? startAt;
  final DateTime? endAt;
  final String planName;

  /// 基本月租（元）。
  final double baseMoney;

  /// 时长 / 流量计费（元）。
  final double usageMoney;

  final int minutes;
  final double flowMb;
  final DateTime? billedAt;

  /// 合计（元）。
  double get total => baseMoney + usageMoney;

  /// 账期**含末日**：服务端 rows 的结束时间是「下期开始」的开区间端点
  /// （上一期的结束 == 下一期的开始），学校页面显示的结束日 = 该时刻的前一天。
  DateTime? get endDay => endAt?.subtract(const Duration(days: 1));

  factory NetworkMonthBill.fromRow(List<dynamic> row) {
    dynamic at(int i) => i < row.length ? row[i] : null;
    return NetworkMonthBill(
      startAt: networkMillis(at(0)),
      endAt: networkMillis(at(1)),
      planName: networkStr(at(2)),
      baseMoney: networkNum(at(3)),
      usageMoney: networkNum(at(4)),
      minutes: networkNum(at(5)).round(),
      flowMb: networkNum(at(6)),
      billedAt: networkMillis(at(7)),
    );
  }
}

/// 年度汇总（`summary`：USETIME / USEBASEMONEY / USEFLOW / USEDMONEY）。
class NetworkMonthBillSummary {
  const NetworkMonthBillSummary({
    required this.minutes,
    required this.baseMoney,
    required this.flowMb,
    required this.usageMoney,
  });

  final int minutes;
  final double baseMoney;
  final double flowMb;
  final double usageMoney;

  double get total => baseMoney + usageMoney;

  static const NetworkMonthBillSummary empty = NetworkMonthBillSummary(
    minutes: 0,
    baseMoney: 0,
    flowMb: 0,
    usageMoney: 0,
  );

  factory NetworkMonthBillSummary.fromJson(Map<String, dynamic> json) =>
      NetworkMonthBillSummary(
        minutes: networkNum(json['USETIME']).round(),
        baseMoney: networkNum(json['USEBASEMONEY']),
        flowMb: networkNum(json['USEFLOW']),
        usageMoney: networkNum(json['USEDMONEY']),
      );
}

/// 充值明细（`bill/getPayMent`）/ 在线充值记录（`service/onlinePayLog`）。
///
/// 两处列定义不同，字段名按「列序」对齐 —— 见 [NetworkPayment.fromRow]
/// （充值明细：0 交费时间, 1 交费类型, 2 金额, 3 受理终端, 4 备注）。
class NetworkPayment {
  const NetworkPayment({
    required this.paidAtText,
    required this.paidAt,
    required this.kind,
    required this.amount,
    required this.terminal,
    required this.memo,
    required this.balanceBefore,
  });

  final String paidAtText;
  final DateTime? paidAt;
  final String kind;
  final double amount;
  final String terminal;
  final String memo;

  /// 充值前剩余（仅在线充值记录有）。
  final double? balanceBefore;

  factory NetworkPayment.fromRow(List<dynamic> row) {
    dynamic at(int i) => i < row.length ? row[i] : null;
    final text = networkStr(at(0));
    return NetworkPayment(
      paidAtText: text,
      paidAt: networkParseDateTime(text),
      kind: networkStr(at(1)),
      amount: networkNum(at(2)),
      terminal: networkStr(at(3)),
      memo: networkStr(at(4)),
      balanceBefore: null,
    );
  }
}

/// 业务办理记录（`bill/getOperatorLog`：0 办理时间, 1 业务描述, 2 受理终端, 4 备注）。
class NetworkOperatorLog {
  const NetworkOperatorLog({
    required this.operatedAtText,
    required this.operatedAt,
    required this.description,
    required this.terminal,
    required this.memo,
  });

  final String operatedAtText;
  final DateTime? operatedAt;
  final String description;
  final String terminal;
  final String memo;

  factory NetworkOperatorLog.fromRow(List<dynamic> row) {
    dynamic at(int i) => i < row.length ? row[i] : null;
    final text = networkStr(at(0));
    return NetworkOperatorLog(
      operatedAtText: text,
      operatedAt: networkParseDateTime(text),
      description: networkStr(at(1)),
      terminal: networkStr(at(2)),
      memo: networkStr(at(4)),
    );
  }
}

/// 报停 / 复通记录（`service/getStopLog` / `service/goReopenLog`）。
class NetworkOperationLog {
  const NetworkOperationLog({
    required this.operatedAt,
    required this.adminId,
    required this.memo,
    required this.newValue,
    required this.oldValue,
    required this.subjectId,
  });

  final DateTime? operatedAt;
  final String adminId;
  final String memo;

  /// 复通记录专有：预约日期 / 变更后值；报停记录恒为空串。
  final String newValue;
  final String oldValue;
  final String subjectId;

  factory NetworkOperationLog.fromJson(Map<String, dynamic> json) =>
      NetworkOperationLog(
        operatedAt: networkMillis(json['fldoperatedate']),
        adminId: networkStr(json['fldadminid']),
        memo: networkStr(json['fldmemo']),
        newValue: networkStr(json['fldnewvalue']),
        oldValue: networkStr(json['fldoldvalue']),
        subjectId: networkStr(json['fldoperateobject']),
      );

  /// 记录描述（复通记录里 `fldoperateid` 是业务码，服务端旧/新值含原因）。
  String get description {
    if (oldValue.isEmpty && newValue.isEmpty) return memo;
    final reason = oldValue.contains('/') ? oldValue.split('/').last : oldValue;
    if (reason.contains('余额不足')) return '余额不足停机后复通';
    if (newValue.isNotEmpty && newValue != oldValue) {
      return '状态变更 $oldValue → $newValue';
    }
    return memo.isEmpty ? '业务办理' : memo;
  }
}

/// 预约套餐日志（`service/packageLog`）。
class NetworkPackageLog {
  const NetworkPackageLog({
    required this.changedAt,
    required this.effectiveAt,
    required this.fromPlan,
    required this.toPlan,
    required this.state,
    required this.memo,
  });

  final DateTime? changedAt;
  final DateTime? effectiveAt;
  final String fromPlan;
  final String toPlan;
  final String state;
  final String memo;

  factory NetworkPackageLog.fromJson(Map<String, dynamic> json) =>
      NetworkPackageLog(
        changedAt: networkMillis(json['fldchangedate']),
        effectiveAt: networkMillis(json['fldexcutedate']),
        fromPlan: networkStr(json['flddefaultname1']),
        toPlan: networkStr(json['flddefaultname2']),
        state: networkStr(json['fldstate']),
        memo: networkStr(json['fldextend']),
      );
}

/// 已绑定设备（`service/getMacList`：行 = `[在线状态, MAC, 终端信息, 最近登录时间, 最近登录IP]`）。
class NetworkDevice {
  const NetworkDevice({
    required this.mac,
    required this.online,
    required this.terminalType,
    required this.lastLoginText,
    required this.lastLoginIp,
  });

  final String mac;
  final bool online;
  final String terminalType;
  final String lastLoginText;
  final String lastLoginIp;

  String get terminalLabel =>
      terminalType.startsWith('#') ? terminalType.substring(1) : terminalType;

  factory NetworkDevice.fromRow(List<dynamic> row) {
    dynamic at(int i) => i < row.length ? row[i] : null;
    return NetworkDevice(
      online: networkStr(at(0)) == '1',
      mac: networkStr(at(1)),
      terminalType: networkStr(at(2)),
      lastLoginText: networkStr(at(3)),
      lastLoginIp: networkStr(at(4)),
    );
  }
}

/// 资费 / 套餐（`service/getUserGroups` 资费介绍；`service/package` 可选套餐卡片）。
class NetworkPlan {
  const NetworkPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.selectable,
  });

  /// 资费 id（= 预约套餐接口的 `serid`）。
  final String id;
  final String name;
  final String description;

  /// 是否为「预约套餐」页可选中的套餐（资费介绍列表里可能有不可选条目）。
  final bool selectable;

  factory NetworkPlan.fromJson(Map<String, dynamic> json) => NetworkPlan(
    id: networkStr(json['id']),
    name: networkStr(json['defaultName']),
    description: networkStr(json['extend']),
    selectable: true,
  );
}

/// 写操作结果（服务端统一回 `{state, message}`；`state == 'success'` 为成功）。
class NetworkActionResult {
  const NetworkActionResult({required this.success, required this.message});

  final bool success;
  final String message;

  factory NetworkActionResult.fromJson(Map<String, dynamic> json) {
    final state = networkStr(json['state']).toLowerCase();
    final data = networkStr(json['data']);
    final message = networkStr(json['message']);
    return NetworkActionResult(
      success:
          state == 'success' || json['success'] == true || json['code'] == 1,
      message: message.isNotEmpty ? message : data,
    );
  }

  static const NetworkActionResult ok = NetworkActionResult(
    success: true,
    message: '',
  );
}

/// 预约套餐页（`service/package`）解析结果：可选套餐 + 下单所需 csrftoken。
class NetworkPackageOptions {
  const NetworkPackageOptions({required this.options, required this.csrfToken});

  final List<NetworkPlan> options;

  /// 页面上隐藏域 `csrftoken`（`doPackage` / `undoPackage` 需要）。
  final String csrfToken;

  static const NetworkPackageOptions empty = NetworkPackageOptions(
    options: [],
    csrfToken: '',
  );
}

/// 上网记录查询窗口（`bill/getUserOnlineLog` 必须带日期范围）。
///
/// 带 `==` / `hashCode`：作为 Riverpod `family` 的参数需要值相等语义，
/// 否则每次 build 都会当成新参数重新请求。
class NetworkUsageQuery {
  const NetworkUsageQuery({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  static NetworkUsageQuery yearOf(int year) =>
      NetworkUsageQuery(from: DateTime(year, 1, 1), to: DateTime(year, 12, 31));
  static NetworkUsageQuery recentYear(DateTime now) => NetworkUsageQuery(
    from: DateTime(now.year - 1, now.month, now.day),
    to: now,
  );

  @override
  bool operator ==(Object other) =>
      other is NetworkUsageQuery && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'NetworkUsageQuery($from ~ $to)';
}

/// 计费方式文案（1 时长 / 2 流量 / 3 包月）。
String networkPayStyleLabel(int payStyle) => switch (payStyle) {
  1 => '时长',
  2 => '流量',
  3 => '包月',
  _ => '—',
};

// ---------- 容错解析工具（全模块共用，测试直接覆盖） ----------

/// 任意值 → `Map<String, dynamic>`（非 Map 一律空 Map）。
Map<String, dynamic> networkMap(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, dynamic>{};
}

/// 任意值 → List（非 List 一律空 List）。
List<dynamic> networkList(dynamic value) =>
    value is List ? value : const <dynamic>[];

/// 任意值 → 字符串（null → 空串；其它走 toString）。
String networkStr(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// 任意值 → double（字符串 / 数字都认；`null` / 空串 / 非数字 → [fallback]）。
double networkNum(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    return double.tryParse(trimmed) ?? fallback;
  }
  return fallback;
}

/// 毫秒时间戳 → DateTime（本地时区）；`null` / 0 / 非法 → null。
DateTime? networkMillis(dynamic value) {
  final ms = networkNum(value, fallback: -1);
  if (ms <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms.round());
}

/// `yyyy-MM-dd HH:mm:ss` / `yyyy-MM-dd` 文本 → DateTime；解析失败 null。
DateTime? networkParseDateTime(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.replaceFirst(' ', 'T');
  final parsed = DateTime.tryParse(normalized);
  if (parsed != null) return parsed;
  return DateTime.tryParse(trimmed);
}
