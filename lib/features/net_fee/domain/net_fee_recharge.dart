/// 校园网充值的**唯一口径**（2026-10-09 立）。
///
/// ## 为什么只有「校方网页支付页」这一条路（真机实测，别再试别的）
///
/// - 小程序「网费充值」（wfcz，appId `1586481872684`）是**微信原生小程序**：
///   `checkAppAuth` 回的 `typeC == '微信原生'`、`pageUrl` 形如
///   `/pages/modules/developer/wfcz/view?…` —— 它的支付走 `wx.requestPayment`，
///   需要该小程序的商户凭据与 openId，**App 侧不可能复刻**。
/// - Dr.COM 自助服务系统的「账户充值 → 在线充值」页（`/service/userRecharge`）
///   里**唯一的一张卡就是「微信充值」**（实测页面 HTML 里 `pick-card` 只有一个），
///   落点同样是 `self.jxufe.cn/WebPay`。
/// - 所以 App 能做的只有一件事：**替用户把账号与金额填好、把校方支付页打开**。
///   支付本身始终发生在校方页面上 —— App 不接触任何支付凭据、不代收、不落单。
///
/// ## 校方支付页的两条形态（同一个 URL，页面自己分流）
///
/// | 页面 | 触发条件 | 提交流程 |
/// |---|---|---|
/// | `WebPay/toRecharge`（PC 版） | 窗口宽 > 768 | 选金额档 → 「立即支付」→ `POST submitRecharge` |
/// | `WebPay/toRechargeM`（移动版） | 宽 ≤ 768，**由 `recharge.js` 自己跳** | 填账号金额 → 「立即充值」→ `POST toRechargeConfirmM`（确认页才选支付方式） |
///
/// 移动版的跳转会把**当前 query 原样带过去**（`queryStr = "?" + arr[1]`），
/// 所以 [netFeeRechargeUrl] 只给一个 PC 口径地址，两端都能吃到账号与金额预填。
library;

import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

/// 校方自助支付页（Dr.COM WebPay）的站点根。
const String kNetFeeWebPayOrigin = 'https://self.jxufe.cn';

/// 校方支付页**唯一开通**的支付方式（实测：URL 传任何 paytype，
/// 页面渲染出来的隐藏域恒为 `3` = 微信；1/2/4 的图标文件在但没被渲染）。
const String kNetFeeWebPayType = '3';

/// 支付页入口路径（**直接开 `toRecharge`，不要开 `recharge`**）。
///
/// ⚠ `/WebPay/recharge` 会 302 到 `toRecharge`，而**重定向会把 `amount` 丢掉**
/// （实测 `final=…/toRecharge;jsessionid=…?paytype=3&account=…`，金额没了），
/// 于是「金额预填」这件事静默失效。直接开 `toRecharge` 才吃 `amount`。
const String kNetFeeWebPayPath = '/WebPay/toRecharge';

/// 快速金额档。
///
/// 前五档与校方 PC 版页面上的按钮一致（10/20/50/100/200）；**12.5 是 App 自己加的**
/// （2026-10-09 · 用户要求）：它是校园网学生套餐的**月费**（`GPON学生12.5元/月`），
/// 充一个月是最常见的用法，校方页面反而没给这个按钮。
///
/// ⚠ 12.5 **不在校方档位里** —— 校方页面对非档位金额走「其他」分支，实测能正确保留
/// （`?amount=12.5` → 页面 `12.50`），原生收银台那条路更是直接把它当数字提交。
/// 移动版多一档 30，App 侧**刻意不跟**：多一档就多一处会过期的抄写。
const List<double> kNetFeeRechargeQuickAmounts = <double>[
  10,
  12.5,
  20,
  50,
  100,
  200,
];

/// 「**充值到目标余额**」模式的常用目标档（元）。
///
/// ⚠ 与 [kNetFeeRechargeQuickAmounts] 是两回事：那是「这次充多少钱」，
/// 这是「我想让余额变成多少」—— 实际充值金额 = 目标 − 当前余额（面板里算）。
const List<double> kNetFeeRechargeTargetAmounts = <double>[20, 50, 100, 200];

/// 校方 `recharge.js` 自己的账号判据（`/^[\w@\.\-\$]{1,30}$/`）。
///
/// 照抄它是为了**少一次白跑**：明显不合法的账号在校方页面同样过不去。
final RegExp _netFeeAccountRe = RegExp(r'^[\w@.\-$]{1,30}$');

/// 金额规整到「分」（校方页面 `change` 里也是 `toFixed(2)`）。
double netFeeNormalizeAmount(double value) =>
    (value * 100).roundToDouble() / 100;

/// 构造校方支付页地址：**账号与金额都预填**。
///
/// 实测：`?account=X&amount=50` 会让页面把金额档选中 50（PC 版 `changeMoney`）
/// 或把金额填进输入框（移动版 `value="50.0"`）；金额不在档位里则落到「其他」。
String netFeeRechargeUrl({required String account, required double amount}) {
  return Uri.parse('$kNetFeeWebPayOrigin$kNetFeeWebPayPath')
      .replace(
        queryParameters: <String, String>{
          'paytype': kNetFeeWebPayType,
          'account': account.trim(),
          'amount': fmtYuan(netFeeNormalizeAmount(amount)),
        },
      )
      .toString();
}

/// 账号校验（`null` = 通过）。空账号与明显非法字符在本地就挡掉。
String? netFeeRechargeAccountError(String raw) {
  final account = raw.trim();
  if (account.isEmpty) return '请填写上网账号';
  if (!_netFeeAccountRe.hasMatch(account)) {
    return r'账号只允许字母、数字与 @ . - _ $ ，且不超过 30 位';
  }
  return null;
}

/// 金额校验（`null` = 通过）。
///
/// ⚠ **刻意不在 App 侧复刻校方的上下限**：校方页面由 `getExtraInfo` 下发
/// （`recharge.js` 里的兜底是 0.01 ~ 500），照抄一份就等于多一处会过期的判断，
/// 而且抄错了会把合法金额挡在门外。这里只挡「明显不是金额」的输入，
/// 真正的上限对话留给校方页面（它会自己提示「金额不能大于 X」）。
String? netFeeRechargeAmountError(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '请选择或输入充值金额';
  final value = double.tryParse(text);
  if (value == null) return '金额只能是数字';
  if (value <= 0) return '金额要大于 0 元';
  return null;
}

/// 网费**充值方式**（校方 `getWfczPayType` 给的那两种，2026-10-09 四轮加）。
///
/// 口径来自智慧江财小程序「网费充值」页（解包读出来的）：
/// `dict_key` 只有 `weixin` 与 `card` 两个，`desc` 分别是「微信支付」「校园卡支付」。
enum NetFeeChargeKind {
  /// 微信支付：走 Dr.COM `self.jxufe.cn` 的二维码 / 唤起微信（本模块已实现的主路径）。
  weixin('weixin', '微信支付'),

  /// 校园卡支付：**直接从校园卡余额扣款**（校方 `…/pay/cardPay`，提交即扣，无密码）。
  campusCard('card', '校园卡支付');

  const NetFeeChargeKind(this.key, this.label);

  /// 校方字典里的 `dict_key`。
  final String key;

  /// 面向用户的短标签。
  final String label;

  static NetFeeChargeKind? fromKey(String key) {
    for (final kind in NetFeeChargeKind.values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// 校方给的「充值方式」条目：`dict_key` + **该方式的充值接口地址**（`dict_value`）。
///
/// ⚠ 地址是**服务端下发的**，别在客户端写死 —— 校方换过就是换过。
class WfczChargeType {
  const WfczChargeType({
    required this.key,
    required this.url,
    required this.desc,
  });

  final String key;
  final String url;
  final String desc;

  NetFeeChargeKind? get kind => NetFeeChargeKind.fromKey(key);

  String get label => desc.isNotEmpty ? desc : (kind?.label ?? key);

  @override
  String toString() => 'WfczChargeType($key)';
}

/// 小程序侧的网费身份：`enc`（加密 userId）+ `openId`（都是**凭据级**）。
class WfczIdentity {
  const WfczIdentity({required this.enc, required this.openId});

  final String enc;
  final String openId;

  /// 诊断用 —— **只报长度，绝不报值**。
  @override
  String toString() => 'WfczIdentity(enc:${enc.length}B, openId:${openId.length}B)';
}

/// 一次充值请求：**去哪个账号充多少钱**。
///
/// 它只是「面板填完的结果」，本身不发任何请求 —— 打开校方支付页由页面负责
/// （见 `presentation/net_fee_recharge_sheet.dart` 的返回值约定）。
class NetFeeRechargeRequest {
  const NetFeeRechargeRequest({
    required this.account,
    required this.amount,
    this.kind = NetFeeChargeKind.weixin,
  });

  /// 上网账号（宽带账号，通常就是学号）。
  final String account;

  /// 充值金额（元，已规整到分）。
  final double amount;

  /// 充值方式（微信 / 校园卡）。
  final NetFeeChargeKind kind;

  /// 校方支付页地址（账号与金额预填）——**只对微信那条路有意义**。
  String get url => netFeeRechargeUrl(account: account, amount: amount);

  /// 诊断用 —— 只报金额与方式，不带账号。
  @override
  String toString() =>
      'NetFeeRechargeRequest(${fmtYuan(amount)} 元 · ${kind.label})';
}

/// 生成一次性的「自动提交」防重 token。
///
/// [now] 只为测试注入；同一微秒内不会开两次支付页。
String newNetFeeRechargeSubmitToken([DateTime? now]) =>
    'r${(now ?? DateTime.now()).microsecondsSinceEpoch}';

/// 校方订单状态：**已支付**（`wxpaySaoma.js` 判的就是这一位）。
///
/// 实测未支付时是 `9`（那张 0.01 元订单放了一小时后仍是 `9`）；
/// 页面脚本只认 `3`，其余一律当「还没付」。
const String kNetFeePayStatePaid = '3';

/// 二维码图片地址（校方**服务端生成的 jpg**，不是我们要自己画的码）。
///
/// 扫码页上的原文是 `<img src="resource/qrcode/<订单号>.jpg">`（相对 `/WebPay/`），
/// 实测直接 GET 就返回 `image/jpeg`（带不带 Referer 都行，约 11.8 KB）。
/// ⇒ App 侧不需要二维码渲染库，把这张图取回来显示即可。
String netFeeQrCodeUrl(String orderNo) =>
    '$kNetFeeWebPayOrigin/WebPay/resource/qrcode/$orderNo.jpg';

/// 一笔**校方待支付订单** —— App 原生收银台的数据形态。
///
/// 它由 `POST submitRecharge` 换来（302 → `/WebPay/wxPaySaoma`，订单号在扫码页的
/// `#orderno` 隐藏域里；**Location 本身不带订单号** —— 订单是挂在 JSESSIONID 会话上的）。
class NetFeeOrder {
  const NetFeeOrder({
    required this.orderNo,
    required this.amount,
    required this.account,
    this.payState = '',
  });

  /// 校方订单号（18 位数字，形如 `20261009000000000123`）。
  final String orderNo;

  /// 充值金额（元）。
  final double amount;

  /// 上网账号。
  final String account;

  /// 校方订单状态（`''` = 还没问过；[kNetFeePayStatePaid] = 已支付）。
  final String payState;

  /// 是否已支付。
  bool get paid => payState == kNetFeePayStatePaid;

  /// 二维码图片地址。
  String get qrCodeUrl => netFeeQrCodeUrl(orderNo);

  NetFeeOrder copyWith({String? payState}) => NetFeeOrder(
    orderNo: orderNo,
    amount: amount,
    account: account,
    payState: payState ?? this.payState,
  );

  /// 诊断用 —— 只报订单号与金额（订单号不是凭据，但要能对上账）。
  @override
  String toString() =>
      'NetFeeOrder($orderNo, ${fmtYuan(amount)} 元, payState=$payState)';
}

/// **页面加载后脚本**：把校方那一页收拾成「选完金额就直接出二维码」。
///
/// 校方流程实测（2026-10-09 · Edge + CDP 真机走了一遍，**0.01 元订单、未付款**）：
///
/// ```
/// POST submitRecharge  →  /WebPay/wxPaySaoma（扫码支付页，3 秒内到达）
///   页面上是：订单号 + <img src="resource/qrcode/<订单号>.jpg"> + 「支付完成 / 返回」
///   该页 JS（`wxpaySaoma.js`）每 3 秒 GET checkOrder?orderno=…，
///   `order.paystate == "3"` 时自动 window.location = payResult / payReturn?orderno=…
/// ```
///
/// 所以「二维码」本来就存在，只差**替用户点掉表单上那一次「立即支付」**。
/// 本脚本做两件事（顺序不能反）：
///
/// ### ① 修金额：校方 `recharge.js` 的 `initAmount` 分支把 `flag` 写反了
///
/// ```js
/// $(".moneyBut").each(function () {
///   if (parseFloat(this.value) == initAmount) { changeMoney(this.id); flag = false; return false; }
/// });
/// if (flag && !$("#tr_manualMoney").is(":hidden")) { /* 填进「其他」 */ }
/// else { $("#moneybut1").click(); }   // ← 匹配到档位时 flag 已是 false，也落到这里 → 金额变 10
/// ```
///
/// 渲染后 DOM 对照（headless，只读）：URL 传 `50` / `100`（校方档位值）→ 页面最终是 **`10`**；
/// 传 `30`（非档位值）→ 正确保留 `30`。**URL 预填档位金额在 PC 版上静默失效**，
/// 而档位恰恰是用户最常选的那几个 —— 用户以为充 50、页面其实停在 10 元。
/// 唯一修法是替它调一次校方自己的 `changeMoney`。
///
/// ### ② 自动提交：直接落到 `wxPaySaoma` 二维码页
///
/// 带一次性 token 防重 —— 脚本每次导航结束都会跑，用户点内嵌页的「上一页」回到表单时
/// **不该再下一单**，所以用 `sessionStorage['dshSubmit:<token>']` 记账；
/// token 由 App 每次「去支付」现生成，于是「关掉二维码页、重新点充值」仍会正常下单。
///
/// ### 无害保证
///
/// `changeMoney` 不存在（移动版 / 结果页）或页面里没有 `form` + `input[type=submit]`
/// （扫码页 / 成功页）时直接 `return`，什么都不做；失败一律吞掉，绝不影响页面本身。
/// ⚠ 走**系统浏览器**兜底时注入不了脚本：那条路上用户要自己在页面上点一次「立即支付」，
/// 所以面板里那句「请核对一眼再付款」必须留着。
String netFeeRechargePageScript({
  required double amount,
  required String submitToken,
}) {
  final value = fmtYuan(netFeeNormalizeAmount(amount));
  return '(function(){try{'
      // ① 修金额：校方 `initAmount` 分支把 flag 写反，档位金额会被打回 10 元。
      'var v=$value;'
      "if(typeof changeMoney!=='function')return;"
      "var bs=document.querySelectorAll('.moneyBut'),id=null;"
      'for(var i=0;i<bs.length;i++){if(parseFloat(bs[i].value)===v){id=bs[i].id;break;}}'
      'if(id)changeMoney(id);'
      // ② 自动提交：直接落到 `wxPaySaoma` 二维码页。
      "var fm=document.querySelector('form');"
      'var sb=fm?fm.querySelector("input[type=submit]"):null;'
      'if(!fm||!sb)return;'
      "var key='dshSubmit:$submitToken';"
      "try{if(sessionStorage.getItem(key))return;"
      "sessionStorage.setItem(key,'1');}catch(e){}"
      'sb.click();'
      '}catch(e){}})();';
}

