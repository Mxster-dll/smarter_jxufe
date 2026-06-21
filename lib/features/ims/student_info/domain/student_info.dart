class StudentInfo {
  final String name; // 姓名 <xm>
  final String namePinyin; // 姓名拼音 <xmpy>
  final String formerName; // 曾用名 <cym>
  final String gender; // 性别 <xb>
  final String ethnicity; // 民族 <mz>
  final String birthDate; // 出生日期 <csrq>
  final String birthPlace; // 出生地 <csd>

  final String idCardNo; // 身份证号 <sfzjh>
  final String idCardAltCode; // 身份证别码 <sfzbm>
  final String idPhotoPath; // 身份证照片路径 <sfzzp>
  final String idPhotoFront; // 身份证正面 <sfzzm>

  final String politicalStatus; // 政治面貌 <zzmm>
  final String educationLevel; // 文化程度 <whcd>
  final String residenceType; // 户口性质 <hkxz>
  final String healthStatus; // 健康状况 <jkzk>
  final String examineeFeature; // 考生特征 <kstz>

  final String userId; // 用户号（统一身份认证号）<yhxh>
  final String studentId; // 学号 <bz>
  final String serialNo; // 序号 <xh>
  final String enrollNo; // 入学号 <rxh>

  final String enrollYear; // 入学年级 <rxnj>
  final String studyYears; // 学制（年）<xz>
  final String enrollDate; // 报到时间 <bdtime>
  final String enrollSeason; // 招生季节 <zsjj>
  final String enrollMethod; // 入学方式 <rxfs>
  final String prevEducation; // 入学前学历 <rxqxl>
  final String trainLevel; // 培养层次 <pycc>
  final String trainMode; // 培养方式 <pyfs>
  final String examineeType; // 考生类别 <kslb>
  final String admittedMajor; // 录取专业 <lqzy>

  final String college; // 院系部 <yxb>
  final String major; // 专业名称 <zymc>
  final String majorDirection; // 专业方向名称 <zyfxmc>
  final String className; // 班级名称 <bjmc>
  final String disciplineCategory; // 学科门类 <xkml>

  final String dormName; // 宿舍名称 <ss_mc>
  final String dormInfo; // 宿舍信息 <ssxx>

  final String phone; // 电话 <dh>
  final String email; // 电子邮箱 <dzyx>
  final String address; // 通讯地址 <txdz>
  final String postalCode; // 邮政编码 <yzbm>
  final String hometown; // 籍贯 <jg>
  final String originProvince; // 生源省份 <sysf>
  final String originPlace; // 生源地 <syd>
  final String originUnit; // 生源地单位 <sydw>

  final String contactPerson; // 联系人 <lxr>
  final String familyContact; // 家庭联系人 <jtlxr>
  final String familyContactPhone; // 家庭联系人方式 <jtlxrfs>
  final String dormPhone; // 宿舍电话 <ssdh>

  final String gaokaoNo; // 高考考生号 <gkksh>
  final String gaokaoTicketNo; // 高考准考证号 <gkzkzh>
  final String gaokaoScore; // 高考总分 <gkzs>
  final String cultureScore; // 文化成绩 <whcj>
  final String examineeTalent; // 考生特长 <kstc>
  final String originMajor; // 生源专业 <syzy>
  final String admissionType; // 招生省市类型 <zzsqlx>
  final String trainTarget; // 培养对象 <pydx>
  final String originSource; // 生源来源 <srly>

  final String advisor; // 辅导员 <fdy>
  final String photo; // 照片 <zp>
  final String photoReviewNo; // 照片审核号 <zpxsh>
  final String isPoor; // 是否贫困 <sfpk>
  final String povertyType; // 贫困类型 <jtpklx>
  final String partyJoinDate; // 入党团时间 <rdtsj>
  final String annualIncome; // 年总收入 <nzsr>
  final String perCapitaIncome; // 人均收入 <rjsr>
  final String registryNo; // 学籍卡编号 <xjkbh>
  final String foreignLanguage; // 外语语种 <wyyz>
  final String computerLevel; // 计算机等级 <jsjdj>
  final String groupInfo; // 所属集团 <ssjt>
  final String graduationPhoto; // 毕业照片 <byzp>

  final String publicSecurity; // 公安 <gat>
  final String cooperationPath; // 合作途径 <hztj>
  final String timestamp1; // 时间戳1 <pv8>
  final String timestamp2; // 时间戳2 <pv7>
  final String idFrontScanned; // 身份证正面已扫描 <xzsfzzpzmsc>
  final String idBackScanned; // 身份证反面已扫描 <xzsfzzpbmsc>
  final String graduationPhotoScanned; // 毕业照已扫描 <xzbyzpsc>
  final String gaokaoTicketScanned; // 高考准考证已扫描 <xzgkzszpsc>
  final String enrollPhotoScanned; // 入学合照已扫描 <xzrxhzpsc>

  const StudentInfo({
    required this.name,
    required this.namePinyin,
    required this.formerName,
    required this.gender,
    required this.ethnicity,
    required this.birthDate,
    required this.birthPlace,
    required this.idCardNo,
    required this.idCardAltCode,
    required this.idPhotoPath,
    required this.idPhotoFront,
    required this.politicalStatus,
    required this.educationLevel,
    required this.residenceType,
    required this.healthStatus,
    required this.examineeFeature,
    required this.userId,
    required this.studentId,
    required this.serialNo,
    required this.enrollNo,
    required this.enrollYear,
    required this.studyYears,
    required this.enrollDate,
    required this.enrollSeason,
    required this.enrollMethod,
    required this.prevEducation,
    required this.trainLevel,
    required this.trainMode,
    required this.examineeType,
    required this.admittedMajor,
    required this.college,
    required this.major,
    required this.majorDirection,
    required this.className,
    required this.disciplineCategory,
    required this.dormName,
    required this.dormInfo,
    required this.phone,
    required this.email,
    required this.address,
    required this.postalCode,
    required this.hometown,
    required this.originProvince,
    required this.originPlace,
    required this.originUnit,
    required this.contactPerson,
    required this.familyContact,
    required this.familyContactPhone,
    required this.dormPhone,
    required this.gaokaoNo,
    required this.gaokaoTicketNo,
    required this.gaokaoScore,
    required this.cultureScore,
    required this.examineeTalent,
    required this.originMajor,
    required this.admissionType,
    required this.trainTarget,
    required this.originSource,
    required this.advisor,
    required this.photo,
    required this.photoReviewNo,
    required this.isPoor,
    required this.povertyType,
    required this.partyJoinDate,
    required this.annualIncome,
    required this.perCapitaIncome,
    required this.registryNo,
    required this.foreignLanguage,
    required this.computerLevel,
    required this.groupInfo,
    required this.graduationPhoto,
    required this.publicSecurity,
    required this.cooperationPath,
    required this.timestamp1,
    required this.timestamp2,
    required this.idFrontScanned,
    required this.idBackScanned,
    required this.graduationPhotoScanned,
    required this.gaokaoTicketScanned,
    required this.enrollPhotoScanned,
  });
}
