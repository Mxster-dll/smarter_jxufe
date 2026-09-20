<!-- 本册 = AGENTS.md §12 的正文（节号与标题原样保留，勿重编号）。根文件：../../AGENTS.md -->

## 12. IMS 全局会话口径（成绩 / 课表 / 毕业学分 / 培养方案 / 我的 共用 · 2026-09-11 立）



**用户诉求（原话）**：「成绩/课表/毕业学分/培养方案/我的 界面都不要强制重新登录 ims，而是同样用全局一个维护的 ims 实例……全局仅实现一个 ims 实例（当然，切换账号要销毁重建这个对象）……重启应用/小组件访问时也不能销毁这个对象，要持久化」。



**唯一实例 = `lib/features/ims/auth/data/ims_session.dart` 的 `ImsSession`**，由 `lib/features/ims/auth/data/providers/ims_session_provider.dart` 的 `imsSessionProvider`（手写 `Provider`，**同步**——十几个数据源要同步 `ref.watch(currentImsDioProvider)` 取 Dio）持有。



- **一个 Dio**：`createImsDio()`（`lib/core/network/ims_dio.dart`）**成对创建 Dio + `ImsAuthInterceptor`**，`currentImsDioProvider` 只取它的 `.dio` → 所有教务数据源共用一份会话与一个重试拦截器。**禁止**再引入「全局单例拦截器 + `setDio`」：多账户并存时后建的 Dio 会覆盖重试目标（历史 bug）。

- **零请求进入（本次改造核心）**：`ImsSplashScreen._enter()` 调 `session.ensureReady()` —— 本地有会话就**一个请求都不发**直接进页面；真失效由拦截器在业务请求上发现 → `session.renew()`（`_inflight` **并发去重**，多个请求同时踩失效只换一次票）→ 用新票重试原请求。**不要把 splash 改回无条件 `refreshJsessionId()`**：那正是用户反馈的「每次进任一 IMS 功能都强制重新登录」；旧代码还没有 try/catch，CAS 一失败就永远停在「加载中…」。换票失败时给「重试 / 先看本地缓存」，不困住用户。

- **续期唯一实现**：`lib/features/ims/auth/data/ims_session_renewal.dart` 的 `fetchAndActivateJsessionId({imsDio, redirectUrl, gid})` = 取票（`/jxcjcaslogin` 的 `Set-Cookie`）+ **用新票访问 CAS 回跳地址激活**（少了第二步教务仍视为未登录）。App 侧 `ImsSession.renew()` 与桌面小组件 `home_widget_background.dart` **共用**它，别再写第二份；App 侧多一层 `AuthRepository.getImsRedirectInfo()`（TGC 过期会用缓存凭据静默重登），小组件侧只有 TGC。

- **持久化按账号**：`imsAuth` box 键 = `JSESSIONID|<账号>`（另有 `…|at` 记落盘时间），实现 `lib/features/ims/auth/data/datasource/ims_auth_local_datasource.dart`。历史版本是无账号单键 `JSESSIONID`（切号必串号），`migrateLegacy()` 把它**只**认领给第一个读到的账号。**`release()`（provider dispose / 切号）只清内存、绝不动磁盘** —— 这是「重启应用 / 小组件访问也不丢会话」的关键；只有 `forget()`（退出登录）才删磁盘。

- **切号 = 会话销毁重建**：`imsSessionProvider` watch `currentAccountProvider`，账号一变整个实例（Dio / 拦截器 / 内存会话）重建。`lib/features/ims/student_info/presentation/account_screen.dart` 的切号流程**不要**再调 `imsAuthRepo.logout()`（会删掉刚登录账号的会话）或 `studentInfoRepo.clearCache()`（已按账号隔离，清了白清）；且必须在**设置账号之后**重新 `ref.read(studentInfoRepositoryProvider.future)`（切号前拿到的仓库绑的是旧账号的 box）。

- **个人数据按账号隔离**：`lib/core/storage/account_scoped_box.dart` 的 `openAccountScopedBox(base, account)` → box 名 `<base>_<账号>`，账号未确定用 `<base>__none`（**故意不回落到旧无账号 box**，避免未登录就露出上一个账号的数据）；旧 box 被第一个账号迁移认领一次（`claimedKey = '__migratedTo'`）。已接入：`gradesCache`（成绩）、`studentInfo`（学籍）、`scheduleReschedules`（调课，经 `RescheduleRepository({account})` + `RescheduleStore.bindAccount` 清内存缓存）、`score_estimate`（分数估计）、`zongce`（综测）。**公共数据不隔离**：`curriculums`（按年/学院/专业）、`colleges`/`majors`、`periodTable`、`scheduleCache`（key 里已含 `studentId`）。新增个人数据 box 一律走 `openAccountScopedBox`。

- **门面**：`ImsAuthRepository` 只剩 `Either` 适配（`getJsessionId({forceRefresh})` / `refreshJsessionId()` / `logout()`），**不再持有任何状态**；成绩 / 学籍 / 培养方案 / 毕业学分 / 加权五个仓库都经它取票，`getJsessionId()` 本来就是「有缓存即返回、不发网络」。

- **守卫测试**：`test/ims_session_test.dart`（13 例：零网络 / 换票两步与落盘 / 并发去重 / 失败可重试 / release 不动磁盘 / forget 才清盘 / 切号不借用他人会话 / 会话键账号隔离与旧键只认领一次 / box 隔离与迁移）。改会话口径先动它。



### 12.1 统一登录（CAS）按账号持久化口径（2026-09-11 立）



**用户诉求（原话）**：「统一登录也要像上面说的一样，持久化，相当于对于每个账号，统一登录和 ims 都只有一个入口」；并拍板：「TGC 有效就直接用，免密码免 MFA；TGC 失效才用保存的密码静默重登」。



- **按账号落盘**（`lib/features/auth/data/datasources/auth_local_datasource.dart`）：`auth` box 键 = `TGC|<账号>` / `CACHEDUSER|<账号>` / `CACHEDPASS|<账号>`；API 一律带账号 —— `saveTgc(account, tgc)` / `getTgc(account)` / `deleteTgc(account)` / `saveCachedCredentials(account, password)` / `getCachedCredentials(account)`。历史无账号单键 `tgc` / `cachedUser` / `cachedPass` 由 `claimLegacyCredentials(account)` **认领给 `cachedUser` 记着的那个账号**（不匹配就不动旧键、认领后删旧键、旧 `cachedUser` 为空则不认领）——归属靠旧 `cachedUser` 精确判定，不会张冠李戴。**真机实测**：老用户升级后 `auth.hive` 里出现 `TGC|2000000002` / `CACHEDUSER|2000000002` / `CACHEDPASS|2000000002` ✓。

- **两个 provider（`lib/features/auth/data/providers/`）**：

  - `authRepositoryForAccountProvider`（**手写** `FutureProvider.family<AuthRepository, String>`，`auth_repository_for_account_provider.dart`）= 指定账号的 CAS 仓库（先 `claimLegacyCredentials` 再 `AuthRepository(account: …)`）。**刻意不用 autoDispose**：`imsSessionProvider` 会 `ref.read` 它，自动销毁会丢掉在途 future。

  - `authRepositoryProvider`（`@Riverpod(keepAlive: true)`）= 当前账号的**唯一入口**，`watch(currentAccountProvider)` 后转发 family。业务代码一律用它；只有 `ims_session_provider.dart` 的 `_resolveRedirect(ref, account)` 直接按会话账号取 family（切号瞬间 `authRepositoryProvider` 可能还在重算）。

- **读盘按账号、写盘按入参账号**：`AuthRepository(account: …)` 构造时只读该账号那份 TGC/凭据；`login(username, …)` / `cacheCredentials(username, …)` 的落盘键用**入参 username** → 「当前是 A、正在登录 B」的切号流程不会写串。

- **免登录闸门 = `AuthRepository.isTgcAlive()`**（一次 CAS 探测，**绝不触发重登**）：`splash_screen.dart` 与 `account_screen._switchAccount` 为 true 时直接 `_enterHome(cardNumber)` / `_completeSwitch(context, ref, account)`（两者都是：设 `currentAccountProvider` → **重新**取 `studentInfoRepositoryProvider` → 刷显示名 → 跳首页），**免密码免 MFA**；false 才走原来的 `prepareLogin → detectMfa → login`（必要时弹 MFA）。**不要拿 `getImsRedirectInfo()` 当闸门**——它 TGC 过期会静默重登，等于每次启动都重登一遍。

- **⚠️ 假阳性陷阱（2026-09-19 已从根上堵住，别退回旧写法）**：CAS 会话失效时会 302 回 `…/cas/login;jsessionid=…`，而 `AuthRemoteDataSource.getRedirectImsUrl` 从前对**任何** `Location` 都算成功 → ① `getImsRedirectInfo()` 收不到 `TgcExpiredException`，**静默重登 `_relogin()` 永不触发**；② `fetchAndActivateJsessionId` 只拿得到**未认证的匿名 JSESSIONID**（`/jxcjcaslogin` 自己也被 302 打回登录页），日志里却一直打印 `[ImsSession] 换票成功`；③ 所有教务请求回 547 字节 `<script>alert('温馨提示：凭证已失效，请重新登录!');…` → 首页课表卡片红字「课表获取失败」（用户 2026-09-19 报的问题，实测链条见下）。现在唯一判定 = `auth_remote_datasource.dart` 顶层纯函数 `isCasLoginRedirect(String? url)`（**先剥掉 `;jsessionid=` 路径参数、再精确匹配 `/cas/login` 末段** —— 写成 `contains('/cas/login')` 会把 `/cas/loginfo` 误判进来，写成 `path == '/cas/login'` 又漏掉真实形态 `…/cas/login;jsessionid=ABC`）：`getRedirectImsUrl` 与 `getCasRedirectUrl` 见到它即抛 `TgcExpiredException`（后者顺带避免在 CAS 域里白转 5 圈），`isTgcAlive()` 复用同一函数。

- **实测证据（2026-09-19，python + 真实会话）**：① `GET https://ssl.jxufe.edu.cn/cas/login?service=…%2Fjxcjcaslogin` 带**有效** TGC → 302 `Location: https://jwxt.jxufe.edu.cn//jxcjcaslogin?ticket=ST-…`；**不带/带失效 TGC** → 302 `Location: https://ssl.jxufe.edu.cn/cas/login?service=…`（形状与「成功」一模一样，这就是假阳性来源）。② 完整链路 `②/jxcjcaslogin`（取 JSESSIONID）→ `③GET 带 ticket 的回跳地址激活` → 课表请求拿到 **12540 字节真实 HTML**；对照（只走 ticket、不先取匿名票）恒回 547 字节 `凭证已失效`。③ 失效期日志形态 = `[ImsSession] 换票成功` 与 `[home_widget] 仪表盘「今日」获取失败: DioException [unknown]: 凭证已失效，请重新登录` **反复交错** —— 见到这个组合就是本缺陷（不是教务故障）。守卫 = `test/cas_login_redirect_test.dart`（11 例：判定语义含 `;jsessionid` 与 `/cas/loginfo` 反例 / 假 `HttpClientAdapter` 验证 302 两种去向与 200 登录页老路径 / 三条源码守卫）+ `test/auth_session_account_test.dart` 的假阳性例（fake 用真实形态 `…/cas/login;jsessionid=ABC`）。

- **首页「今日课程」卡 = cache-first + 联网刷新 + 失败降级**（`lib/features/home/data/providers/dashboard_providers.dart` 的 `dashboardTodayCoursesProvider` → `scheduleCacheRepositoryProvider.load(refresh: true)`，与实况窗 `live_class_screen` 同口径）：会话过期 / 断网时退回 `scheduleCache` 里的整学期课表，只有**缓存也为空**才把异常交给卡片。**别再改回裸 `scheduleRepositoryProvider`** —— 在线仓库一次失败就在首页摊红字。

- **TGC 捕获两条分支都要**：`login()` 的 302（Set-Cookie）与 200+「登录成功」（MFA 后）都调 `_captureTgcFromCookies(response, username)`；只认 302 会让 MFA 用户的票永远落不了盘（`_tgc` 恒 null → 闸门永远 false）。200 分支没带 Set-Cookie 时行为不变。

- **桌面小组件**：`home_widget_sync.pushAuthSnapshot` 的 `tgc` 读本账号 `authDs.getTgc(account)`。

- **守卫测试**：`test/auth_session_account_test.dart`（17 例：TGC/凭据按账号隔离、旧单键精确认领与幂等、读盘按账号、切号不写串、重登用本账号凭据、闸门四态（无票 / 有效 / 过期 / 网络错）、CAS 打回登录页的假阳性、200 分支捕获 TGC）+ `test/auth_trust_device_test.dart`（8 例，调用点已随签名更新：`saveTgc('账号', 'tgc')`、`AuthRepository(account: …)`）。改口径先动这两处。



### 12.2 教务令牌的手动刷新 —— 设置页「教务会话」节（2026-09-15 立）



**用户诉求（原话）**：「我们需要一个在设置里刷新 ims 登录令牌的按钮」；随后问答裁定：语义 = **先探活、失效才换**（不是无条件换票），且卡片要把当前状态与令牌显示出来。



- **落点**：`lib/features/settings/presentation/settings_screen.dart` 的「教务会话」节（`_ImsSessionCard`，排在「平台标识」与「桌面小组件」之间），节颜色 `FeaturePalette.imsSession`（`#00695C`）。**设置页是唯一入口**（§3「全局偏好一律收拢到设置页」）。

- **判定口径 = `lib/features/ims/auth/domain/ims_token_refresh.dart`（纯逻辑，唯一实现）**：`enum ImsProbeResult { alive, expired, noSession, unknown }` → `ImsTokenRefreshActionFor()` → `enum ImsTokenRefreshAction { keepCurrent, renew }`。**只有 `alive` 走 `keepCurrent`**；`expired` / `noSession` / `unknown` 一律换票（unknown 也换：用户按这个按钮就是要一张能用的令牌，在按钮上原地报错没用）。同文件还有 `imsProbeBodyLooksValid` / `maskImsToken` / `imsProbeLabel` / `imsRefreshOutcomeText`。

- **探活实现 = `ImsSession.probe()`**（`lib/features/ims/auth/data/ims_session.dart`）：`GET /jw/common/getStuGradeSpeciatyInfo.action?xh=`（最小、**不依赖学生号**——实测传空也返回本生数据），手工带 `Cookie: JSESSIONID=<token>`。

  - ⚠ **必须用 `ResponseType.bytes`**：`ImsAuthInterceptor.onResponse` 只认 `data is String`，用 bytes 它就不会把我们的探活偷换成「自动换票 + 重试」——**探活结论必须原样交给调用方**，否则「先探活」这个口径在代码里等于不存在。

  - 判据方向**不能反**：`jwSessionExpired`（547 字节 UTF-8 alert 页）→ `expired`；`{` 开头且能 `jsonDecode` 成 Map → `alive`；其余 → `unknown`。**宁可 unknown（进而照样换票），也不能把登录页 / 半截页当成有效** —— 把失效当有效，用户会以为修好了、业务页却仍然打不开。

  - 配套新增 `ImsSession.peek()`：只读（内存 → 磁盘）看一眼令牌，**不发请求、也不换票**；卡片首屏用它（`ensureReady()` 在本地没有令牌时会顺手走一次 CAS 换票，**打开设置页不该触发登录**）。`probe()` 内部也走 `peek()`。

- **实测（2026-09-15，打实时教务）**：真令牌 `633DA58E…` → `alive`（HTTP 200 / **232 字节** `{"status":"200","message":"操作成功!",…}`）；伪造 32 位令牌 → `expired`（547 字节 alert 页）；无本地令牌 → `noSession`。三个分支都有真数据证据。

- **界面口径**：状态胶囊（读取中 / 已就绪 / 未就绪 / 不可用 / 刷新中）+ 掩码令牌（`maskImsToken`，前 8 位）+ `账号 <卡号> · 签发 <HH:mm:ss>`（`issuedAt` 在重启后为 null → 显示「签发时间未知（本次启动尚未换票）」）+ 最近探活结论 + 最近一次失败原因；按钮「刷新登录令牌」busy 时禁用；结果走 SnackBar（`imsRefreshOutcomeText`：**令牌仍有效时不谎称「已刷新」**）。切换账号 → `imsSessionProvider` 重建 → 卡片用 `ref.listen` 清掉本地状态。

- **守卫测试**：`test/ims_token_refresh_test.dart`（12 例：判定表四态 / 响应判据方向 / 掩码与文案 / 源码守卫「probe 必须在 renew 之前，且 renew 必须被判定表守住」）+ `test/ims_session_card_test.dart`（3 例：有令牌显示掩码且**打开页面不换票** / 无令牌显示未就绪 / 按按钮判不出时照样换票、失败落在卡片与 SnackBar）。改口径先动这两处。

