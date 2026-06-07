import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/splash/presentation/splash_screen.dart';

void main() async {
  runApp(const ProviderScope(child: SmarterJxUFE()));
}

class SmarterJxUFE extends StatelessWidget {
  const SmarterJxUFE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '智慧尼采',
      theme:
          ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color.fromARGB(255, 0, 140, 255),
            ),
          ).copyWith(
            textTheme: ThemeData.light().textTheme.apply(
              fontFamily: 'Cascadia Code',
              fontFamilyFallback: ['霞鹜文楷', '仓耳今楷01'],
            ),
          ),
      home: SplashScreen(),
    );
  }
}
