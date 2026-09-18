# -*- coding: utf-8 -*-
"""创建 GitHub Release 并上传三个产物（APK / Windows 安装包 / 源码包）。

token 从 git credential manager 读取，绝不打印到输出。
用法：python D:\\Temp\\_rel_publish.py
"""
import hashlib
import json
import mimetypes
import os
import subprocess
import sys

import requests
import urllib3

urllib3.disable_warnings()
sys.stdout.reconfigure(encoding='utf-8')

REPO = 'Mxster-dll/smarter_jxufe'
REPO_DIR = r'D:\Project\Ongoing\smarter_jxufe'
TAG = 'v2.0.0'
DIST = os.path.join(REPO_DIR, 'dist')
ASSETS = [
    ('SmartJXUFE-v2.0.0-android.apk', 'application/vnd.android.package-archive'),
    ('SmartJXUFE-v2.0.0-windows.exe', 'application/octet-stream'),
    ('SmartJXUFE-source-v2.0.0.zip', 'application/zip'),
]


def token():
    p = subprocess.run(['git', 'credential', 'fill'], cwd=REPO_DIR, input='protocol=https\nhost=github.com\n\n',
                       capture_output=True, text=True, encoding='utf-8')
    for line in p.stdout.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1].strip()
    sys.exit('未取到 GitHub token')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest().upper()


def human(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if n < 1024 or unit == 'GB':
            return f'{n:.1f} {unit}' if unit != 'B' else f'{n} B'
        n /= 1024


TOKEN = token()
S = requests.Session()
S.trust_env = False

# 本机到 GitHub 的 TLS 被本地拦截器接管（mitmproxy CA 已装系统 Root，Python 的 certifi
# 不认它）→ 优先用拦截器 CA 校验；不可用再退化为不校验（本项目一贯做法）。
VERIFY = False
_mitm = os.path.join(os.path.expanduser('~'), '.mitmproxy', 'mitmproxy-ca-cert.pem')
if os.path.exists(_mitm):
    try:
        if requests.get('https://api.github.com/', timeout=20, verify=_mitm,
                        headers={'User-Agent': 'curl/8'}).status_code == 200:
            VERIFY = _mitm
            print('TLS: 使用 mitmproxy CA 校验')
    except Exception:
        pass
if VERIFY is False:
    print('TLS: 退化为不校验（verify=False）')
H = {'Authorization': f'Bearer {TOKEN}', 'Accept': 'application/vnd.github+json',
     'X-GitHub-Api-Version': '2022-11-28'}

me = S.get('https://api.github.com/user', headers=H, timeout=30, verify=VERIFY)
print('auth:', me.status_code, me.json().get('login') if me.status_code == 200 else me.text[:200])
if me.status_code != 200:
    sys.exit('token 无效或无权限')

rels = S.get(f'https://api.github.com/repos/{REPO}/releases', headers=H, timeout=30, verify=VERIFY).json()
print('已存在的 release:', [(r['tag_name'], r['name']) for r in rels] if isinstance(rels, list) else rels)

rows = []
for name, _ in ASSETS:
    p = os.path.join(DIST, name)
    if not os.path.exists(p):
        sys.exit(f'缺少产物: {p}')
    rows.append((name, os.path.getsize(p), sha256(p)))
    print(f'  {name}  {human(os.path.getsize(p))}  sha256={rows[-1][2][:16]}…')

BODY = f'''江西财经大学「智慧江财」增强客户端 **v2.0.0** —— 首个正式发行版（正式签名）。

## 下载

| 平台 | 文件 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| Android 8.0+ | `{rows[0][0]}` | {human(rows[0][1])} | `{rows[0][2]}` |
| Windows x64 | `{rows[1][0]}` | {human(rows[1][1])} | `{rows[1][2]}` |
| 源码 | `{rows[2][0]}` | {human(rows[2][1])} | `{rows[2][2]}` |

> ⚠️ **从 v1.0.0 升级请先卸载旧版**：v1.0.0 系列为调试签名，v2.0.0 起改用正式签名（RSA 4096），两者无法互相覆盖安装。
> Windows 安装包免管理员权限（装到用户目录），会自动创建桌面与开始菜单快捷方式。

## 本版亮点

**AI 助手（新）** —— 内置大模型对话（OpenAI 兼容，8 家服务商可切换），**19 个函数调用工具**覆盖成绩、课表、培养方案、学籍、公共查询、无课时间、校规检索、分数估计、综测、材料、志愿、校历、电费网费与设置；回答支持 Markdown；只读为主、写操作二次确认；宫格与侧栏第一格入口 + 移动端全局悬浮球。

**深色模式（新）** —— 跟随系统 / 浅色 / 深色三档；全应用语义色、课表十二色课程块与 Android 桌面小组件均按深浅两套色板适配。

**主页与课表改版** —— 手机端定宽自适应宫格 / 桌面端左侧导航栏 + 右侧内嵌页面；首页「数据一览」+ 今日课程 12 节时间轴（连续课合并、大间隔自动画分隔线）；课表新增学期码 `xxy` 阵列选择器、周数选择器、拖动翻页（表头固定 + 节数列淡出）、作息时间、周六周日开关。

**综合测评与材料库** —— 总评改为五育加权（占比自行设置，默认 20/35/15/15/15）；智育加权与志愿时长按学年自动带入；竞赛标注「计入总分」；外语证书按表 10 档位识别；材料库两级选择向导（160+ 竞赛、13 类外语证书）+ 按二级分类分组 + 附件留档。

**阅读** —— 新生入馆教育原生闯关（五章地图 + 答题 + 后门模式一键通过）；蛟湖阅读四部分进度（实际 / 服务端双档）；畅想之星「经典阅读」分类书架 + **原生 PDF 阅读器**（逐页解密渲染、进度云同步、**阅读时长如实计入平台统计**）+ 逐书阅读报告。

**其他** —— 桌面小组件扩到 24 个（3 指标 × 8 档尺寸）；新增网上选课、公共查询、上课实况窗、本科生成绩单申请、网络服务、我的邮箱、请假记录、校区地图；全局设置入口常驻各页标题栏且只显示本页相关设置节。

## 说明

- 本项目为**个人开发的非官方项目**，与江西财经大学无隶属关系；接口基于公开渠道与个人逆向分析，仅供学习交流，请勿商用。
- 需使用学校统一身份认证（CAS）登录；部分实时数据源（校园网 / 请假 / 校历官方安排）需在「设置 → 平台标识」按向导配置一次微信平台 GUID。
- 源码包由 `git archive` 生成，与本 tag 一一对应（不含本地抓包、密钥与构建产物）。
'''

payload = {'tag_name': TAG, 'name': f'SmartJXUFE v2.0.0', 'body': BODY,
           'draft': False, 'prerelease': False}
r = S.post(f'https://api.github.com/repos/{REPO}/releases', headers=H, data=json.dumps(payload), timeout=60, verify=VERIFY)
print('create release:', r.status_code)
if r.status_code >= 300:
    print(r.text[:600])
    sys.exit(1)
rel = r.json()
rel_id, upload_url = rel['id'], rel['upload_url'].split('{')[0]
print('release id:', rel_id, '|', rel['html_url'])

for name, ctype in ASSETS:
    p = os.path.join(DIST, name)
    with open(p, 'rb') as f:
        up = S.post(f'{upload_url}?name={name}', headers={**H, 'Content-Type': ctype}, data=f, timeout=1800, verify=VERIFY)
    print(f'  upload {name}: {up.status_code}', up.json().get('browser_download_url') if up.status_code < 300 else up.text[:200])

final = S.get(f'https://api.github.com/repos/{REPO}/releases/{rel_id}', headers=H, timeout=30, verify=VERIFY).json()
print('\n=== Release 就绪 ===')
print(final['html_url'])
for a in final['assets']:
    print(f"  {a['name']}  {human(a['size'])}  downloads={a['download_count']}")

