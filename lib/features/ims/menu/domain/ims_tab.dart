import 'package:flutter/material.dart';

enum ImsTab {
  curriculum('培养方案', Icons.school, Colors.blue),
  schedule('课表', Icons.calendar_today, Colors.green),
  grade('成绩', Icons.grade, Colors.orange),
  studentInfo('我的', Icons.person, Colors.purple);

  final String title;
  final IconData icon;
  final Color color;

  const ImsTab(this.title, this.icon, this.color);
}
