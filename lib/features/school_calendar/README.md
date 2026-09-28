# 校历与学校时间（`lib/features/school_calendar/`）

> 用户 2026-09-27：「我们希望可以独立出来被所有模块复用，学年的时间范围就定为该
> 学年第一学期第一天到下学年第一天前一天；假期时间也可以从校历页查，
> https://jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp」

本模块是**全应用学校时间（学年 / 学期 / 假期）的唯一出处**，同时承载校历页面。
约 20 个 feature 从 `domain/school_term.dart` / `domain/school_time.dart` 取口径
（课表、首页今日课程、体测、公共查询、学习通「只扫当下学期」、分数估计、
志愿时长「本学年」、综测、AI 快照…）。

## 文件地图

| 层 | 文件 | 职责 |
|---|---|---|
| domain | `school_time.dart` | **学年 / 学期 / 假期时间轴**（2026-09-27 立）：`SchoolTermDates` / `SchoolYear` / `SchoolBreak` / `SchoolTimeTable` + 学期标识归一 |
| domain | `school_term.dart` | 「**当下学期**」判定 `currentSchoolTerm`、学期码 `schoolTermCode`（`xxy`）、选择器范围 |
| domain | `school_calendar.dart` | 教务校历页模型（月历 + `workday/nonday` 标注 + 备注行） |
| domain | `wxcal_semester.dart` | 小程序校历源模型（结构化事件 `WxCalEvent`） |
| domain | `teaching_week.dart` | 教学周推算（第 1 周锚点 = 学期 `start` 所在周一） |
| domain | `calendar_day_mark.dart` | 「假 / 班」角标索引（主源 = 小程序事件） |
| data | `datasources/school_calendar_remote_datasource.dart` | 教务校历页（免登录，匿名 JSESSIONID） |
| data | `datasources/wxcal_remote_datasource.dart` | 小程序校历接口 |
| data | `providers/school_time_providers.dart` | **其它模块取学校时间的入口**（`schoolTimeTableProvider` / `schoolYearProvider` / `schoolBreaksProvider`） |
| data | `providers/school_calendar_providers.dart` | 教务校历页 provider（`schoolCalendarProvider` family，按 `(xn, xq)` 缓存） |
| data | `wxcal_offline_data.dart` | 小程序校历离线快照（2017 秋 ~ 2026 秋，19 学期） |
| presentation | `school_calendar_screen.dart` / `calendar_day_sheet.dart` | 校历页（含「学年时间」卡）与单日详情 |

## 学校时间轴口径（`domain/school_time.dart`）

- **学年** = `[该学年第一学期第一天, 下学年第一学期第一天 − 1 天]`
  （用户 2026-09-27 裁定）。以 2025 学年为例：`2025-09-01 ~ 2026-09-06`。
- **下学年未公布 → 结束日留 `null`，绝不猜**。校历只公布到当前学年：
  `xn = 2027 / 2028` 的页面是 **723 字节空壳**，解析器直接抛
  `SchoolCalendarException('校历 HTML 解析失败：未找到月份表…')`。
  `SchoolYear.contains` 对 `lastDay == null` 按**开区间**处理（不早于起点即属本学年）。
- **假期（寒 / 暑假）结束日一律派生自「下一学段起点 − 1 天」**：教务页那个
  `假期结束日期` 就是它算出来的，已公布学年三处实测逐字吻合
  （2024 学年 `08-31` ↔ 2025 学年 `09-01`；2025 学年 `09-06` ↔ 2026 学年 `09-07`）。
- **占位值识别**：未公布学段会被教务页串成假日期（2026 学年因此出现
  **4 天寒假**）→ 跨度小于 `schoolMinWinterBreakDays`(14) /
  `schoolMinSummerBreakDays`(21) 时判为占位：`end = null, certain = false`。
- **学期标识归一**（唯一换算）：`schoolYearOfTermText` / `schoolTermOfText` /
  `schoolTermCodeOfText` / `schoolTermFullName` / `schoolTermTextOfCode`，
  接受短码 `251`、完整名 `2025-2026学年第一学期`、只到学年 `2025-2026学年`。
  **认不出必须返回 `null`/空串**，绝不兜默认年份（会把别学年的课算进本学年）。
  已收口的重复实现：`zc_year_sources.dart` 的 `zcSemesterStartYear`（转发别名）、
  `ims/grades/domain/semester.dart` 的 `Semester`（**整个类已删**）、
  `ai/tools/score_tools.dart` 的 `aiSemesterLabel`（只留 AI 侧两个兜底）。
- **学年窗口的两个口径都住这里**（2026-09-27 第二刀，从 zongce / 志愿时长收上来）：
  - `schoolYearOrFallback(table, xn)` —— **默认选择**：有校历用真实窗口，没有则兜底；
  - `schoolYearFallback(xn)` —— 固定 `[xn]-09-01 ~ [xn+1]-08-31`（纯函数 / 离线兜底）；
  - `schoolYearStartOf(day)` —— 「日期 → 学年起始年」（`month >= 9 ? year : year - 1`）；
  - `schoolDayText(day)` —— `yyyy-MM-dd`（学校时间里日期文本的唯一格式）。
  已收口：`zc_models.dart` 的 `zcYearWindowContains` / `zcDefaultYear`（转发别名，
  **日期算术已从该文件清零**）、`volunteer_hours_stats.dart` 的私有 `_inYear`（删除）。
  两条真实链路都传校历：`dashboardVolunteerHoursProvider`（`schoolTimeTableProvider(term.xn)`）、
  `zcAutoVolunteerProvider`（`schoolTimeTableProvider(yearEnd - 1)`）。
  ⚠ 传表与否会在 **09-01 ~ 09-06** 这段产生分歧（真实学年末可能是 `09-06`）。

### 页面上怎么看

`school_calendar_screen.dart` 的 **「学年时间」卡**（挂在「关键日期」之后）：
学年行（`2026-2027学年 · 2026-09-07 起（下学年校历未公布）`）+ 每个**已公布**学段一行
+ 每个假期一行（结束日未知 → 「待公布」胶囊）。与「关键日期」的分工：那张**原样**
列备注（含教务编的占位日期），这张只显示可信的派生结果；取不到时间表整卡不画。

### 实测台账（2026-09-27 探针原文）

| 学年 | 第一学段 | 寒假（派生） | 第二学段 | 暑期段 | 暑假（派生） | 下学年首日 |
|---|---|---|---|---|---|---|
| 2023 | 09-04~2024-01-19 | 01-20~02-25（37 天） | 02-26~07-03 | 07-04~07-10 | 07-11~09-01（53 天） | 2024-09-02 |
| 2024 | 09-02~2025-01-10 | 01-11~02-16（37 天） | 02-17~06-29 | 06-30~07-04 | 07-05~08-31（58 天） | 2025-09-01 |
| 2025 | 09-01~2026-01-15 | 01-16~03-01（45 天） | 03-02~07-05 | 07-06~07-10 | 07-11~09-06（58 天） | 2026-09-07 |
| 2026 | 09-07~2027-01-15 | 01-16~01-19 ← 占位 | 2027-01-20 ← 占位 | 07-06~07-31 | 08-01~? ← 未公布 | **未公布** |

## 两个校历源（别混用）

| 源 | 端点 | 给什么 | 不给什么 |
|---|---|---|---|
| **教务校历页**（学年 / 学期 / 假期口径的来源） | `jwxt.jxufe.edu.cn/public/SchoolCalendar.show.jsp`（免登录；先 GET `SchoolCalendar.jsp` 拿匿名 JSESSIONID） | 备注里的**结构化日期**：学期开始 / 结束、假期开始 / 结束 | **法定节假日**：逐日只有 `workday\|nonday`，国庆整段标 `workday` |
| **小程序校历**（假 / 班角标的主源） | `wxcourse.jxufe.cn/interface/api/interface/getSchoolCalendar` | 结构化事件（`国庆节放假` / `寒假开始` / `补第4周周五的课`） | 学年窗口（`start/end` 是学期区间，非学年） |

## 踩过的坑

1. **`enrollYear` 不是学年**：学籍 `enrollYear` = 入学年（该生 2025），
   拿它当学年会在 2026 年 9 月整月显示 `2025-2026 第一学期`。
   它只能用于「培养方案学年」与「军训是否显示」。
2. **`resolveTeachingWeek` 在假期会回退到上一学期** → 拿到 `TeachingWeek` 后
   **必须**用 `tw.term.matches(xn, xq)` 守卫。
3. **两套学年语义并存**：教学学年（本模块 `xn`）vs **测评学年**
   （`lib/features/zongce/domain/zc_models.dart` 的 `zcDefaultYear`，9 月起评上一学年）
   —— 「本学年志愿时长」用的是教学学年，别拿 `zcDefaultYear` 顶。
4. **`schoolTermCode` 的 `xxy` ≠ `wxTermCode`**：前者是用户界面口径
   （第二阶段 = 3），后者是小程序数据源 `term` 字段（无暑期段，`xq = 2` 给 `…2`）。
5. **教务页对未公布学段会「自洽地」编假日期**（假期结束 = 下一段开始 − 1 天），
   所以「日期看起来对得上」不能当可信判据，必须按跨度下限判占位。

## 守卫

- `test/school_time_test.dart`（**35 例**）：备注解析 / 学年窗口（含 null 与开区间）/
  假期派生与占位识别 / 归属查询 / 学期标识归一 / **固定口径兜底与「日期 → 学年」** /
  **源码守卫**（9 个声明只在 `domain/school_time.dart` 一处；`zc_models.dart` 与
  `volunteer_hours_stats.dart` 不许再出现日期算术；两个取数入口必须把校历传下去）。
- `test/school_time_providers_test.dart`（6 例）：用**真实抓取的教务页**
  （`test/fixtures/_cal_xq0.html` / `_cal_xq1.html` / `_cal_xq2.html` /
  `_cal_261_xq0.html`）走真解析器，断言 2025 学年 `2025-09-01 ~ 2026-09-06`、
  寒暑假天数、以及「下学年未公布 → `lastDay` 为 null」。
- `test/school_calendar_screen_test.dart`：「学年时间卡」例（真实教务页拼时间表 →
  学年行 / 已公布学段行 / 寒假「起 + 待公布」/ 占位结束日只在「关键日期」出现一次）。
- `test/zc_year_sources_test.dart` / `test/volunteer_activity_time_test.dart`：
  学期码 → 学年、志愿时长窗口（各有一例钉住「传校历 vs 不传」在这个分歧点上的差异）。
- 真网络探针：`.scratch/school_time_probe.dart`（跑法 `dart run
  .scratch/school_time_probe.dart`）。
