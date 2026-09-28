# 学习通（`lib/features/chaoxing/`）

用户 2026-09-19 立项，原话：

> 我发现了一个接入学习通内容的方法，原智慧江财网页里有一项叫"网络教学"，然后会跳到江财教学网，
> 然后可以从"本科生入口"/"学习空间"跳到学习通，这样我们就可以接入学习通的作业信息与通知消息了

## 已拍板的三项口径

| 维度 | 决定 | 理由 |
|---|---|---|
| 范围 | **只读三件套：课程 / 作业 / 通知** | 不碰任何写操作（不交作业、不标已读、不改课程） |
| 入口 | **首页服务目录新增「学习通」磁贴 + 独立页** | 与其余服务同口径，不另开悬浮球/仪表盘卡 |
| 成本 | **扫全部课程（≈2 请求/课）+ 本地缓存** | 平台没有「全校作业」接口，只能逐课取；缓存让二次进入零请求 |

## 零密码链路（与图书馆那条**只差 refer 一处**）

| # | 跳/请求 | 得到什么 |
|---|---|---|
| 1 | `AuthRepository.getServiceRedirectUrl(ChaoxingEndpoints.casServiceUrl)` | 用 `app_data/auth.hive` 里已有的 `TGC\|<账号>` 换票 → `…/login_auth/cas/jxufe/index?ticket=ST-…` |
| 2 | 网关消费票据 → 200 一张「跳转中…」页 | 页内 `data` / `time` / `enc` 三个签名值（`parseGatewayBridgeParams` 解析，**标识符要回代到 `var` 声明**） |
| 3 | `GET /login_auth/cas/jxufe/login?data&time&enc` | `{"status":true}` —— **这一步下发 `.chaoxing.com` 域级 passport**：`UID/_uid/_d/vc3/uf/uname/fid/p_auth_token/xxtenc/cx_p_token/DSSTASH_LOG` |
| 4 | 跳 `https://i.chaoxing.com?data&time&enc` → 302 `/base?t=…` → 200 | 登录完成；**收件箱 token 就在这一页**（`chaoxingNoticeToken`） |

网关页的 `jumpToRefer(firstReferer, …)` 把 `init?refer=` 传进来的地址**原样回显**并跳过去
→ 落点客户端可控，这正是「同一条链、换 refer 就能拿学习通会话」的原因
（图书馆那条 refer 写 `/find/sso/login/jxufe/0?pageType=0`，这边写 `https://i.chaoxing.com`）。

⚠ **用户给的「智慧江财 → 网络教学 → 江财教学网」只是线索**：ehall（`ehall.jxufe.edu.cn`）
登录后**一个会话 cookie 都不下发**、9 个应用清单接口全 404，那条路走不通；真正可用的是上面这条
（不经过教学网页面，也不需要 fid —— `fid=1412` 只在将来要走
`passport2.chaoxing.com/login?fid=1412` 时才用得上，故留在 `ChaoxingEndpoints.fid` 备查）。

> **⚠ 2026-09-20 架构审查 ②：这段换证链的「逐跳循环」已上提到
> `lib/core/network/cas_walk.dart` 的 `walkCasRedirects`**（与阅读学分 / 畅想之星 / 图书馆 /
> 入馆教育共用一份）。本模块只保留**私有子协议**（都在 `afterResponse` 钩子里）：
> 落在网关域 → 重放桥接接口（`parseGatewayBridgeParams` + `status:true` 判定）→
> `CasHopGoto` **改跳**学习空间（下一跳地址是页面里算出来的，不是响应头给的）→
> 落在学习空间域 → 收工并建 `ChaoxingSession`；落到别的主机**直接抛错、不猜**。
> 跳数上限（`maxHops = 8`）与错误文案仍归本模块。行为由
> `test/chaoxing_data_test.dart` 的端到端换证链用例 + `test/cas_walk_test.dart` 守着。

## 数据来源与解析口径

| 数据 | 接口 | 要点 |
|---|---|---|
| 课程 | `GET mooc1.chaoxing.com/visit/courses` | 每门课**有两个**指向 `stucoursemiddle` 的 `<a>`（封面那个在前且为空）→ 解析**两趟**：先认 `a.courseName` 再回填 href |
| 作业入口 | `GET /visit/stucoursemiddle?courseid&clazzid&vc=1&cpi` | `enc`/`openc` **每课各不相同**，必须逐课抠；挑带 `openc` 的 `data` 属性，**不要** `status=` / `pageNum=` 变体 |
| 作业列表 | `GET /mooc-ans/work/getAllWork?<原样 query>` | **HTML**：`li > .titTxt > a.inspectTask[data]` + 三个 `span.pt5`（开始/截止/状态）+ `div.titOper`（已完成时 `90分`）。⚠ query 必须**原样拼进 URL**，走 `queryParameters` 会再编码 → 签名对不上 |
| 通知 | `GET notice.chaoxing.com/pc/notice/getNoticeList?s=<token>` | JSON，一次最近 20 条；发件人字段是 **`createrName`**（没有 `senderName`）、已读是 **`isread`**（小写 r） |
| 红点 | `GET i.chaoxing.com/base/getNoticeCount` | `msg` 是**布尔**不是条数（实测 20 条通知时也是 `false`）→ **不用于界面计数** |
| ⚠ 作废 | `POST /mooc-ans/api/workTestPendingNew` | 恒返回 `[]`（7 种变体全试过）→ 别拿它当「待做作业」筛选器 |
| ⚠ 未破解 | 通知翻页 | `lastGetId` / `lastPage` / `page` / `pageNum` 都返回同一页 → 只取第一页 |

字段与实测样本见 `reverse_engineering/学习通接口.md`。

## 目录结构

```
domain/            纯领域：课程 / 作业 / 通知 / 快照 / 文案（无 Flutter、无 Hive、无网络）
data/              会话、端点表、Cookie 罐、HTTP 客户端、仓库（编排）、缓存、刷新闸门
data/anti_corruption/   三个解析器：课程清单 HTML、作业入口 query、作业页 HTML、通知 JSON
data/datasources/       三个远端数据源：换证（auth）/ 课程与作业（mooc）/ 通知（notice）
data/providers/          Dio、数据源、仓库、控制器、角标、刷新闸门
presentation/           主页 + 作业 / 通知 / 课程三个二级页 + 共享行/卡组件
```

- `ChaoxingEndpoints` 是**全部地址的唯一出处**（守卫生效点见下）。
- `ChaoxingRepository` 的换票接缝是 `typedef ChaoxingTicketFetcher = Future<Either<Failure,String>> Function(String casLoginUrl)`
  —— 故意**不传整个 `AuthRepository`**：单测可以直接喂假票据，不必真联网（`libsp` 那边传的是整个
  repository，于是只能靠真实网络验证）。

## 会话、缓存与刷新

- **Cookie 按域匹配**（`SessionCookieJar`）：passport 是 `Domain=.chaoxing.com` 的**域级** Cookie，
  必须同时发给 `i.chaoxing.com` / `mooc1.chaoxing.com` / `notice.chaoxing.com`；而换证中间那几跳
  （`unified-auth.chaoxing.com` 的 `JSESSIONID`/`firstReferer`/`route`）是 **host-only，绝不外泄**
  —— 混发会把会话搞坏（`libsp` 踩过同源问题）。同名时**更具体的域赢**（host-only > 域级）。
- **会话不落盘**：`ChaoxingStore`（Hive box `chaoxing_<账号>`，单 key `snapshot`）只存**业务快照**，
  Cookie 只在内存里活一次刷新。
- `refresh()` 的容错口径：作业**逐课并发（4 路）**，单课失败**沿用上一次的旧作业**并记进
  `failedCourseKeys`；通知失败**沿用旧通知**、只把 `noticesAvailable` 置 false；课程清单取不到
  → 整次抛错。**任何失败都不落盘** —— 只有「取全了」的快照才覆盖缓存（见下「风控」）。
- **1 分钟自动刷新闸门** `chaoxingMinRefreshInterval`（口径照抄畅想之星）：首次进入 / 从子页返回 /
  回前台受限；手动下拉、错误卡重试、清除后重取不受限。窗口起点 = **上一次真的取到新数据的时刻**
  （界面那行「更新于 HH:mm:ss」同源）。

## ⚠ 风控（「刷新会刷新没」的根因，2026-09-19 实测）

请求过密时超星会回 **`202` + 4527 B 的验证码挑战页**（`<title>提示页面</title>` +
`【9010】操作异常，请输入图片中的验证码`）。它长得像一次成功响应、`validateStatus` 全放行，
但正文里**既没有课程锚点、也没有 `getAllWork` 作业入口、更没有「暂无内容」空态标记** ——
首版把这种页面一律当**空结果**，于是：

1. 那几门课的作业**静默消失**（用户看到的「作业刷新会刷新没」）；
2. `refresh()` 又把残缺快照无条件写进 Hive → **好缓存也被覆盖**，退出重进都回不来；
3. 若这批里含 `/visit/courses`，就是**课程也一起空**。

实测触发与恢复口径（同一会话、同一批课程详情页）：

| 情形 | 结果 |
|---|---|
| 全并发 8 个 / 16 个 | **0 次风控** |
| 全并发 24 个 | **24/24 全中** |
| 触发后每秒探测一次 | **60 秒仍不恢复**（60/60 全是挑战页） |
| **匀速 2 请求/秒**扫 35 门课 | **第 31 门（≈62 个请求）起整段变验证码页** ← 决定性 |
| 稳态 1 请求/秒 × 20 个 | 0 次（但只发 20 个请求，没到预算） |

→ 结论有两条，**第二条改变了架构**：

1. 触发量是**累计请求数（≈60 个/窗口）而不是速率** —— 一次全扫 = 35 × 2 = **70 个请求 > 预算，必然撞墙**（慢到 2 请求/秒也一样）。所以不能只靠限速，必须**分批轮转**：
   `ChaoxingRepository.maxCoursesPerScan = 20`（每轮 ≤ 40 个请求，留够余量），游标滚动，
   没轮到的课沿用缓存里的旧数据并如实记进 `pendingCourseKeys`，下一轮从游标接着扫
   → 两轮覆盖 35 门。
2. **撞墙也不能丢数据**：每门课「只有**扫成功**才允许替换（哪怕是替换成空）」，
   其余（窗口外 / 失败 / 被拦下）一律把旧作业原样搬过来 → 刷新永远不会让作业凭空消失。

配套四件：

1. **识别**：每个业务响应都过 `ChaoxingHttpClient.ensureUsable` → 挑战页抛
   `ChaoxingChallengedException`（与「会话失效」分开：换票没用），
   `worksOf` 抠不出作业入口 / `courses` 解析 0 门 / 作业页 0 条且无「暂无内容」
   一律抛 `ChaoxingPageException` —— **「真没数据」与「没拿到可信页面」必须二分**；
2. **限速**：`chaoxingMinRequestInterval = 260 ms`（全局一条队列，业务请求传 `throttle: true`；
   换证链不排队）。⚠ 实现必须是**原子预定下一格** —— 首版「读上次时刻 → 睡够 → 写时刻」
   在 4 条 lane 下会一起醒来一起发，实测退化成 4 请求/间隔（64 个请求 4.3 秒跑完，风控照样触发）；
3. **命中即收手 + 冷却**：作业扫描一旦撞上风控立刻停发剩余请求，进
   `challengeCooldown = 120 秒` 冷却（冷却期内**一个请求都不发**；`force: true` 才越得过
   —— 手动下拉 / 点刷新带 force，自动刷新不带）；
4. **界面如实说**：概览卡那行会显示「N 门课扫描失败」「另有 N 门课下一轮扫（学习通有请求配额，每轮扫 20 门）」
   「学习通限流，本轮沿用上次数据」——不让用户自己去猜「没作业」还是「没扫到」。

⚠ **为什么「下一轮」不是立即续扫**：两轮各 40 个请求若连着打（80 个/25 秒）会重新撞上
同一个累计预算（实测第 62 个请求就整段变验证码页）。所以轮转**跨时间**发生 ——
由 1 分钟自动刷新闸门（进入页面 / 从子页返回 / 回前台）自然推进：第一次进来补完 20 门，
下一次进来或下拉刷新补另外的。手动下拉不受闸门限制，随时可以催一轮。

## ⚠ 第二个真凶：并发双扫 + `previous` 为空（2026-09-20 用户报「我明明有一项线性代数的作业，为什么提示没有作业」）

风控那套落地后**仍会丢数据**。真机取证（VM Service 读实时状态 + 逐帧回溯 Hive）查到两条
**互相独立**的缺陷：

| # | 缺陷 | 真机证据 | 修法 |
|---|---|---|---|
| 1 | **两个 `refresh` 并发跑** | 缓存里两帧快照相差 **280 ms**（`works=13` / `works=29`，`pending=15` / `19`，都带 `throttled=true`）——各打一份 ≈40 请求，双双撞风控，**后写的那份盖掉前一份** | `ChaoxingController.refresh` **单飞**：已在飞的那次直接复用同一个 Future（`_inFlight`）。页面侧有三条触发路径（首帧 `post-frame` 自动刷新、`RouteAware.didPopNext`、`_openChild().then`），而 1 分钟闸门只在**取到新数据后**才记账 → 刚失败 / 刚进页面时根本拦不住，闸门只能建在控制器里 |
| 2 | **`previous` 是 `null`** | 首帧自动刷新在 `build()` 读完缓存**之前**触发 → `state.valueOrNull == null` → 仓库那套「只信扫成功、其余沿用 previous」的兜底**整条失效**。线性代数在课程表第 5 位、`pendingCourseKeys` 里就有它 → 缓存里明明存着那条作业，界面却什么都没有 | `final previous = state.valueOrNull ?? await repository.cached();` —— 内存里没有就**回落到磁盘缓存** |

顺带补齐界面口径：**「本轮未扫到」不许说成「没有作业」**（这正是用户那句话的另一半）。
唯一出处 = `ChaoxingSnapshot.isCoursePending / isCourseFailed / unscannedCourseKeys` +
`chaoxingCourseScanNote(snapshot, courseKey)`（`domain/chaoxing_text.dart`）：

- 未扫到 → `本轮未扫到（学习通有请求配额，下次进入补扫）`
- 扫描失败 → `本轮扫描失败，显示的是上次数据`
- 正常扫过（**哪怕真的没作业**）→ **空串，不挂任何备注**

三个渲染点：`ChaoxingCourseRow` 的 `note`、`chaoxing_courses_screen.dart` 的副标题与展开正文
（空课正文只在「正常扫过」时才敢写「这门课没有作业记录」）、主页「待做作业」空态
（`另有 N 门课本轮未扫到，可能有遗漏`）。

## 只扫当下学期 + 通知兜底（用户 2026-09-20 选定 A+B）

**起因 = 用户提问**：「为啥要扫描一遍才知道有哪些作业，没有统一接口吗」。

先把话说清楚：**通知与课程本来就有统一接口，只有作业没有** ——

| 数据 | 统一接口 | 成本 |
|---|---|---|
| 通知 | `notice.chaoxing.com/pc/notice/getNoticeList?s=`（JSON） | **1 请求** |
| 课程 | `mooc1.chaoxing.com/visit/courses`（HTML，一次 34~35 门） | **1 请求** |
| 作业 | **没有** —— 逐课 `stucoursemiddle`（取签名 query）→ `getAllWork` | **2×N** |

为什么作业结构上就没有聚合（实测，详见 `reverse_engineering/学习通接口.md` §9.1）：
作业挂在「课程 + 班级(`classId`)」下，`getAllWork` 的 query 带**每课一份签名**
（`enc`/`openc` 各 32 hex，35/35 门各不相同），签名把「这台客户端有权看这门课」编了进去
→ 拿一串 courseId 拼批量请求在协议层就不成立。唯一长得像聚合的
`POST /mooc-ans/api/workTestPendingNew`（课程列表页 JS 自己用它点红点）**恒返回 `[]`**
（web UA / App UA / `mooc1-api` 域共 10 种变体全空，2026-09-20 复核）。
`task.chaoxing.com`（收件箱壳页配置里的 `taskHttps`）根路径 404、猜的 5 条路径全 404；
学习空间与泛雅引用的 23 个 JS bundle 里没有任何 work/task 接口字面量。

**所以真正的解法是缩小范围，而不是分批轮转**：

- **A｜只扫当下学期**（`domain/chaoxing_scan.dart`）：`currentTermCode` 由
  `currentSchoolTerm()` + `schoolTermCode()` 推出（口径与课表/校历同源），只扫
  学期码命中的课 **+ 学期前缀认不出的课**（实测 35 门里有 2 门无前缀，多为实训/通识，
  可能就是本学期的 —— 为省 4 个请求漏掉一门真在上的课不划算）。
  **真机实测 2026-09-20**：261 学期 10 门 + 无前缀 2 门 = **12/35 门 = 24 个请求、6059 ms、0 风控**
  （24 × 260ms 限速 ≈ 6.2s，反证限速器在算）→ **窗口装得下整个课程池，游标推回 0、每轮都是同一批全量**，
  用户点一次刷新就是完整的，不再有「两轮才凑齐」。
  两条**不筛**的退路（都在 `chaoxingScanPlan` 里，别在仓库层再判一次）：学期码为空、
  **一门课都不匹配当下学期码**（新学期课程还没建 → 照筛会让界面变成「一条作业都没有」）。
  被有意跳过的课进 `snapshot.skippedCourseKeys`，课程页如实写「非当下学期，未扫描（只扫当下学期）」——
  ⚠ **不能复用 `pendingCourseKeys` 的文案**：那档说的是「下次进入补扫」，而这些课**下一轮也不会扫**。
  窗口（20）只有在一学期选课 > 20 门时才起作用，那时才恢复轮转 + `pendingCourseKeys`。
- **B｜通知里兜一刀**（`chaoxingNoticeWorkHints`）：平台在老师发布作业时会自动发一条
  `作业:《课程名》作业标题`（实测标题里就带课程名与作业标题）→ 通知是统一接口，
  拿它把「没扫到但确实发布了」的作业显示出来（主页「通知里的作业提醒」卡片，点开是通知详情）。
  **去重口径 = 该课已有作业的标题是否出现在通知标题里**（实测作业列表那条
  `9月20日24:00前提交作业` 正是通知标题的后半段）→ 已扫到的不重复显示。
  ⚠ 只认 `作业:` / `作业：` 开头这一种形态：「作业结束提醒」是已结束，不是发布。

## 页面

| 页面 | 内容 |
|---|---|
| `chaoxing_screen.dart`（主页） | 概览卡（待做 / 未读 / 课程三格 + 更新时刻 + 失败课数）+ 待做作业（前 5）· 最近完成（前 3）· 通知消息（前 4）· 我的课程（前 6），各带「查看全部」 |
| `chaoxing_works_screen.dart` | 全部作业 + 四档筛选（全部 / 待做 / 待批阅 / 已完成）；相邻同课只印一次课程名 |
| `chaoxing_notices_screen.dart` | 全部通知 + 点开全文弹窗（**不做标记已读**） |
| `chaoxing_courses_screen.dart` | 全部课程 + 学期 chip 筛选 + 展开看该课作业 |

## 下游消费方（别的模块读哪些东西）

| 消费方 | 读什么 | 口径 |
|---|---|---|
| `lib/features/score_estimate/`（分数估计） | **作业快照缓存**（`ChaoxingStore.open(account).load()`，`data/ge_chaoxing_works.dart`） | 把某课的**已完成且有分数**的作业均分接进该课的「作业」分项（`domain/ge_chaoxing_sync.dart`）。⚠ **只读缓存、不发请求**（超星请求配额见上文风险控制节），且**只有该课已配「作业」分项（占比已知）才接**；新鲜度取 `snapshot.fetchedAt`，界面照实显示。详见 `docs/agents/04-…` 的「学习通作业成绩接入」段 |


**消息可点看详情（2026-09-19 · 用户原话「我希望消息可以点击看详情」）**：通知行
`ChaoxingNoticeRow` 的 `onTap` 非空时整行可点并出右箭头，点开 = `showChaoxingNoticeDetail`
（`presentation/chaoxing_common.dart`，**弹窗唯一实现**，主页「通知消息」区块与「全部通知」页
共用 —— 此前主页的行点了没反应，只能先进「全部通知」）。弹窗 = 图标 + 标题 + `置顶 · 发件人 · 时间`
+（查得到才印）`所属课程：<课程名>` + 正文 `SelectableText`（**保留段落只 trim**，别用
`chaoxingCleanText` 把整篇压成一行）。课程名由 `chaoxingCourseNameOf(snapshot, courseId)`
（`domain/chaoxing_text.dart`）从快照查 —— **查不到返回空串且整行不画**，绝不回显裸 `courseId`。
⚠ 不提供「在学习通里打开」：`ChaoxingNotice.detailPath` 依赖会话 Cookie，外链只会落到登录页。
⚠ 弹窗是**路由**，关掉会让页面收到 `didPopNext` → 走一次「返回即刷新」（`refreshes` 会 +1/次），
这是既有的自动刷新口径，不是写操作。

**作业也可点看详情（2026-09-19 三轮 · 用户原话「也做」→ 与通知同一套）**：作业行
`ChaoxingWorkRow` 同样 `onTap` 非空才可点并出右箭头，点开 = `showChaoxingWorkDetail(context, work,
{required now, courseName})`（**同一份 `chaoxing_common.dart`，主页「待做作业 / 最近完成」两个区块、
「全部作业」页、课程页展开的作业行共用**）。弹窗行式 label/value：`状态`（`chaoxingWorkStatusText`
→ `已完成 90 分`，**分数不单列**）、`课程`（查得到才印）、`开始时间` / `截止时间`（一律**绝对时刻**
`chaoxingMomentText` → `2026-09-20 23:59`；列表里那套相对口语「今天 08:05」在详情里没信息量）、
`剩余`（**只在 `work.status.isOpen`（待做）时画** —— 已完成/待批阅谈「已过期 X」是误导，与
`ChaoxingWork.isOverdueAt` 同一口径；过期标 `AppColors.critical`，否则 primary）。

入口 = `lib/features/home/presentation/home_service_catalog.dart` 的「学习通」条目
（`HomeServiceGroup.study`，强调色 `FeaturePalette.chaoxing = Color(0xFF0D47A1)`）。

## 测试

- `test/chaoxing_parser_test.dart`（24 例）：三个解析器 + **端点与换证链守卫**
  （CAS service 必须是网关那个百分号编码串、refer 必须是学习空间、桥接参数回代）。
- `test/chaoxing_data_test.dart`（**45 例**）：Cookie 罐按域匹配、快照派生与文案（含 1 分钟闸门、
  `chaoxingCourseNameOf`、`chaoxingMomentText`）、**业务请求跳转口径 3 例**（真机 302 回归，见下）、
  **风控与「可信空」口径 13 例**（挑战页 202 / 200 两种识别、课程页与作业页的挑战页、
  抠不出作业入口、作业页 0 条无空标记、真·空课仍返回空、课程清单空 / 挑战页、限速器串行、
  **限速器并发**、换证链不排队）、**端到端 7 例**（假 HTTP 走完整换证链 + 真解析器：
  4 门课 / 3 条作业 / 4 条通知 + 落缓存 + Cookie 归属；会话失效只重换一次票；换票失败抛带原因的异常；
  **风控截断 → 已扫到的照算 / 没扫到的沿用旧数据 + 冷却期一个请求不发**；**分批轮转**；
  **可信空压过旧数据**；**通知失败沿用旧通知**；**单课结构变化 → 逐课容错仍落盘**）、
  **控制器 3 例**（★ **并发 `refresh` 只跑一次全扫**（假仓库 `implements ChaoxingRepository`，
  第二次调用必须 `identical` 复用同一个 Future）；★ **首帧刷新（`build` 还卡在读缓存时）
  也必须把磁盘缓存当 `previous`**；★ 未扫到 / 失败 / 正常三档文案）。
- `test/chaoxing_screen_test.dart`（**17 例**）：**界面渲染守卫** —— 用假控制器（`ChaoxingController`
  子类，只覆盖 `build` 与四个动作，**不碰网络与 Hive**）喂固定快照：主页四区块 + 概览三个 Key、
  空快照不崩且首次进入会取数（闸门只拦「有数据」的情形）、作业页四档筛选、通知页弹全文且不写已读、
  课程页展开看作业、刷新按钮真的调 `refresh`、**手动刷新带 `force` 而自动刷新不带**、
  **主页通知行点开详情**（「所属课程」只有查得到才印）、
  通知行 **`onTap` 非空才出右箭头**、**作业详情弹窗**（待做有「剩余」+ 开始时间缺失给 `—` / 已完成
  「已完成 90 分」且**无**「剩余」）、**主页两个作业区块的行直接可点**、作业行 **`onTap` 门控箭头**、
  ★ **未扫到的课如实说**（全部课程页写「本轮未扫到」而**不写**「这门课没有作业记录」；主页
  「待做作业」空态标注「另有 N 门课本轮未扫到，可能有遗漏」）。
  ⚠ 弹窗文案要用 `find.descendant(of: find.byType(AlertDialog), matching: find.text(…))`（列表行与
  弹窗常同文案，直接 `find.text` 会命中两个）。
  ⚠ 两个测试坑：①主页是长滚动页，默认 800×600 视口下第四个区块**根本不会 build** → 要放大视口，
  但 `tester.view.physicalSize` 是**物理像素**（测试 dpr = 3）→ 必须同时 `devicePixelRatio = 1.0`，
  否则 1000×2400 只有 333×800 逻辑像素；②作业页筛选 chip 的文字**带计数**（`已完成（1）`）
  → `find.text('已完成')` 找不到。
- `test/chaoxing_scan_test.dart`（**16 例**）：**「只扫当下学期」与「通知兜底」的纯域守卫** ——
  学期码口径（`261学期` → `261`、无 `学期` 二字 → 空串）、当下学期 + 无前缀都扫 / 往期课剔除、
  两组严格互补、学期码为空 → 不筛、**一门都不匹配 → 不筛**、`skipped` 的 JSON 往返与旧缓存缺键容错、
  三档扫描状态文案各不相同（**「非当下学期」不得含「下次」**）、
  作业通知识别（只认 `作业:` / `作业：`）、剥标题、标题包含去重、同课别的作业对不上时仍提示。
- fixture 全部脱敏（假号假名假 token），平铺在 `test/fixtures/chaoxing_*.html|json`
  （`chaoxing_courses_terms.html` = 学期筛选用：261 / 252 / 251 学期 + 2 门无前缀）。

### 真机冒烟（`tool/chaoxing_smoke.dart`，纯 Dart，不进 App）

```
& "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe" run tool\chaoxing_smoke.dart [--diag] [--all]
```

用本机 `app_data/auth.hive` 里的 TGC 把**真服务端**跑一遍：换票 → 网关桥接 → 会话 →
课程 → 逐课作业 → 通知 → 快照派生，逐项 ✓/✗。`--diag` 会把第一门课的
课程详情页与作业列表原样落盘到 `.scratch/xxt_smoke_*.html`，并打出重定向链。
⚠ **逐课作业默认只扫「当下学期」**（= 生产口径，见上节 A；学期码取课程里最大的那个，
`--term=252` 可手动指定）；`--all` 才全扫 35 门 —— 那**会撞风控**（末尾几门被验证码页拦下），是诊断用，不是验收。
⚠ 前置：TGC **没过期**（App 关闭久了票会失效，CAS 会回登录页 —— 脚本会明确报出来并打出逐跳）。
实测 2026-09-20（只扫当下学期）：**12/35 门（261 学期 10 + 无前缀 2）、24 个请求、6059 ms、0 风控**、
通知 19 条、12 项全过；学期分布 `261学期=10 / 无前缀=2 / 252学期=12 / 251学期=11`。
⚠ **代价（用户已知情并选定）**：往期学期的作业不再取数 —— 老用户靠缓存里的旧数据继续显示，
**全新安装只会看到当下学期的作业**（界面写「只扫当下学期（12/35 门）」）。
实测 2026-09-19（改前，分批轮转）：35 门 / 通知 19 条；`--all` 时末尾 6 门被风控拦下
（这正是当初催生「分批轮转」的那组数据）。
⚠ **作业条数是流动值**（21:0x = 5 门 32 条 → 21:2x = 7 门 44 条），**别把具体条数写进断言**。

## 踩过的坑

1. **业务页会先给 302（真机实测，假 HTTP 测试抓不到）**：`/visit/stucoursemiddle` 直接请求
   返回 **302 + 0 字节**，跟到带会话 token 的下一跳才是真页面。首版客户端一律不跟跳转
   （换证链需要逐跳自己判定），于是**所有课都被判成「没有作业」**（35 门课 0 条，且因
   没有异常还显示「扫描完成」）。现在 `ChaoxingHttpClient.get(..., followRedirects: true)`
   只给**业务请求**开（课程 / 作业 / 通知），换证链保持默认不跟；
   **被踢回 `passport2.chaoxing.com` 的 302 一律原样返回**，交给 `ensureAlive` 走失效重换。
   守卫 = `test/chaoxing_data_test.dart`「业务请求的跳转口径」三例。
2. **`enc`/`openc` 每课不同 → 端到端假 HTTP 不能对所有课返回同一张详情页**：四门课的作业入口
   URL 会一模一样，「只有一门课有作业」这种真实情形根本表达不出来（首跑实测：期望 3 条、实得 0 条；
   逐课给了 `chaoxing_course_middle_lin.html` 之后才对）。
3. **`hasPassport` 认三件套 `UID` / `_uid` / `p_auth_token`**：实测网关那一步三个一起发；
   只认后两个时，fixture 或服务端换个写法就会被静默判成「没登录」（首跑实测 2 例失败）。
4. **Cookie 归属断言要卡在正确的时机**：`jrose` 等 host-only Cookie 是换证**最后一跳**才下发的，
   「发给 `i.chaoxing.com`」这条断言必须发生在那一跳**之后**的请求上（用
   `i.chaoxing.com/base/getNoticeCount` 那一次），否则永远为假。
5. **红点不是条数**（`msg` 布尔）；**通知只有第一页 20 条**。
6. **凭据纪律**：`p_auth_token` / `xxtenc` / `vc3` / `_uid` / `_d` / 收件箱 `s` token / 作业页
   `enc`/`openc` 全是凭据 —— 探针与日志只报长度与形态，任何值都不许进对话与日志；
   `SessionCookieJar.namesOf()` 也只报**名字**（守卫里有一例专门断言 `toString()` 不含值）。
7. **风控修完不等于数据不会丢**（2026-09-20 用户报「我明明有一项线性代数的作业，为什么提示没有作业」）：
   真凶是**并发双扫 + `previous` 为 null** 这一对（见上「第二个真凶」）。
   ⚠ **定位手法值得复用**：`flutter run` 的日志每次重启会被截断、`debugPrint` 什么都不剩 ——
   改从 **Hive 文件逐帧回溯**（同一 key 在 Hive 里是**追加**的：`raw.find(b'{"courses"')` 找到的
   是**最旧**那帧，要扫全部匹配并把每帧的 `fetchedAt` / 条数 / 关键字段打出来）**+ VM Service 读
   实时状态**（`ProviderScope.containerOf` 沿 `visitChildren` 找容器，再 `read(provider)`）两边对。
   两帧相差 280 ms、`works` 13 vs 29 —— 「并发」这个结论就是从那 280 ms 里读出来的。
   ⚠ VM Service `evaluate` 的两个坑：**闭包捕获的局部变量不会做空安全提升**（`ProviderContainer? f`
   被 `void walk(Element)` 捕获 → `f.read(...)` 报 `Method 'read' cannot be called on
   'ProviderContainer?'`，要先 `final c = found; if (c == null) …`）；返回值字符串在
   `valueAsString` 里**会被截断**（约 100 字符），长结果要拆成多次短查询或落盘再看。
