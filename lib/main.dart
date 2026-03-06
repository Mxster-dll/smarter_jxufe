import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/AcademicUnit.dart';
import 'package:smarter_jxufe/ims/CurriculumData.dart';
import 'package:smarter_jxufe/ims/GradePage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  }

  await GetStorage.init();
  // TODO 此行验证登录状态（修改密码的情况）并隔一阵子就验证密码（可选）
  await CalendarService.update();
  // CalendarService.showDurationBetweenAcademicTimes();

  MajorCurriculum data = MajorCurriculum();
  data.checkUpdate();

  //   runApp(const SmarterJxUFE());
}

class SmarterJxUFE extends StatelessWidget {
  const SmarterJxUFE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '智慧尼采',
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color.fromARGB(255, 0, 140, 255),
        ),
      ),
      // home: MyHomePage(title: 'demo'),
      // home: LoginScreen(),
      // home: const HomePage(title: '智慧尼采 SmarterJxUFE'),
      home: GradesPage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});
  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(
                  child: Column(
                    children: [
                      //   Image(image: AssetImage('images/学业成绩.png'), width: 100),
                      Text('学业成绩'),
                    ],
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
