import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:smarter_jxufe/QrCodeCard.dart';
import 'icons.dart';
import 'dart:async';
import 'QrCode.dart';

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

class JxufeLogin {
  final Dio _dio = Dio();
  static const String baseUrl = 'https://ssl.jxufe.edu.cn';

  String? _execution;
  String? _fpVisitorId;
  Future<void>? _futureLoginPageInfo;

  MfaQrCode? mqc;
  String? state;

  JxufeLogin() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    preloadLoginPage();
  }

  void preloadLoginPage() => _futureLoginPageInfo ??= _getLoginPageInfo();

  /// 获取登录页的 execution 和 fpVisitorId 字段
  Future<void> _getLoginPageInfo() async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/login',
        queryParameters: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
        },
      );

      final data = response.data as String;

      _execution = RegExp(
        r'name="execution" value="([^"]+)"',
      ).firstMatch(data)?.group(1)!;

      _fpVisitorId = RegExp(
        r'name="fpVisitorId" value="([^"]+)"',
      ).firstMatch(data)?.group(1)!;
    } catch (e) {
      throw Exception('获取登录页面失败: $e');
    }
  }

  Future<bool> mfaDetect(String account, String password) async {
    try {
      await _futureLoginPageInfo;
      final response = await _dio.post(
        '$baseUrl/cas/mfa/detect',
        data: {
          'username': account,
          'password': password,
          // 'fpVisitorId': _fpVisitorId!,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      if (data['need']) state = data['state'];

      return data['need'];
    } catch (e) {
      throw Exception('MFA检测失败: $e');
    }
  }

  // Future<void> _postLoginRequests(String account, String password) async {}

  // Future<void> login(String account, String password) async {
  //   try {
  //     if (await mfaDetect(account, password)) {
  //       final qrCodeUrl = '$baseUrl/cas/mfa/initByType/qrcode';
  //       final mqc = this.mqc = MfaQrCode(qrCodeUrl, state!);

  //       await mqc.init();
  //       mqc.data;
  //     }

  //     _postLoginRequests(account, password);
  //   } catch (e) {
  //     rethrow;
  //   }
  // }

  //   Future<Uint8List?> loginAndGetQrCodeData(
  //     String account,
  //     String password,
  //   ) async {
  //     try {
  //       // 发送2FA检测请求
  //       if (!await mfaDetect(account, password)) {
  //         throw Exception('不需要2FA验证');
  //       }

  //       // if (!await mfaDetect(username, password)) return null;

  //       // 获取二维码数据
  //       final qrCodeUrl = '$baseUrl/cas/mfa/initByType/qrcode';
  //       final mqc = this.mqc = MfaQrCode(qrCodeUrl, state!);

  //       await mqc.init();
  //       return mqc.data;
  //     } catch (e) {
  //       rethrow;
  //     }
  //   }
}

// INFO
// 信任设备在第一个login请求的trustAgent字段
// NOTE
// 提前请求资源
// 多用Future字段(全面详细的管理空与Future)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _loginService = JxufeLogin();

  bool _isLoading = false;
  String? _errorMessage;
  Uint8List? _qrCodeBytes;
  bool _passwordVisible = false;
  Future<void>? loginPageInfo;

  // 江西财经大学主题色
  static const Color _primaryColor = Color(0xFFC3282E);
  static const Color _secondaryColor = Color(0xFF8B0000);
  static const Color _backgroundColor = Color(0xFFF5F5F5);
  static const Color _inputBgColor = Color(0xFFF8F8F8);
  static const Color _borderColor = Color(0xFFE0E0E0);
  static const Color _textColor = Color(0xFF333333);
  static const Color _hintColor = Color(0xFF999999);

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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _qrCodeBytes = null;
    });

    try {
      if (await _loginService.mfaDetect(account, password)) {
        final qrCodeUrl = '${JxufeLogin.baseUrl}/cas/mfa/initByType/qrcode';
        final mfaQrCode = MfaQrCode(qrCodeUrl, _loginService.state!);

        // if (qrCodeBytes != null) {

        QrCodeCard.showQrCodeDialog(
          context,
          mfaQrCode,
          title: '安全验证',
          info: '当前登录环境异常，需通过安全验证确认是本人操作',
        );
        await mfaQrCode.init();
      }

      // } else {
      //   setState(() {
      //     _errorMessage = '获取二维码失败';
      //   });
      // }
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
      backgroundColor: _backgroundColor,
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
                color: _primaryColor.withAlpha(0x1A),
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
                color: _primaryColor.withAlpha(0x1A),
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
                              color: _primaryColor,
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
                                  color: _textColor,
                                  height: 1.2,
                                ),
                              ),
                              Text(
                                'Jiangxi University of Finance and Economics',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _hintColor,
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
                        color: _borderColor,
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
                        color: Colors.black.withAlpha(0x1A),
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
                                  color: _primaryColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '账号密码登录',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 用户名输入框
                        Container(
                          decoration: BoxDecoration(
                            color: _inputBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: _accountController,
                            decoration: InputDecoration(
                              hintText: '请输入校园卡号',
                              hintStyle: TextStyle(color: _hintColor),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline,
                                color: _primaryColor.withAlpha(0x60),
                              ),
                            ),
                            style: TextStyle(color: _textColor),
                            keyboardType: TextInputType.text,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 密码输入框
                        Container(
                          decoration: BoxDecoration(
                            color: _inputBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              hintText: '请输入登录密码',
                              hintStyle: TextStyle(color: _hintColor),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 18,
                              ),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: _primaryColor.withAlpha(0x60),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: _hintColor,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _passwordVisible = !_passwordVisible;
                                  });
                                },
                              ),
                            ),
                            style: TextStyle(color: _textColor),
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
                              color: _primaryColor.withAlpha(0x14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _primaryColor.withAlpha(0x33),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: _primaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: _primaryColor,
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
                              backgroundColor: _primaryColor,
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
                              _primaryColor,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('暂未开放扫描二维码登录登录'),
                                    backgroundColor: _primaryColor,
                                  ),
                                );
                              },
                            ),

                            const SizedBox(width: 32),

                            _buildOtherLoginIcon(
                              Icons.wechat,
                              const Color(0xFF14c468),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('暂未开放微信登录'),
                                    backgroundColor: _primaryColor,
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
                                    backgroundColor: _primaryColor,
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

                Spacer(),

                // 底部信息
                Container(
                  margin: const EdgeInsets.only(top: 40, bottom: 24),
                  child: Column(
                    children: [
                      Container(
                        height: 1,
                        color: _borderColor,
                        margin: const EdgeInsets.only(bottom: 16),
                      ),
                      const Text(
                        'Copyright© 2026 All right reserved.',
                        style: TextStyle(fontSize: 12, color: _hintColor),
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

  // Dialog _buildQrCodeDialog(QrCode qrCode, String title, String info) {
  //   return Dialog(
  //     backgroundColor: Colors.transparent,
  //     insetPadding: const EdgeInsets.symmetric(horizontal: 20),
  //     child: Container(
  //       decoration: BoxDecoration(
  //         color: Colors.white,
  //         borderRadius: BorderRadius.circular(12),
  //         boxShadow: [
  //           BoxShadow(
  //             color: Colors.black.withAlpha(0x26),
  //             blurRadius: 30,
  //             offset: const Offset(0, 10),
  //           ),
  //         ],
  //       ),
  //       child: Padding(
  //         padding: const EdgeInsets.all(24),
  //         child: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Container(
  //               margin: const EdgeInsets.only(bottom: 20),
  //               child: Column(
  //                 children: [
  //                   Container(
  //                     width: 40,
  //                     height: 40,
  //                     decoration: BoxDecoration(
  //                       color: _primaryColor,
  //                       borderRadius: BorderRadius.circular(20),
  //                     ),
  //                     child: const Icon(
  //                       Icons.qr_code_scanner,
  //                       color: Colors.white,
  //                       size: 24,
  //                     ),
  //                   ),

  //                   const SizedBox(height: 12),

  //                   Text(
  //                     title,
  //                     style: TextStyle(
  //                       fontSize: 18,
  //                       fontWeight: FontWeight.bold,
  //                       color: _textColor,
  //                     ),
  //                   ),

  //                   const SizedBox(height: 8),

  //                   Text(
  //                     info,
  //                     style: TextStyle(fontSize: 13, color: _hintColor),
  //                     textAlign: TextAlign.center,
  //                   ),
  //                 ],
  //               ),
  //             ),

  //             // 二维码卡片
  //             qrCode.buildQrCodeCard(
  //               backgroundColor: _inputBgColor,
  //               borderColor: _borderColor,
  //               tipsColor: _hintColor,
  //             ),

  //             const SizedBox(height: 20),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // void _showQrCodeDialog(
  //   QrCode qrcode, {
  //   required String title,
  //   required String info,
  // }) => showDialog(
  //   context: context,
  //   barrierColor: Colors.black.withAlpha(0x1A), // 半透明背景
  //   barrierDismissible: true, // 点击背景关闭
  //   builder: (context) => _buildQrCodeDialog(qrcode, title, info),
  // );

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
                color: hovering ? color : _inputBgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hovering ? color : _borderColor,
                  width: hovering ? 2 : 1,
                ),
                boxShadow: hovering
                    ? [
                        BoxShadow(
                          color: color.withAlpha(0x4D),
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
