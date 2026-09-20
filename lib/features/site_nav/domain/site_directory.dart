/// 网站导航 · **全量目录表**（用户 2026-09-19 立项）。
///
/// 数据来源（2026-09-19 一轮穷尽式调研，双层核实）：
/// 1. **权威来源** = 学校官网「机构设置」三页 —— `news-list-xysz.html`（学院设置）、
///    `news-list-guanlijigou.html`（管理机构）、`news-list-keyanjigou.html` /
///    `news-list-keyanpingtai.html`（科研机构 / 科研平台），逐条抓取链接；
/// 2. **二次核实** = 对 `*.jxufe.edu.cn` / `*.jxufe.cn` 候选子域做 DNS + HTTP 探活，
///    以**实际返回的 `<title>`** 命名（凡标题与名称对不上的都已在 [CampusSite.note] 标注）。
///
/// ⚠ 三条实测口径，改动本表前先读：
/// - **别凭旧印象写学院名**：现行名与旧名单不同 —— 已无「财税与公共管理学院 / 国际经贸
///   学院 / 人文学院 / 艺术学院 / 信息管理学院 / 统计学院 / 旅游与城市管理学院」，
///   现为财政税务学院 / 公共管理学院 / 国际经济与政治学院 / 社会与人文学院 /
///   设计与艺术学院 / 信息管理与数学学院 / 统计与数据科学学院（旅游管理系并入工商管理学院）。
/// - **协议按站点实况写死**：`xk.jxufe.cn`（选课）、`hello.jxufe.edu.cn`（迎新）、
///   `mail.jxufe.edu.cn`（邮箱）、`st.jxufe.edu.cn`（实训）、`sim.jxufe.edu.cn`
///   （信息管理与数学学院）、`career.jxufe.cn` 等**只有 http 可用**（https 报 SQL 错误 /
///   握手失败 / 空壳模板），一律按本表写，别「顺手统一成 https」。
/// - **6 个「解析得到但只是学校通用空壳模板」的假站点已排除**（`bwc` / `oecmis` 首页 /
///   `bx.jxufe.edu.cn` / `lib.jxufe.edu.cn` 首页 / `sim` 的 https / `xk.jxufe.edu.cn`）；
///   `bwc.jxufe.edu.cn`（保卫处旧域）请改用 `jczzw.jxufe.edu.cn`。
///   `.cn` 与 `.edu.cn` 双域名大多互通，但 `lib.jxufe.cn`（图书资源门户）与
///   `lib.jxufe.edu.cn`（图书馆主站）是**两个不同站点**，别合并。
library;

import 'campus_site.dart';

CampusSite _collegeSite(
  String name,
  String url, {
  bool hot = false,
  String? note,
}) => CampusSite(name, url, CampusSiteCategory.college, hot: hot, note: note);

CampusSite _deptSite(String name, String url, {bool hot = false, String? note}) =>
    CampusSite(name, url, CampusSiteCategory.department, hot: hot, note: note);

CampusSite _serviceSite(
  String name,
  String url, {
  bool hot = false,
  String? note,
}) => CampusSite(name, url, CampusSiteCategory.service, hot: hot, note: note);

CampusSite _researchSite(
  String name,
  String url, {
  bool hot = false,
  String? note,
}) => CampusSite(name, url, CampusSiteCategory.research, hot: hot, note: note);

CampusSite _otherSite(String name, String url, {bool hot = false, String? note}) =>
    CampusSite(name, url, CampusSiteCategory.other, hot: hot, note: note);

/// 全量站点目录（顺序 = 页面里的排列顺序；分节见 [campusSiteSections]）。
///
/// [CampusSite.hot] 标记的 16 条 = 用户点名的那 8 条 + 每天都会点的几个系统入口
/// （统一身份认证 / 网上办事大厅 / 邮箱 / 就业网 / 网络教学平台 / 校园网与 VPN 总入口 /
/// 云盘），它们在页面里带「常用」小标，并可用「常用」筛选一键收窄。
final List<CampusSite> campusSites = [
  // ─────────────────────────── 学院与学部（29） ───────────────────────────
  _collegeSite('经济学院', 'https://econ.jxufe.edu.cn/'),
  _collegeSite('数字经济学院', 'https://szjj.jxufe.edu.cn/'),
  _collegeSite('财政税务学院', 'https://csxy.jxufe.edu.cn/'),
  _collegeSite('金融学院', 'https://finance.jxufe.edu.cn/'),
  _collegeSite(
    '国际经济与政治学院',
    'https://gmxy.jxufe.edu.cn/',
    note: '原「国际经贸学院」',
  ),
  _collegeSite('法学院（纪检监察学院）', 'https://law.jxufe.edu.cn/'),
  _collegeSite('马克思主义学院', 'https://mkszyxy.jxufe.edu.cn/'),
  _collegeSite(
    '社会与人文学院',
    'https://rwxynew.jxufe.edu.cn/',
    note: '原「人文学院」；rwxy 域名已失效',
  ),
  _collegeSite(
    '设计与艺术学院',
    'https://art.jxufe.edu.cn/',
    note: '原「艺术学院」',
  ),
  _collegeSite('外国语学院', 'https://wyxy.jxufe.edu.cn/'),
  _collegeSite(
    '国际学院',
    'https://intl.jxufe.edu.cn/',
    note: '需校园网',
  ),
  _collegeSite('国际教育学院（汉语国际推广中心）', 'https://sie.jxufe.edu.cn/'),
  _collegeSite(
    '格里菲斯数智学院',
    'https://www.jxufe.edu.cn/news-list-xysz.html',
    note: '暂无独立网站',
  ),
  _collegeSite('出国留学预备学院', 'https://liuxue.jxufe.edu.cn/'),
  _collegeSite('考文垂大学孔子学院', 'https://kzxy.jxufe.edu.cn/'),
  _collegeSite('统计与数据科学学院', 'https://stat.jxufe.edu.cn/'),
  _collegeSite(
    '工商管理学院',
    'https://business.jxufe.edu.cn/',
    note: '旅游管理系现属该院',
  ),
  _collegeSite('会计学院', 'https://kjxy.jxufe.edu.cn/'),
  _collegeSite(
    '信息管理与数学学院',
    'http://sim.jxufe.edu.cn/',
    note: '原「信息管理学院」；仅 http',
  ),
  _collegeSite('公共管理学院', 'https://ggxy.jxufe.edu.cn/'),
  _collegeSite('计算机与人工智能学院', 'https://cai.jxufe.edu.cn/'),
  _collegeSite(
    '软件与物联网工程学院',
    'https://software.jxufe.edu.cn/',
    hot: true,
  ),
  _collegeSite('虚拟现实（VR）现代产业学院', 'https://vr.jxufe.edu.cn/'),
  _collegeSite('体育学院（国防教育部）', 'https://jxcdsport.jxufe.edu.cn/'),
  _collegeSite('科技商学院', 'https://bst.jxufe.edu.cn/'),
  _collegeSite(
    '现代经济管理学院（独立学院）',
    'https://www.jcxjg.edu.cn/',
    note: '独立域名',
  ),
  _collegeSite('继续教育学院', 'https://cjxy.jxufe.edu.cn/'),
  _collegeSite('创新创业学院', 'https://cyjy.jxufe.edu.cn/'),
  _collegeSite('MPAcc 教育中心', 'https://mpacc.jxufe.edu.cn/'),

  // ─────────────────────────── 职能部门（37） ───────────────────────────
  _deptSite('党委办公室·校长办公室', 'https://xiaoban.jxufe.edu.cn/'),
  _deptSite('党委组织部', 'https://zzb.jxufe.edu.cn/'),
  _deptSite(
    '党委宣传部',
    'https://news.jxufe.edu.cn/news-list-xiaodangweixuanchuanbu.html',
    note: '无独立站，走新闻网栏目',
  ),
  _deptSite('党委统战部（机关党委）', 'https://tzb.jxufe.edu.cn/'),
  _deptSite('纪委（纪检监察组）', 'https://jiwei.jxufe.edu.cn/'),
  _deptSite('人事处·党委教师工作部', 'https://rsc.jxufe.edu.cn/'),
  _deptSite('学生工作部（处）', 'https://xgc.jxufe.edu.cn/'),
  _deptSite(
    '学工处（第二站点）',
    'https://mxgc.jxufe.edu.cn/',
    note: '与学工部内容部分重合',
  ),
  _deptSite('大学生心理健康教育与咨询中心', 'https://stuaff.jxufe.edu.cn/'),
  _deptSite('校工会', 'https://gonghui.jxufe.edu.cn/'),
  _deptSite('校团委', 'https://tw.jxufe.edu.cn/'),
  _deptSite('团委网（移动端）', 'https://mtw.jxufe.edu.cn/'),
  _deptSite('发展规划与学科建设处', 'https://fh.jxufe.edu.cn/'),
  _deptSite('教务处', 'https://jwc.jxufe.edu.cn/', hot: true),
  _deptSite('研究生院', 'https://grs.jxufe.edu.cn/', hot: true),
  _deptSite('科研处', 'https://kyc.jxufe.edu.cn/'),
  _deptSite('招生就业处', 'https://zsjyc.jxufe.edu.cn/'),
  _deptSite('本科招生网', 'https://zsjy.jxufe.edu.cn/', hot: true),
  _deptSite('国内合作处', 'https://gnhz.jxufe.edu.cn/'),
  _deptSite('国际合作与交流处', 'https://oec.jxufe.edu.cn/'),
  _deptSite('财务处', 'https://cwc.jxufe.edu.cn/'),
  _deptSite('审计处', 'https://sjc.jxufe.edu.cn/'),
  _deptSite('后勤与资产管理处', 'https://hqbzc.jxufe.edu.cn/'),
  _deptSite('资产管理处', 'http://zcgl.jxufe.edu.cn/', note: '仅 http'),
  _deptSite('校园建设处', 'https://xyjs.jxufe.edu.cn/'),
  _deptSite(
    '招标采购中心',
    'https://zbcgzx.jxufe.edu.cn/gateway.do',
    note: '官网给的入口带 gateway.do',
  ),
  _deptSite('离退休人员工作处', 'https://ltxc.jxufe.edu.cn/'),
  _deptSite(
    '保卫工作部（处）、人武部',
    'https://jczzw.jxufe.edu.cn/',
    note: 'bwc 域名为空壳，勿用',
  ),
  _deptSite(
    '科技与信息化中心',
    'https://nic.jxufe.edu.cn/',
    hot: true,
    note: '校园网 / 邮箱 / VPN 总入口',
  ),
  _deptSite('评价中心', 'https://jxpg.jxufe.edu.cn/'),
  _deptSite('档案管理中心', 'https://dag.jxufe.edu.cn/'),
  _deptSite('校友联络服务中心', 'https://xiaoyouban.jxufe.edu.cn/'),
  _deptSite('校医院', 'https://xyy.jxufe.edu.cn/'),
  _deptSite('附属中学', 'https://cdfz.jxufe.edu.cn/'),
  _deptSite('博士后流动站', 'https://bogb.jxufe.edu.cn/'),
  _deptSite(
    '人才招聘系统',
    'https://jxcdhr.jxufe.edu.cn/zp.html#/',
    note: '人事处招聘门户',
  ),
  _deptSite(
    '经济管理与创业模拟实验教学中心',
    'https://emlab.jxufe.edu.cn/',
  ),

  // ─────────────────────────── 服务系统（23） ───────────────────────────
  _serviceSite(
    '综合服务门户（智慧江财）',
    'https://ehall.jxufe.edu.cn/',
    hot: true,
    note: '一站式服务大厅',
  ),
  _serviceSite(
    '网上办事大厅',
    'https://onestop.jxufe.edu.cn/',
    hot: true,
    note: '与智慧江财是两个系统',
  ),
  _serviceSite(
    '统一身份认证',
    'https://ssl.jxufe.edu.cn/cas/login',
    hot: true,
    note: '全校 SSO 网关',
  ),
  _serviceSite(
    '教务管理系统',
    'https://jwxt.jxufe.edu.cn/',
    hot: true,
    note: '成绩 · 课表 · 校历',
  ),
  _serviceSite(
    '教学管理服务平台（选课）',
    'http://xk.jxufe.cn/',
    hot: true,
    note: '仅 http',
  ),
  _serviceSite(
    '研究生招生系统',
    'http://yjszs.jxufe.edu.cn/',
    note: '仅 http，跳统一认证',
  ),
  _serviceSite(
    '学生活动时长统计',
    'http://ssp.jxufe.edu.cn/',
    note: '志愿时长登记',
  ),
  _serviceSite(
    '网络教学平台（学习通）',
    'https://jxufe.fanya.chaoxing.com/portal',
    hot: true,
    note: '超星泛雅，外部域名',
  ),
  _serviceSite(
    '慕课平台',
    'https://jxufe.mooc.chaoxing.com/',
    note: '超星，外部域名',
  ),
  _serviceSite(
    '一体化在线教学实训系统',
    'http://st.jxufe.edu.cn/',
    note: 'OJ / GitLab；仅 http',
  ),
  _serviceSite(
    '实验教学平台',
    'https://lms.jxufe.edu.cn/',
    note: '需登录后才有内容',
  ),
  _serviceSite('江财云盘', 'http://pan.jxufe.cn/', note: '仅 http'),
  _serviceSite(
    '网络自助服务（上网认证）',
    'http://bx.jxufe.cn/',
    note: '校园网登录 / 自助',
  ),
  _serviceSite(
    '学生 / 教工邮箱',
    'http://mail.jxufe.edu.cn/',
    hot: true,
    note: '仅 http；校外多不可达',
  ),
  _serviceSite(
    'VPN / WebVPN',
    'https://vpn.jxufe.edu.cn/',
    note: '需校内或特定网络',
  ),
  _serviceSite('就业信息网', 'https://career.jxufe.edu.cn/', hot: true),
  _serviceSite(
    '迎新网',
    'http://hello.jxufe.edu.cn/',
    hot: true,
    note: '仅 http',
  ),
  _serviceSite('图书馆', 'https://lib.jxufe.edu.cn/', hot: true),
  _serviceSite(
    '图书馆 · 图书资源门户',
    'http://lib.jxufe.cn/',
    note: '与图书馆主站是两个站点',
  ),
  _serviceSite(
    '国际化信息系统',
    'http://oecmis.jxufe.edu.cn/',
    note: '需登录',
  ),
  _serviceSite('百业大调查平台', 'https://dc.jxufe.edu.cn/'),
  _serviceSite(
    '国家大学生就业服务平台 · 江财专页',
    'https://jxufe.ncss.cn/',
    note: '国家级平台',
  ),

  // ─────────────────────────── 科研机构（38） ───────────────────────────
  _researchSite(
    '财经数据科学实验室（教育部哲社）',
    'https://czdsj.jxufe.edu.cn/',
  ),
  _researchSite('计算社会科学实验室', 'https://jsshkx.jxufe.edu.cn/'),
  _researchSite('财经大数据教育部工程研究中心', 'https://finbd.jxufe.edu.cn/'),
  _researchSite(
    '大湖流域国土空间生态保护修复工程技术创新中心',
    'https://dhzx.jxufe.edu.cn/',
    note: '自然资源部',
  ),
  _researchSite('多媒体智能处理江西省重点实验室', 'https://mip.jxufe.edu.cn/'),
  _researchSite('数据与知识工程重点实验室', 'https://dke.jxufe.edu.cn/'),
  _researchSite('区域国别研究院', 'https://ias.jxufe.edu.cn/'),
  _researchSite('国势研究院', 'http://ios.jxufe.edu.cn/', note: '仅 http'),
  _researchSite(
    '中国当代国势学数据研究平台',
    'https://guoshi.jxufe.edu.cn/#/home',
  ),
  _researchSite(
    '中国宏观经济监测预测与政策评估分析平台',
    'https://macroeco.jxufe.edu.cn/',
  ),
  _researchSite(
    '应用统计研究中心（超越 GDP 统计研究院）',
    'http://beyondgdp.jxufe.edu.cn/',
  ),
  _researchSite('数量经济研究所', 'https://iqe.jxufe.edu.cn/'),
  _researchSite('生态经济研究院', 'https://eeconomics.jxufe.edu.cn/'),
  _researchSite('生态文明研究院', 'https://stwm.jxufe.edu.cn/'),
  _researchSite(
    '江西省经济预测与决策研究中心',
    'http://efdrc.jxufe.edu.cn/',
  ),
  _researchSite('会计发展研究中心', 'http://kfzx.jxufe.edu.cn/'),
  _researchSite(
    '金融发展与风险防范研究中心',
    'http://jrfxyjzx.jxufe.edu.cn/',
  ),
  _researchSite('财税研究中心', 'http://csyjzx.jxufe.edu.cn/'),
  _researchSite('产业集群与企业发展研究中心', 'http://qyzx.jxufe.edu.cn/'),
  _researchSite('规制与竞争研究中心', 'http://cygz.jxufe.edu.cn/'),
  _researchSite(
    '绿色发展与中国式现代化研究网',
    'https://gdcpmrc.jxufe.edu.cn/',
  ),
  _researchSite('现代产业发展研究院', 'https://zkjszx.jxufe.edu.cn/'),
  _researchSite(
    '江西全面建成小康社会决策支持协同创新中心',
    'http://xkxtzx.jxufe.edu.cn/',
  ),
  _researchSite(
    '法治江西网（江西法治政府研究中心）',
    'http://fzjx.jxufe.edu.cn/',
  ),
  _researchSite('社会工作政策理论研究基地', 'https://swpt.jxufe.edu.cn/'),
  _researchSite(
    '江西省电子商务企业服务产业技术工程化中心',
    'https://eb.jxufe.edu.cn/',
  ),
  _researchSite('红色故事收集整理与研究中心', 'https://hszx.jxufe.edu.cn/'),
  _researchSite(
    '江西省非物质文化遗产研究基地',
    'https://ich.jxufe.edu.cn/',
  ),
  _researchSite(
    '江西省文化艺术科学重点研究基地',
    'https://cas.jxufe.edu.cn/',
  ),
  _researchSite('“一带一路”研究院', 'http://brri.jxufe.edu.cn/'),
  _researchSite('数据法律研究院', 'https://idl.jxufe.edu.cn/'),
  _researchSite('司法鉴定中心', 'https://jcsj.jxufe.edu.cn/'),
  _researchSite('人工智能评测研究院', 'https://jxaiqtc.jxufe.edu.cn/'),
  _researchSite('高等教育研究所', 'https://gjs.jxufe.edu.cn/'),
  _researchSite('深圳研究院', 'https://shenzhen.jxufe.edu.cn/'),
  _researchSite('北京高等研究院', 'http://bjgdyjy.jxufe.edu.cn/'),
  _researchSite('上海高等研究院', 'https://shgdyjy.jxufe.edu.cn/'),
  _researchSite('赣州研究院', 'http://ganzhou.jxufe.edu.cn/'),

  // ─────────────────────────── 其他站点（11） ───────────────────────────
  _otherSite('学校官网', 'https://www.jxufe.edu.cn/', hot: true),
  _otherSite(
    '学校官网（旧域 · 全站检索）',
    'http://www.jxufe.cn/',
    note: '301 到官网主域',
  ),
  _otherSite('学校官网（手机版）', 'https://m.jxufe.edu.cn/'),
  _otherSite('新闻网', 'https://news.jxufe.edu.cn/'),
  _otherSite('新闻网（手机版）', 'https://mnews.jxufe.edu.cn/'),
  _otherSite('英文站（JUFE）', 'http://english.jxufe.edu.cn/', note: '仅 http'),
  _otherSite('国际生教育英文站', 'https://oesenglish.jxufe.edu.cn/'),
  _otherSite('当代财经杂志社', 'https://cfe.jxufe.edu.cn/'),
  _otherSite(
    '《当代财经》期刊',
    'http://cfejxufe.magtech.com.cn/ddcj/CN/1005-0892/home.shtml',
    note: '期刊平台（外部域名）',
  ),
  _otherSite(
    '《江西财经大学学报》期刊',
    'http://cfejxufe.magtech.com.cn/xb/CN/1008-2972/home.shtml',
    note: '期刊平台（外部域名）',
  ),
  _otherSite('江西华财资产经营有限公司', 'https://zsw.jxufe.edu.cn/'),
];
