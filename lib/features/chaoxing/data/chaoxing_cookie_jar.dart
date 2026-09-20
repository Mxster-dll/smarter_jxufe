/// 学习通模块对共享 Cookie 罐的补充 —— **罐本体在 `lib/core/network/cookie_jar.dart`**。
///
/// 2026-09-20 架构审查后：这份按域匹配的 Cookie 罐是全仓唯一做对语义的实现，已提升为
/// [SessionCookieJar]（`lib/core/network/cookie_jar.dart`），供所有「换证 + 会话」站点共用；
/// 本文件只保留学习通自己的**判活口径**（passport 是否就位）。
///
/// 这里 `export` 罐本体，是为了让模块内既有 import 不用改（原先它们就是为了
/// `SessionCookieJar` 才 import 本文件的）。
library;

import 'package:smarter_jxufe/core/network/cookie_jar.dart';

export 'package:smarter_jxufe/core/network/cookie_jar.dart' show SessionCookieJar;

/// [SessionCookieJar.hasPassport] —— 学习通 passport 是否已就位
/// （身份 Cookie 落在能覆盖 `i.chaoxing.com` 的域上）。
///
/// 用它而不是「罐非空」：换证过程中会先出现网关域的几个 Cookie，
/// 那时还没真正登录成功。
///
/// 认 **三个**名字（`UID` / `_uid` / `p_auth_token`）：实测网关桥接那一步会一起下发
/// `UID/_uid/_d/vc3/uf/uname/fid/p_auth_token/xxtenc/cx_p_token/DSSTASH_LOG`，
/// 但只要其中任一个到了业务域就说明票已消费成功。**不认 host-only 的同名 Cookie** ——
/// 网关域（`unified-auth.chaoxing.com`）自己也发过 `UID` 类 Cookie，
/// 那种情况下还没登录（见 `test/chaoxing_data_test.dart` 的网关域那一例）。
extension ChaoxingPassportJar on SessionCookieJar {
  bool get hasPassport =>
      hasAny('i.chaoxing.com', const ['UID', '_uid', 'p_auth_token']);
}
