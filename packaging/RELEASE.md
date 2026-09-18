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
| keystore | `D:\Keys\smarter_jxufe-release.jks`（PKCS12，RSA 4096，有效期 30 年，别名 `smarter_jxufe`） |
| 口令与配置 | `D:\Keys\keystore.properties`（备份说明见同目录 `README-签名备份.txt`） |
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
$dart = 'D:\Program\flutter\bin\cache\dart-sdk\bin\dart.exe'
$snap = 'D:\Program\flutter\bin\cache\flutter_tools.snapshot'
$env:FLUTTER_ROOT='D:\Program\flutter'; $env:FLUTTER_SUPPRESS_ANALYTICS='true'; $env:FLUTTER_ALREADY_LOCKED='true'

Get-Process smarter_jxufe,MSBuild,VBCSCompiler,dart -EA SilentlyContinue | Stop-Process -Force
attrib -R build\flutter_assets\* /S /D 2>$null; Remove-Item build\flutter_assets -Recurse -Force -EA SilentlyContinue

& $dart $snap build apk --release        # → build/app/outputs/flutter-apk/app-release.apk
attrib -R build\flutter_assets\* /S /D 2>$null; Remove-Item build\flutter_assets -Recurse -Force -EA SilentlyContinue
& $dart $snap build windows --release    # → build/windows/x64/runner/Release/
& 'D:\Program\Inno\ISCC.exe' packaging\smarter_jxufe.iss   # → dist/SmartJXUFE-vX.Y.Z-windows.exe

New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\SmartJXUFE-vX.Y.Z-android.apk -Force
git archive --format=zip --prefix=SmartJXUFE-vX.Y.Z/ -o dist\SmartJXUFE-source-vX.Y.Z.zip HEAD
```

- **切换构建目标前必须删 `build\flutter_assets`**（该目录的增量拷贝非幂等 → `MSB8066 flutter_assemble.rule exited with code 1`）。
- 源码包用 `git archive` → 只含已提交内容，天然排除抓包、密钥与构建产物，且与 tag 一一对应；**因此必须先提交、再打 tag、最后打包**。

## 4. 发布到 GitHub Release

本机**没有安装 `gh` CLI**，改用 REST API 脚本（脚本在 `D:\Temp\_rel_publish.py`，可复制到 `packaging/` 备查）：

- token 从 `git credential fill`（Windows 凭据管理器）读取，**不落盘、不打印**；
- 创建 release：`POST /repos/Mxster-dll/smarter_jxufe/releases`（`tag_name` / `name` / `body` / `draft:false`）；
- 上传附件：`POST <upload_url>?name=<file>`，APK 用 `application/vnd.android.package-archive`；
- ⚠️ **TLS 坑**：本机到 `api.github.com` 的 TLS 被本地拦截器接管（系统 Root 里装了 mitmproxy CA），Python 自带的 certifi 链校验必然失败（`SSLCertVerificationError: unable to get local issuer certificate`）。脚本先用 `~/.mitmproxy/mitmproxy-ca-cert.pem` 试，失败则退化为 `verify=False`（git push 走系统证书库所以不受影响）。
- Release 正文模板见脚本里的 `BODY`：下载表（含大小与 SHA-256）、亮点、升级提示、免责声明。

## 5. 发版前的隐私检查（公开仓库，必做）

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

- 脱敏会**改动测试输入**：`test/course_selection_des_test.dart` 的 DES 对拍期望值是按真实学号算出来的，替换输入后必须按同一实现重算期望值（文件顶部有「脱敏说明」注释）。
- ⚠️ **规则文件与扫描/脱敏脚本本身含敏感原文**（`_scrub_rules2.txt`、`_rel_scan.py`、`_rel_scrub.py`）→ 只放在 `%TEMP%`，**绝不入库**。本手册只记录做法，具体串从本地环境重建。
- 抓包原件（`reverse_engineering/saikang_tice/captures/`、`*.mitm`、`*.flows`）已在 `.gitignore` 中排除，**永远不要提交**。
- `.gitignore` 本身必须入库（曾漏跟踪，导致公开仓库里连忽略规则都没有）。

## 6. 发版清单

- [ ] `flutter analyze` 无 error
- [ ] `flutter test --concurrency=1`（串行；已知 `test/widget_test.dart` 模板用例与 golden 用例可能受环境影响，逐个复核）
- [ ] 版本号两处同步（`pubspec.yaml` + `packaging/smarter_jxufe.iss`）
- [ ] README 更新（版本表、更新亮点、下载链接）
- [ ] 隐私扫描 +（必要时）历史重写
- [ ] 分组提交 → push → 打 tag → 构建 → 上传 Release
- [ ] 校验 APK 签名（`CN=SmartJXUFE`）与 `versionName`
- [ ] 在真机装一次（**换签名时先卸载旧版**）
