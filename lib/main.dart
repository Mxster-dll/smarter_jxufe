import 'package:flutter/material.dart';

import 'Grades.dart';
import 'login.dart';

void main() => runApp(const SmarterJxUFE());

class SmarterJxUFE extends StatelessWidget {
  const SmarterJxUFE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧尼采',
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: const Color.fromARGB(255, 0, 140, 255),
        ),
      ),
      //   home: MyHomePage(title: "demo"),
      home: LoginScreen(),
      // home: const HomePage(title: '智慧尼采 SmarterJxUFE'),
      // home: GradesPage(title: '智慧尼采 SmarterJxUFE'),
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
                      //   Image(image: AssetImage("images/学业成绩.png"), width: 100),
                      Text("学业成绩"),
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
