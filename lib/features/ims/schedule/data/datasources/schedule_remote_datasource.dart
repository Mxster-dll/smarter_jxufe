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
		<link rel="stylesheet" href="../css/Form.css" type="text/css" />
		<style type='text/css'>
		.table{width:98%;height:auto;border-collapse: collapse; margin: 0px auto; margin-top:10px; border:solid 1px #999;}
		.tr{height:auto;}
		.td{border:solid 1px #999; height:100%;margin-left: 2px;padding: 5px; vertical-align: top; }
		.td0{border:solid 1px #999;padding:0px;height:4mm;font-size:14px;text-align: center;background-color: #E4E4E4;}
		.td1{border:solid 1px #999;padding:0px;width:9mm;height:100%;font-size:14px;text-align: center;background-color: white;}
		.div1,.div_nokb{width:100%;height:100%;background-color:white;border:solid 0px gray;margin:0px;padding:0px;font-size:12px; position: relative;}
		.div_nokb{min-height:36px;}

		.xkinfo{ position:absolute; left:3px; top:3px;}
		.choice{ position:absolute; right:3px; bottom:3px; }
		tr.H {background-color: #A9D4A7; text-align: center; height:24px; line-height: 24px;}
	</style>

	</head>
	<body style="font-size:12px">


		<div>
			<input type="hidden" id="xn" name="xn" value="2025">
			<input type="hidden" id="xq_m" name="xq_m" value="1">
			<input type="hidden" id="xh" name="xh" value="201600035929">
		</div>

		<table class='table' style="border: 0px;" cellpadding="0" cellspacing="0">
			<tr>
				<td style="width:15%;">学号：REDACTED_USERNAME</td>
				<td style="width:15%;">姓名：陈煜仕</td>
				<td style="width:30%;">所在班级：计算机科学与技术252</td>
				<td style="width:40%;">
					课程门数：12&ensp;
					课程学分：31.0(未处理学分：0.0)&ensp;
					环节学分：0.0&ensp;
					本学期修读总学分：31.0&ensp;&ensp;
				</td>
			</tr>
		</table>

		<table class='table' id='mytable' name='mytable' >
			<thead></thead>
			<tbody >
				<tr class="H">
					<td class="td0" style='width:5%;padding:0px;' colspan='2'></td>

						<td class='td0' style="width:12%;height:20px;">
						星期一
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期二
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期三
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期四
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期五
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期六
						</td>

						<td class='td0' style="width:12%;height:20px;">
						星期日
						</td>

				</tr>


				<tr>
					<td class='td1' rowspan='2' valign='middle'>
						<div style='background-color: white; '><b>上<br>午</b></div>
					</td>
					<td class='td1'>
							<b>一</b>
					</td>


						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k11'>
							</div>

					</td>

						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k21'>
							</div>

					</td>

						<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>程序设计实践</font><br>焦贤沛 <br>1-16[1-2]<br>麦图文楼M103(麦庐园校区)</div>

					</td>

						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k41'>
							</div>

					</td>

						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k51'>
							</div>

					</td>

						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k61'>
							</div>

					</td>

						<td class='td' style="width:12%;">

							<div class='div_nokb' id='k71'>
							</div>

					</td>

				</tr>


				<tr>
					<td class='td1'>
							<b>
								二
							</b>
					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>写作与沟通I</font><br>王柳芳 <br>1-12[3-4]<br>麦三教3310(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>中国近现代史纲要</font><br>吴通福 <br>1-16[3-5]<br>麦三教3203(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>高等数学II</font><br>俞丽兰 <br>1-16[3-5]<br>麦三教3304(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>大学英语II</font><br>史希平 <br>1-16[3-4]<br>麦三教3207(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>体育2</font><br>彭永善 <br>1-16[3-4]<br>麦乒乓球场T021(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k62'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k72'>
							</div>

					</td>

				</tr>


				<!--
				</tbody>
				<tbody block="block">
				 -->

				<tr>
					<td class='td1' rowspan='2' valign='middle'>
						<div style='background-color: white;'><b>下<br>午</b></div>
					</td>
					<td class='td1'>
							<b>
								三
							</b>
					</td>


					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>面向对象程序设计(双语)</font><br>夏雪 <br>1-16 单 [6-8]<br>麦三教3407(麦庐园校区)</div><div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>面向对象程序设计(双语)</font><br>夏雪 <br>1-16 双 [6-8]<br>麦图文楼M106(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>毛泽东思想和中国特色社会主义理论体系概论</font><br>康立芳 <br>1-16[6-8]<br>麦三教3303(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>形势与政策II</font><br>谢尔艾力.库尔班 <br>13-16[6-7]<br>麦三教3403(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>大学物理</font><br>余泉茂 <br>1-16[6-8]<br>麦二教2103(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>习近平新时代中国特色社会主义思想概论</font><br>徐腊梅 <br>1-16[6-8]<br>麦三教3202(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k63'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k73'>
							</div>

					</td>

				</tr>

				<tr>
					<td class='td1'>
							<b>
								四
							</b>
					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k14'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k24'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k34'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k44'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k54'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k64'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k74'>
							</div>

					</td>

				</tr>

				<!--
				</tbody>
				<tbody block="block">
				 -->


				<tr>
					<td class='td1' rowspan='1' valign='middle'>
						<div style='background-color: white;'><b>晚<br>上</b></div>
					</td>
					<td class='td1'>
							<b>
								五
							</b>
					</td>


					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>高等数学II</font><br>俞丽兰 <br>1-16[10-12]<br>麦三教3303(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>数字逻辑与数字系统</font><br>包晗秋 <br>1-16[10-11]<br>麦三教3313(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k35'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div style='padding-bottom:5px;clear:both;'><font style='font-weight: bolder'>数字逻辑与数字系统</font><br>包晗秋 <br>1-16 双 [10-11]<br>麦图文楼M102(麦庐园校区)</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k55'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k65'>
							</div>

					</td>

					<td class='td' style="width:12%;">

							<div class='div_nokb' id='k75'>
							</div>

					</td>

				</tr>

			</tbody>
		</table>

		<br>
		<div style="text-align:left;">

		</div>
	</body>
</html>
""";
  }
}
