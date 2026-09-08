# 赛康精益体测 · 逆向计划（saikang_tice）

> 目标：查体测成绩的独立 Flutter 应用（Windows 桌面 + Android 双端），数据源 = 微信小程序「赛康精益」的后端接口。
> 厂商：[北京赛康精益](http://www.bjskjy.com.cn/)（智能体测设备 + 配套小程序）。

## 里程碑状态

- [x] **M1 抓包**（2026-09-07，PC 微信 4.0 + mitmproxy 本机代理，4MB 流量）→ `captures/wx_tice.mitm`（gitignored）
- [x] **M2 接口文档** → `接口文档.md`（8 个接口全部摸清，含实测参数语义）
- [x] **M3 登录态方案评估** → **结论：无微信墙**。查询接口无鉴权（openid 不校验、无需绑定、无 token/cookie/签名），直接 HTTP POST 即可
- [x] **M4a Flutter 脚手架**：`D:\Project\Ongoing\tice_app`（独立 git 仓，android+windows，--empty 模板）
- [ ] **M4b App 实现**：查询页（单查/批量学号）、年度选择、结果卡片、CSV 复制导出
- [ ] **M5 双端打包验证**（windows debug + android apk）

## 逆向核心发现（详见 接口文档.md）

1. 业务域名仅 `www.skjycx.com`，小程序 AppID `wx6ff9ff67c25de356`
2. 成绩查询 = `POST /src/StuSpace/queryStuResult.php`，参数 `stuNum + stuSchool + StartTestDate`（学年学期窗口内任意日期），**openid 可垃圾值**
3. 小程序 UI"解绑/重绑才能查多人"只是前端限制；后端不校验绑定，App 可直接按学号批量查
4. 响应：`stuResult[]` 每年度 7 分项（身高体重/肺活量/50m/立定跳远/坐位体前屈/耐力跑/引体向上）+ 总分等级 + 学生信息
5. 待补：女生分项键名（推测仰卧起坐）、多年度返回形态

## 使用约束（重要）

- 接口无鉴权：**知道学号即可查任何人的成绩**。仅限本人/授权查询，不内置学号枚举、不批量拉全库、不公开传播工具
- 抓包产物含真实 openid/姓名，`captures/` 已 gitignore，文档一律脱敏
