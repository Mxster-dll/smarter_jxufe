import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:smarter_jxufe/Services/JxufeLogin.dart';
import 'package:smarter_jxufe/Services/ScanLogin.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/Services/MfaService.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '江西财经大学统一身份认证',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC3282E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: IconThemeData(color: Color(0xFF333333)),
          titleTextStyle: TextStyle(
            color: Color(0xFF333333),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC3282E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF999999)),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC3282E),
            side: const BorderSide(color: Color(0xFFC3282E)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          hintStyle: const TextStyle(color: Color(0xFF999999)),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        fontFamily: 'Microsoft YaHei, PingFangSC-Regular, sans-serif',
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// INFO
// 信任设备在第一个login请求的trustAgent字段
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final Dio _dio = Dio();
  late final MfaService _mfaService = MfaService(_dio);
  late final ScanLogin _scanLoginService = ScanLogin();

  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _passwordVisible = false;
  Future<void>? loginPageInfo;

  @override
  void initState() => super.initState();

  Future<void> _handleLogin() async {
    // final username = _usernameController.text.trim();
    // final password = _passwordController.text.trim();
    //
    // if (username.isEmpty) {
    //   setState(() {
    //     _errorMessage = '请输入校园卡号';
    //   });
    //   return;
    // } else if (password.isEmpty) {
    //   setState(() {
    //     _errorMessage = '请输入密码';
    //   });
    //   return;
    // }
    var account = _accountController.text.trim();
    var password = _passwordController.text.trim();
    if (account.isEmpty) account = '[REDACTED_EMAIL]';
    if (password.isEmpty) password = '[REDACTED_PWD]';

    _mfaService.set(account, password);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _mfaService.process(context);
    } catch (e) {
      setState(() {
        _errorMessage = '登录失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JxufeTheme.backgroundColor,
      body: Stack(
        children: [
          // 背景装饰元素
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: JxufeTheme.primaryColor.withAlpha(26),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(100),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: JxufeTheme.primaryColor.withAlpha(26),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(100),
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 20, bottom: 40),
                  child: Column(
                    children: [
                      // 校徽和文字组合
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: JxufeTheme.primaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.school,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '江西财经大学统一身份认证',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: JxufeTheme.textColor,
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                'Jiangxi University of Finance and Economics',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: JxufeTheme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 分割线
                      Container(
                        height: 1,
                        color: JxufeTheme.borderColor,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

                SizedBox(height: 60),

                // 登录表单卡片
                Container(
                  width: 450,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(26),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // 表单标题
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          child: Row(
                            children: [
                              Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: JxufeTheme.primaryColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '账号密码登录',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: JxufeTheme.textColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 用户名输入框
                        Container(
                          decoration: BoxDecoration(
                            color: JxufeTheme.inputBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: _accountController,
                            decoration: InputDecoration(
                              hintText: '请输入校园卡号',
                              hintStyle: TextStyle(color: JxufeTheme.hintColor),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline,
                                color: JxufeTheme.primaryColor.withAlpha(96),
                              ),
                            ),
                            style: TextStyle(color: JxufeTheme.textColor),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 密码输入框
                        Container(
                          decoration: BoxDecoration(
                            color: JxufeTheme.inputBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              hintText: '请输入登录密码',
                              hintStyle: TextStyle(color: JxufeTheme.hintColor),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: JxufeTheme.primaryColor.withAlpha(96),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: JxufeTheme.hintColor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _passwordVisible = !_passwordVisible;
                                  });
                                },
                              ),
                            ),
                            style: TextStyle(color: JxufeTheme.textColor),
                            obscureText: !_passwordVisible,
                            onSubmitted: (_) => _handleLogin(),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 错误提示
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: JxufeTheme.primaryColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: JxufeTheme.primaryColor.withAlpha(51),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: JxufeTheme.primaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: JxufeTheme.primaryColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),

                        // 登录按钮
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: JxufeTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    '登录',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // 其他登录方式图标
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildOtherLoginIcon(
                              Icons.qr_code,
                              JxufeTheme.primaryColor,
                              onTap: () => _scanLoginService.process(context),
                            ),

                            const SizedBox(width: 32),

                            _buildOtherLoginIcon(
                              Icons.wechat,
                              const Color(0xFF14c468),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('暂未开放微信登录'),
                                    backgroundColor: JxufeTheme.primaryColor,
                                  ),
                                );
                              },
                            ),

                            const SizedBox(width: 32),

                            _buildOtherLoginIcon(
                              ExpandIcons.wecon,
                              const Color(0xFF73A9EC),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('暂未开放企业微信登录'),
                                    backgroundColor: JxufeTheme.primaryColor,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 底部信息
                Container(
                  margin: const EdgeInsets.only(top: 40, bottom: 24),
                  child: Column(
                    children: [
                      Container(
                        height: 1,
                        color: JxufeTheme.borderColor,
                        margin: const EdgeInsets.only(bottom: 16),
                      ),
                      const Text(
                        'Copyright© 2026 All right reserved.',
                        style: TextStyle(
                          fontSize: 12,
                          color: JxufeTheme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherLoginIcon(
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final isHovering = ValueNotifier<bool>(false);

    return MouseRegion(
      onEnter: (_) => isHovering.value = true,
      onExit: (_) => isHovering.value = false,
      child: GestureDetector(
        onTap: onTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: isHovering,
          builder: (context, hovering, child) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: hovering ? color : JxufeTheme.inputBgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hovering ? color : JxufeTheme.borderColor,
                  width: hovering ? 2 : 1,
                ),
                boxShadow: hovering
                    ? [
                        BoxShadow(
                          color: color.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: hovering ? Colors.white : color,
                size: 24,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
