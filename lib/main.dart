import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'Grades.dart';

void main() async {
  runApp(const SmarterJxUFE());
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
      //   home: MyHomePage(title: 'demo'),
      //   home: LoginScreen(),
      // home: const HomePage(title: '智慧尼采 SmarterJxUFE'),
      home: GradesPage(title: '智慧尼采 SmarterJxUFE'),
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
// lib/main.dart
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
