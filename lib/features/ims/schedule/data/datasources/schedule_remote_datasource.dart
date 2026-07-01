import 'package:dio/dio.dart';

class ScheduleRemoteDataSource {
  final Dio _dio;

  ScheduleRemoteDataSource(this._dio);

  Future<String> getScheduleInTableHtml() async {
    return """










<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
	<head>
		<title></title>
		<meta http-equiv="Content-Language" content="zh-cn" />
		<meta http-equiv="Content-Type" content="text/html; charset=GBK" />

		<link rel="stylesheet" href="../css/Print.css" type="text/css" />
		<script type="text/JavaScript">
			var _config_ = {
				pageSize : "A4",
				orientation : "L",
				top : 0,
				bottom : 20,
				left : 10,
				right : 10
			}
		</script>
		<script language='javascript' type='text/javascript' src='../js/Print.js'></script>
	</head>
	<body style="font-size:12px">
		<div pagetitle="pagetitle" style="width:256mm;font-size:20px;font-weight:bold;" align="center">
			江西财经大学学生个人课表
			<div style="font-size:12px;font-weight:bold;">2025-2026学年第二学期</div>
		</div>

		
		<div group="group" style="width:256mm;text-align:left;font-size:12px;font-weight:normal;">
			<div style="float:left;">
				学号：REDACTED_USERNAME
				&ensp;&ensp;
				姓名：陈煜仕
				&ensp;&ensp;
				所在班级：计算机科学与技术252
			</div>
			<div style="float:right;">
				课程门数：12&ensp;
				课程学分：31.0(未处理学分：0.0)&ensp;
				环节学分：0.0&ensp;
				本学期修读总学分：31.0&ensp;&ensp;
			</div>
		</div>
		<table style="clear:left;width:256mm;font-size:12px">
			<thead>
				<tr>
					<td style="text-align:center;width: 10%">上课班级<br>代码</td>
					<td style="width:10%;text-align:center;">上课班级<br>名称</td>
					<td style="text-align:center;width: 22%">课程</td>
					<td style="text-align:center;width: 4%">总<br>学时</td>
					<td style="text-align:center;width: 4%">学分</td>
					<td style="text-align:center;width: 4%">修读<br>性质</td>
					
					<td style="text-align:center;width: 15%">任课教师</td>
					
					<td style="text-align:center;width: 4%">选课<br>状态</td>
					
					<td style="width:8%;text-align:center;">外年级/专业<br>选课</td>
					
					<td style="text-align:center;width: 4%">教材</td>
					
					<td style="text-align:center;width: 15%">上课时间地点</td>
					
					<td style="text-align:center;width: 8%">备注</td>
				</tr>
			</thead>
			<tbody>
				
				<tr>
					<td style="text-align:center;" hidevalue="001567-056">001567-056</td>
					<td style="text-align:left;" hidevalue="主干+">主干+</td>
					<td style="text-align:left;">[1004600282]大学英语II</td>
					<td style="text-align:right;">32</td>
					<td style="text-align:right;">2.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200400772]史希平</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 四[3-4] 麦三教3207(70)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr0_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr0_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr0_kcdm" name="kcdm" style="display: none">001567</td>
					<td id="tr0_skbjdm" name="skbjdm" style="display: none">001567-056</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="002005-023">002005-023</td>
					<td style="text-align:left;" hidevalue="主干+">主干+</td>
					<td style="text-align:left;">[1004701096]高等数学II</td>
					<td style="text-align:right;">96</td>
					<td style="text-align:right;">6.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200400880]俞丽兰</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 一[10-12] 麦三教3303(101),1-16周 三[3-5] 麦三教3304(140)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr1_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr1_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr1_kcdm" name="kcdm" style="display: none">002005</td>
					<td id="tr1_skbjdm" name="skbjdm" style="display: none">002005-023</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="2020880-023">2020880-023</td>
					<td style="text-align:left;" hidevalue=""></td>
					<td style="text-align:left;">[1004907141]写作与沟通I</td>
					<td style="text-align:right;">24</td>
					<td style="text-align:right;">1.5</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1202300009]王柳芳</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-12周 一[3-4] 麦三教3310(70)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr2_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr2_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr2_kcdm" name="kcdm" style="display: none">2020880</td>
					<td id="tr2_skbjdm" name="skbjdm" style="display: none">2020880-023</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="003399-124">003399-124</td>
					<td style="text-align:left;" hidevalue="本科新生+乒乓球">本科新生+乒乓球</td>
					<td style="text-align:left;">[1005000651]体育2</td>
					<td style="text-align:right;">32</td>
					<td style="text-align:right;">1.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200402593]彭永善</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:left;">1-16周 五[3-4] 麦乒乓球场T021(40)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr3_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr3_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr3_kcdm" name="kcdm" style="display: none">003399</td>
					<td id="tr3_skbjdm" name="skbjdm" style="display: none">003399-124</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="2020342-008">2020342-008</td>
					<td style="text-align:left;" hidevalue=""></td>
					<td style="text-align:left;">[1005401103]大学物理</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200402760]余泉茂</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 四[6-8] 麦二教2103(108)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr4_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr4_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr4_kcdm" name="kcdm" style="display: none">2020342</td>
					<td id="tr4_skbjdm" name="skbjdm" style="display: none">2020342-008</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="004699-022">004699-022</td>
					<td style="text-align:left;" hidevalue="思政+">思政+</td>
					<td style="text-align:left;">[1012100193]中国近现代史纲要</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200402628]吴通福</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 二[3-5] 麦三教3203(101)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr5_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr5_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr5_kcdm" name="kcdm" style="display: none">004699</td>
					<td id="tr5_skbjdm" name="skbjdm" style="display: none">004699-022</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="2020773-044">2020773-044</td>
					<td style="text-align:left;" hidevalue="思政+">思政+</td>
					<td style="text-align:left;">[1012100350]形势与政策II</td>
					<td style="text-align:right;">8</td>
					<td style="text-align:right;">0.5</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1202000078]谢尔艾力.库尔班</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">13-16周 三[6-7] 麦三教3403(101)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr6_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr6_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr6_kcdm" name="kcdm" style="display: none">2020773</td>
					<td id="tr6_skbjdm" name="skbjdm" style="display: none">2020773-044</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="1012100483-047">1012100483-047</td>
					<td style="text-align:left;" hidevalue="思政+">思政+</td>
					<td style="text-align:left;">[1012100483]毛泽东思想和中国特色社会主义理论体系概论</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1202000109]康立芳</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 二[6-8] 麦三教3303(101)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr7_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr7_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr7_kcdm" name="kcdm" style="display: none">1012100483</td>
					<td id="tr7_skbjdm" name="skbjdm" style="display: none">1012100483-047</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="1012100493-034">1012100493-034</td>
					<td style="text-align:left;" hidevalue="思政+">思政+</td>
					<td style="text-align:left;">[1012100493]习近平新时代中国特色社会主义思想概论</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200401015]徐腊梅</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 五[6-8] 麦三教3202(101)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr8_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr8_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr8_kcdm" name="kcdm" style="display: none">1012100493</td>
					<td id="tr8_skbjdm" name="skbjdm" style="display: none">1012100493-034</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="1014300272-003">1014300272-003</td>
					<td style="text-align:left;" hidevalue=""></td>
					<td style="text-align:left;">[1014300272]程序设计实践</td>
					<td style="text-align:right;">32</td>
					<td style="text-align:right;">2.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1200400840]焦贤沛</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 三[1-2] 麦图文楼M103(60)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr9_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr9_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr9_kcdm" name="kcdm" style="display: none">1014300272</td>
					<td id="tr9_skbjdm" name="skbjdm" style="display: none">1014300272-003</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="1014300283-004">1014300283-004</td>
					<td style="text-align:left;" hidevalue="主干+">主干+</td>
					<td style="text-align:left;">[1014300283]面向对象程序设计(双语)</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1201900014]夏雪</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周(单) 一[6-8] 麦三教3407(70),1-16周(双) 一[6-8] 麦图文楼M106(78)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr10_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr10_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr10_kcdm" name="kcdm" style="display: none">1014300283</td>
					<td id="tr10_skbjdm" name="skbjdm" style="display: none">1014300283-004</td>
				</tr>
				
				<tr>
					<td style="text-align:center;" hidevalue="1014300293-004">1014300293-004</td>
					<td style="text-align:left;" hidevalue=""></td>
					<td style="text-align:left;">[1014300293]数字逻辑与数字系统</td>
					<td style="text-align:right;">48</td>
					<td style="text-align:right;">3.0</td>
					<td style="text-align:center;">初修</td>
					
					<td style="text-align:left;">[1202400028]包晗秋</td>
					
					<td style="text-align:center;">选中</td>
					<td style="text-align:center;">否</td>
					<td style="text-align:center;">是</td>
					<td style="text-align:left;">1-16周 二[10-11] 麦三教3313(70),1-16周(双) 四[10-11] 麦图文楼M102(52)(麦庐园校区)</td>
					<td style="text-align:left;"></td>
					<td id="tr11_xtxh" name="xtxh" style="display: none">201600035929</td>
					<td id="tr11_xk_status_m" name="xk_status_m" style="display: none">03</td>
					<td id="tr11_kcdm" name="kcdm" style="display: none">1014300293</td>
					<td id="tr11_skbjdm" name="skbjdm" style="display: none">1014300293-004</td>
				</tr>
				
			</tbody>
		</table>
		
	</body>
</html>

""";
  }
}
