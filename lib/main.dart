import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';

import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_screen.dart';

void main() async {
  await HiveInitializer.init();

  await imsService.fetchJSessionId();

  // final container = ProviderContainer();
  // final value = container.read(collegeLocalDataSourceProvider);
  // await value.clearAll();

  // // TODO 此行验证登录状态（修改密码的情况）并隔一阵子就验证密码（可选）
  // await CalendarService.update();
  // // CalendarService.showDurationBetweenAcademicTimes();
  // MajorCurriculum data = MajorCurriculum();
  // data.checkUpdate();
  runApp(const ProviderScope(child: SmarterJxUFE()));
}

class SmarterJxUFE extends StatelessWidget {
  const SmarterJxUFE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '智慧尼采',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 0, 140, 255),
        ),
      ),
      home: CurriculumScreen(),
      // home: MyHomePage(title: 'demo'),
      // home: LoginScreen(),
      // home: const HomePage(title: '智慧尼采 SmarterJxUFE'),
      // home: GradesPage(),
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
