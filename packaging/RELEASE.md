# 发版手册（SmartJXUFE）

> 本文件记录**正式发版**的完整流程与所有坑。发新版时照此执行即可。
> 最近一次发版：**v2.0.0 / 2026-09-19**（首个正式签名版）。

## 1. 版本号（唯一出处两处，必须同步）

| 位置 | 字段 | 说明 |
| --- | --- | --- |
| `pubspec.yaml` | `version: X.Y.Z+N` | `X.Y.Z` → Android `versionName` / Windows 文件版本；`+N` → Android `versionCode` |
| `packaging/smarter_jxufe.iss` | `#define MyAppVersion "X.Y.Z"` | 决定安装包文件名 `SmartJXUFE-vX.Y.Z-windows.exe` 与注册表版本 |

Windows 可执行文件的版本信息由 Flutter 从 `pubspec.yaml` 注入（`windows/runner/Runner.rc` 里的 `1,0,0,0` 只是非 Flutter 构建的兜底），**不必改**。

## 2. Android 正式签名（密钥绝不入库）

| 项 | 路径 |
| --- | --- |
| keystore | `<仓库外的密钥目录>\smarter_jxufe-release.jks`（PKCS12，RSA 4096，有效期 30 年，别名 `smarter_jxufe`） |
| 口令与配置 | `<仓库外的密钥目录>\keystore.properties`（备份说明见同目录 `README-签名备份.txt`） |
| 工程内配置 | `android/key.properties`（gradle 读取，**已被 .gitignore 排除**；缺失时 release 自动回退 debug 签名） |

- 证书指纹（SHA-256）：`44:3F:7B:84:3A:09:52:99:8A:04:61:95:2A:0F:61:48:F3:3D:72:5D:6F:99:8D:AD:FD:46:83:12:23:BA:27:0B`
- ⚠️ **务必多处备份 `.jks` + `keystore.properties`**。丢失后无法再发布「可覆盖安装」的升级包，用户必须卸载重装（本地登录态与缓存清空）。
- ⚠️ 换签名（例如从 debug 换正式、或重新生成密钥）都会导致**新旧版本无法互相覆盖安装**：发版说明里必须写明「请先卸载旧版」。v1.0.0 → v2.0.0 就是这种情况。

自检（发版前必做）：

```powershell
$bt = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1
& "$($bt.FullName)\apksigner.bat" verify --print-certs dist\SmartJXUFE-vX.Y.Z-android.apk   # 期望 CN=SmartJXUFE
& "$($bt.FullName)\aapt2.exe" dump badging dist\SmartJXUFE-vX.Y.Z-android.apk | Select-String 'package:'
```

## 3. 构建产物

```powershell
$env:FLUTTER_ROOT='<FLUTTER_ROOT>'; $env:FLUTTER_SUPPRESS_ANALYTICS='true';
$env:FLUTTER_ALREADY_LOCKED='true'
$dart = "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe"
$snap = "$env:FLUTTER_ROOT\bin\cache\flutter_tools.snapshot"

Get-Process smarter_jxufe,MSBuild,VBCSCompiler,dart -EA SilentlyContinue | Stop-Process -Force
attrib -R build\flutter_assets\* /S /D 2>$null; Remove-Item build\flutter_assets -Recurse -Force -EA SilentlyContinue

& $dart $snap build apk --release        # → build/app/outputs/flutter-apk/app-release.apk
attrib -R build\flutter_assets\* /S /D 2>$null; Remove-Item build\flutter_assets -Recurse -Force -EA SilentlyContinue
& $dart $snap build windows --release    # → build/windows/x64/runner/Release/
& '<INNO>\ISCC.exe' packaging\smarter_jxufe.iss   # → dist/SmartJXUFE-vX.Y.Z-windows.exe

New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\SmartJXUFE-vX.Y.Z-android.apk -Force
# ⚠ 不再手工 `git archive` 源码包（2026-10-10 起，见下方「源码包口径」）
```

- **切换构建目标前必须删 `build\flutter_assets`**（该目录的增量拷贝非幂等 → `MSB8066 flutter_assemble.rule exited with code 1`）。
- **源码包口径（2026-10-10 改 · 用户裁定）：dist 里只放两个安装包，源码包不再自己建** —— 直接让 GitHub 为 tag 生成「Source code (zip / tar.gz)」。理由与代价：
  - 自动源码包**总是**反映 tag 在**当前**指向的内容，所以「脱敏后忘了重新打包」这类「包比代码旧」的失效模式被**从根上消除**（v1.0.0 / v2.0.0 那两个手工包正是这么坏的：构建于 09-09 / 09-19，脱敏在 09-21，包里留着未脱敏的真票据）。
  - 代价一：源码包不再与「发布那一刻的 tag」**内容冻结** —— 日后若重写历史、tag 被重新指向，下载到的就是新内容。对本项目这是**想要的**行为（脱敏能自动生效）。
  - 代价二：文件名与顶层目录变成 GitHub 的固定形态 `smarter_jxufe-<tag>.zip` → 解压目录 `smarter_jxufe-<tag>/`，不再是 `SmartJXUFE-vX.Y.Z/`。README 的下载表别再宣传旧命名。
  - 代价三：自动包不含子模块与 Git LFS 对象（本项目都不用，无影响）。
  - ⚠ 先决条件不变：**必须先提交、再打 tag、最后构建**（否则 tag 指向的树上没有你要发的代码）。本仓无 `.gitattributes`，故自动包 = 该 tag 全部已提交文件（gitignore 的密钥、抓包、`app_data/` 天然不在其中）。
  - 推论：§5.1 的 ③「源码包逐字节比对」对**自动包**无法执行（内容随 tag 浮动，本地没有可比对的文件）；改为在 tag 上直接核对 `git show vX.Y.Z:<路径>` 是否已脱敏即可。

## 4. 发布到 GitHub Release

本机**没有安装 `gh` CLI**，改用 REST API 脚本（**已入库 = `packaging/publish_release.py`**，正文里的路径 `%TEMP%\_rel_publish.py` 是旧口径）：

- token 从 `git credential fill`（Windows 凭据管理器）读取，**不落盘、不打印**；
- 创建 release：`POST /repos/Mxster-dll/smarter_jxufe/releases`（`tag_name` / `name` / `body` / `draft:false`）；
- 上传附件：`POST <upload_url>?name=<file>`，APK 用 `application/vnd.android.package-archive`；
- ⚠️ **`ASSETS` 列表只留两个安装包**（源码包改由 GitHub 自动生成，见 §3「源码包口径」）→ 脚本顶部那个 `ASSETS` 常量与 `BODY` 里的下载表要同步删掉源码包那一行。
- ⚠️ **TLS 坑**：本机到 `api.github.com` 的 TLS 被本地拦截器接管（系统 Root 里装了 mitmproxy CA），Python 自带的 certifi 链校验必然失败（`SSLCertVerificationError: unable to get local issuer certificate`）。脚本先用 `~/.mitmproxy/mitmproxy-ca-cert.pem` 试，失败则退化为 `verify=False`（git push 走系统证书库所以不受影响）。
- Release 正文模板见脚本里的 `BODY`：下载表（含大小与 SHA-256）、亮点、升级提示、免责声明。

## 5. 发版前的隐私检查（公开仓库，必做）

**第 0 步永远是守卫测试**（口径见 `AGENTS.md` §3.2 与 `docs/agents/34-提交前隐私纪律（公开仓库）.md`）——它是闸门，先跑它再谈别的：

```powershell
$env:FLUTTER_ROOT='<FLUTTER_ROOT>'; $env:FLUTTER_SUPPRESS_ANALYTICS='true';
$env:FLUTTER_ALREADY_LOCKED='true'
$dart = "$env:FLUTTER_ROOT\bin\cache\dart-sdk\bin\dart.exe"
$snap = "$env:FLUTTER_ROOT\bin\cache\flutter_tools.snapshot"
Remove-Item build\unit_test_assets -Recurse -Force -EA SilentlyContinue
& $dart $snap test test\privacy_guard_test.dart     # 必须绿；红了先修，别往下走
```

绿色只代表**工作树**干净；下面才是发版特有的**全历史**检查（更贵，只在发版做）：

```powershell
# ① 扫描工作树（学号 / 姓名 / GUID / enc / 手机号 / token）
python %TEMP%\_rel_scan.py
# ② 替换规则（工作树与历史共用同一份）
%TEMP%\_scrub_rules2.txt     # literal:旧==>新
# ③ 清理工作树
python %TEMP%\_rel_scrub.py
# ④ 重写全部历史并强推
Remove-Item .git\filter-repo -Recurse -Force -EA SilentlyContinue
git filter-repo --replace-text %TEMP%\_scrub_rules2.txt --force
git remote add origin https://github.com/Mxster-dll/smarter_jxufe.git
git push --force origin main; git push origin vX.Y.Z
# ⑤ 验收：以下检索必须全部为 0
git log --all --oneline -S'<敏感串>'
```

### 5.1 ⚠ 产物体检（2026-10-10 补 · 上传 Release **之前**必做）

工作树干净、历史干净，**都不代表 `dist/` 里那三个产物干净** —— 产物是**历史上某个时刻**构建的，脱敏可能发生在它之后（v1.0.0 / v2.0.0 就是如此：源码包构建于 2026-09-09 / 09-19，脱敏在 09-21，**两个旧源码包里至今躺着未脱敏的真 TGT / JSESSIONID / 身份证号**）。所以上传前必须体检产物本身。

```powershell
# 工具（与脱敏脚本同待遇：只放本机临时目录，脚本含反面样本，绝不入库）
$sz = '<7ZIP>\7z.exe'
$sd = '%TEMP%\relcheck'    # ← 体检脚本放这里，不入库

# ① APK 里有没有打包私钥（**最容易复发的一条**）
#    pubspec.yaml 的 assets 一旦写回目录形式 `assets/capture_certs/`，私钥就会进包。
#    判据不能只看「文件名在不在」，要**解出来和源文件比 sha256** —— 占位文件也会叫 leaf.key。
& $sz l dist\SmartJXUFE-vX.Y.Z-android.apk | Select-String 'capture_certs'
# 逐个条目提取（-so 输出到 stdout），与 assets/capture_certs/* 逐个比对 sha256
# 期望：ca.cer / ca.crt / leaf.crt 三个证书；**leaf.key 若出现，必须是有意为之**（见 pubspec 注释），
#       而 `ca.key` 若出现即为回归 —— 它已零引用，不该再随包分发。

# ② 源码包里有没有真凭据（把「敏感形状」按正则扫一遍，不是靠眼睛）
#    必扫形状：TGT-… / ST-… / SESSION= / JSESSIONID=（长度 ≥8）
#             18 位身份证 / 真口令字面量（如 pwd":"…"）
#    注意白名单：合成值会有意长得像真的（110101200001010010 是合法校验位的假证件号），
#    别把白名单外的命中当成误报放过，也别把合成值当成泄漏。

# ③ **源码包必须与 tag 逐字节一致** —— 这条能一次性拦住「旧包装新 tag」
& $sz l -ba -slt dist\SmartJXUFE-source-vX.Y.Z.zip     # 逐条提取 -so，算 sha256
git show vX.Y.Z:<对应路径> | 比对 sha256                # 二者必须相同
# 反例（本轮实测）：zip 内 login.http 32,390 B，而 `git show v2.0.0:reverse_engineering/login.http`
# 只有 5,983 B（已脱敏）→ 一眼看出「包比 tag 旧」，这就是 ①③ 两条要存在的理由。

# ④ 其它机械项
& $sz l dist\SmartJXUFE-source-vX.Y.Z.zip | Select-String 'app_data|\.hive|key\.properties|captures|\.mitm|\.env'
# 期望为空（git archive 天然排除未跟踪件；若非空说明打包前有文件被误提交）

# ⑤ 校验签名与版本号（原有口径，§2）
```

**三层齐了才算过关**：工作树（守卫测试）→ 全历史（`git log --all -S`）→ **产物（本节）**。只做前两层等于漏掉「包比代码旧」这个真实失效模式。

⚠ **报告纪律**：Release 正文/README 里写「不含密钥/抓包」这类话之前，**必须先用本节 ① 验过产物**。v2.0.0 的正文写了「源码包由 `git archive` 生成……不含本地抓包、密钥与构建产物」，而实测两个源码包里都有带登录态的抓包原文 —— 声明与产物不符比不说更糟。

⚠ 若产物已污染：**先删掉 Release 上的附件**（或整个 Release），删掉 `dist/` 里的旧产物（别留在原地，会被下一次发版顺手传上去），再从当前 tag 重新构建上传。已下载到别人手里的无法召回。

### 5.2 其它发版纪律与坑

- ⚠ **`git filter-repo` 会删掉 `origin`**（第 ④ 步里那句 `git remote add` 不是可选项）；仓库里若留着上一次的 `.git/filter-repo/already_ran`，它会弹交互式提示（无 stdin → `EOFError`），先移走。
- 脱敏会**改动测试输入**：`test/course_selection_des_test.dart` 的 DES 对拍期望值是按真实学号算出来的，替换输入后必须按同一实现重算期望值（文件顶部有「脱敏说明」注释）。
- ⚠️ **规则文件与扫描/脱敏脚本本身含敏感原文**（`_scrub_rules2.txt`、`_rel_scan.py`、`_rel_scrub.py`）→ 只放在 `%TEMP%`，**绝不入库**。本手册只记录做法，具体串从本地环境重建。
- 抓包原件（`reverse_engineering/saikang_tice/captures/`、`*.mitm`、`*.flows`）已在 `.gitignore` 中排除，**永远不要提交**。
- `.gitignore` 本身必须入库（曾漏跟踪，导致公开仓库里连忽略规则都没有）。
- ⚠️ **改写历史 ≠ 彻底清除**：GitHub 会保留不可达对象，旧 SHA 仍能取到内容 → 真要把旧值从远端抹掉，只能**删除并重建同名仓库**（详见 §34.7 第 5 条）。
  - **2026-10-10 实测更新（比上面那句更细）**：GitHub 保留的是**改写后**那批（已脱敏）对象 —— 旧 SHA `81ea406a…` 至今 `/commits` 仍 200、`/contents/<路径>?ref=81ea406a…` 也能取到文件，但取出来的是**脱敏后**的版本。而**改写前**的原始 SHA（如旧 tag `9882dd4d…` 对应提交）已被回收：`/commits` 与 `/git/commits` 均 **422/404**（`422` = 对象已不存在）。换言之「旧对象仍可访问」这条警告在**本例**上不成立（改写发生在 09-21，距今已过 GitHub 的回收窗口）。要复核就照这组端点试：`/repos/<owner>/<repo>/commits/<sha>` 与 `/git/commits/<sha>`。

## 6. 发版清单

- [ ] `flutter analyze` 无 error
- [ ] `flutter test --concurrency=1`（串行；已知 `test/widget_test.dart` 模板用例与 golden 用例可能受环境影响，逐个复核）
- [ ] **隐私守卫测试绿**（`test/privacy_guard_test.dart`）+ `git status` 范围核对
- [ ] 版本号两处同步（`pubspec.yaml` + `packaging/smarter_jxufe.iss`）
- [ ] README 更新（版本表、更新亮点、下载链接）
- [ ] 隐私扫描 +（必要时）历史重写
- [ ] **产物体检**（§5.1：APK 无打包私钥 / dist 产物无真凭据）
- [ ] 分组提交 → push → 打 tag → 构建 → 上传 Release（**只传两个安装包，源码包交给 GitHub 自动生成**）
- [ ] 校验 APK 签名（`CN=SmartJXUFE`）与 `versionName`
- [ ] 在真机装一次（**换签名时先卸载旧版**）
- [ ] （新克隆/新机器：先跑一次 `git config core.hooksPath .githooks` 启用提交钩子）
