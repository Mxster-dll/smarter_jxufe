import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/Course.dart';
import 'package:smarter_jxufe/ims/CurriculumService.dart';
import 'package:smarter_jxufe/ims/GradePage.dart';

void main() async {
  await GetStorage.init();
  await CalendarService.update();
  // CalendarService.showDurationBetweenAcademicTimes();

  final cs = CurriculumService();
  final cnt = List<int>.filled(42, 0);
  final Map data = {};
  // TODO 添加空标识
  for (int i = 2025; i >= 2010; i--) {
    data[i] = {};
    print(i);
    print(await cs.getMajorList(i, '02'));
    final cl = await cs.getCollegeList();
    for (int j = 0; j < cl.length; j++) {
      print(cl[j]['name']!);
      final ml = await cs.getMajorList(i, cl[j]['code']!);
      if (ml.isNotEmpty) cnt[j]++;
      for (final m in ml) {
        // print(m['name']);
        await cs.getCurriculum(i, cl[j]['code']!, m['code']!);
      }
    }
  }

  print(CourseBuilder.fourth);
  print(cnt);

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
// import 'package:flutter/material.dart';
// import 'package:smarter_jxufe/pages/login_page.dart';

// void main() {
//   runApp(JxufeAuthApp());
// }

// class JxufeAuthApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: '江西财经大学统一身份认证',
//       theme: ThemeData(
//         primaryColor: Color(0xFFC3282E),
//         fontFamily: 'Microsoft YaHei',
//         scaffoldBackgroundColor: Colors.white,
//         appBarTheme: AppBarTheme(
//           backgroundColor: Color(0xFFC3282E),
//           elevation: 0,
//         ),
//       ),
//       home: LoginPage(),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }
