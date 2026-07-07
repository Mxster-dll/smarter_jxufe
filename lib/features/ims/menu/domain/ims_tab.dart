import 'package:flutter/material.dart';

enum ImsTab {
  curriculum('培养方案', '查看专业培养方案与教学计划', Icons.school, Colors.blue),
  schedule('课表', '查看本学期课程安排', Icons.calendar_today, Colors.green),
  grade('成绩', '查看各学期考试成绩', Icons.grade, Colors.orange),
  graduationRequirements('毕业学分', '查看毕业学分要求', Icons.verified, Colors.teal),
  studentInfo('我的', '查看个人信息与学籍状态', Icons.person, Colors.purple);

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const ImsTab(this.title, this.subtitle, this.icon, this.color);
}
