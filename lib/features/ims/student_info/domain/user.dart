/// 学生完整基本信息（对应教务系统 STU_BaseInfoAction XML 响应，全字段）。
class User {
  // ── 基本信息（16 字段） ──
  final String xm; // 姓名
  final String xmpy; // 姓名拼音
  final String cym; // 曾用名
  final String xb; // 性别
  final String mz; // 民族
  final String csrq; // 出生日期
  final String csd; // 出生地
  final String sfzjh; // 身份证号
  final String sfzbm; // 身份证别码
  final String sfzzp; // 身份证照片路径
  final String sfzzm; // 身份证正面
  final String zzmm; // 政治面貌
  final String whcd; // 文化程度
  final String hkxz; // 户口性质
  final String jkzk; // 健康状况
  final String kstz; // 考生特征

  // ── 学籍信息（14 字段） ──
  final String yhxh; // 用户号（统一身份认证号）
  final String xh; // 学号
  final String rxh; // 入学号
  final String rxnj; // 入学年级
  final String xz; // 学制（年）
  final String bdtime; // 报到时间
  final String zsjj; // 招生季节
  final String rxfs; // 入学方式
  final String rxqxl; // 入学前学历
  final String pycc; // 培养层次
  final String pyfs; // 培养方式
  final String kslb; // 考生类别
  final String byzp; // 毕业照片
  final String lqzy; // 录取专业

  // ── 学院专业（8 字段） ──
  final String yxb; // 院系部
  final String zymc; // 专业名称
  final String zyfxmc; // 专业方向名称
  final String bjmc; // 班级名称
  final String xkml; // 学科门类
  final String ssjt; // 所属集团/家庭
  final String ss_mc; // 宿舍名称
  final String ssxx; // 宿舍信息

  // ── 联系方式（12 字段） ──
  final String dh; // 电话
  final String txdz; // 通讯地址
  final String yzbm; // 邮政编码
  final String dzyx; // 电子邮箱
  final String jg; // 籍贯
  final String sysf; // 生源省份
  final String syd; // 生源地
  final String sydw; // 生源地单位
  final String lxr; // 联系人
  final String jtlxr; // 家庭联系人
  final String jtlxrfs; // 家庭联系人方式
  final String ssdh; // 宿舍电话

  // ── 高考信息（10 字段） ──
  final String gkksh; // 高考考生号
  final String gkzkzh; // 高考准考证号
  final String gkzs; // 高考总分
  final String whcj; // 文化成绩
  final String kstc; // 考生特长
  final String syzy; // 生源专业
  final String zzsqlx; // 招生省市类型
  final String pydx; // 培养对象
  final String srly; // 生源来源

  // ── 其他信息（23 字段） ──
  final String fdy; // 辅导员
  final String zp; // 照片
  final String zpxsh; // 照片审核号
  final String bz; // 备注
  final String sfpk; // 是否贫困
  final String jtpklx; // 家庭贫困类型
  final String rdtsj; // 入党团时间
  final String nzsr; // 年总收入
  final String rjsr; // 人均收入
  final String xjkbh; // 学籍卡编号
  final String gat; // 公安标志
  final String hztj; // 合作途径
  final String wyyz; // 外语语种
  final String jsjdj; // 计算机等级
  final String pv8; // 时间戳1
  final String pv7; // 时间戳2
  final String xzsfzzpzmsc; // 身份证正面已扫描
  final String xzsfzzpbmsc; // 身份证反面已扫描
  final String xzbyzpsc; // 毕业照已扫描
  final String xzgkzszpsc; // 高考准考证已扫描
  final String xzrxhzpsc; // 入学合照已扫描

  const User({
    required this.xm,
    required this.xmpy,
    required this.cym,
    required this.xb,
    required this.mz,
    required this.csrq,
    required this.csd,
    required this.sfzjh,
    required this.sfzbm,
    required this.sfzzp,
    required this.sfzzm,
    required this.zzmm,
    required this.whcd,
    required this.hkxz,
    required this.jkzk,
    required this.kstz,
    required this.yhxh,
    required this.xh,
    required this.rxh,
    required this.rxnj,
    required this.xz,
    required this.bdtime,
    required this.zsjj,
    required this.rxfs,
    required this.rxqxl,
    required this.pycc,
    required this.pyfs,
    required this.kslb,
    required this.byzp,
    required this.lqzy,
    required this.yxb,
    required this.zymc,
    required this.zyfxmc,
    required this.bjmc,
    required this.xkml,
    required this.ssjt,
    required this.ss_mc,
    required this.ssxx,
    required this.dh,
    required this.txdz,
    required this.yzbm,
    required this.dzyx,
    required this.jg,
    required this.sysf,
    required this.syd,
    required this.sydw,
    required this.lxr,
    required this.jtlxr,
    required this.jtlxrfs,
    required this.ssdh,
    required this.gkksh,
    required this.gkzkzh,
    required this.gkzs,
    required this.whcj,
    required this.kstc,
    required this.syzy,
    required this.zzsqlx,
    required this.pydx,
    required this.srly,
    required this.fdy,
    required this.zp,
    required this.zpxsh,
    required this.bz,
    required this.sfpk,
    required this.jtpklx,
    required this.rdtsj,
    required this.nzsr,
    required this.rjsr,
    required this.xjkbh,
    required this.gat,
    required this.hztj,
    required this.wyyz,
    required this.jsjdj,
    required this.pv8,
    required this.pv7,
    required this.xzsfzzpzmsc,
    required this.xzsfzzpbmsc,
    required this.xzbyzpsc,
    required this.xzgkzszpsc,
    required this.xzrxhzpsc,
  });
}
