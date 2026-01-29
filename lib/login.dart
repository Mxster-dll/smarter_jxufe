import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'icons.dart';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;

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
  final String baseUrl = 'https://ssl.jxufe.edu.cn';

  JxufeLogin() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
  }

  Future<Map<String, String>> getLoginPage() async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/login',
        queryParameters: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
        },
      );

      final execution = RegExp(
        r'name="execution" value="([^"]+)"',
      ).firstMatch(response.data as String)?.group(1);
      final fpVisitorId = RegExp(
        r'name="fpVisitorId" value="([^"]+)"',
      ).firstMatch(response.data as String)?.group(1);

      return {'execution': execution ?? '', 'fpVisitorId': fpVisitorId ?? ''};
    } catch (e) {
      throw Exception('获取登录页面失败: $e');
    }
  }

  Future<String?> mfaDetect(
    String username,
    String password,
    Map<String, String> params,
  ) async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/mfa/detect',
        data: {
          'username': username,
          'password': password,
          'fpVisitorId': params['fpVisitorId'],
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final result = response.data as Map<String, dynamic>;
      if (result['code'] == 0 &&
          result['data'] != null &&
          result['data']['need'] == true) {
        return result['data']['state'] as String;
      }
      return null;
    } catch (e) {
      throw Exception('MFA检测失败: $e');
    }
  }

  Future<Map<String, dynamic>?> getQrCodeData(String state) async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/mfa/initByType/qrcode',
        queryParameters: {'state': state},
      );

      final result = response.data as Map<String, dynamic>;
      if (result['code'] == 0) {
        return result['data'] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      throw Exception('获取二维码数据失败: $e');
    }
  }

  Future<String?> getQrCodeImage(Map<String, dynamic> qrCodeData) async {
    try {
      String? qrCodeUrl = qrCodeData['qrCode']?['scanQrcode'] as String?;

      if (qrCodeUrl == null || qrCodeUrl.isEmpty) {
        final attestServer = qrCodeData['attestServerUrl'] as String?;
        final gid = qrCodeData['gid'] as String?;

        if (attestServer != null && gid != null) {
          final sendUrl = '$attestServer/api/guard/qrcode/send';
          final response = await _dio.post(sendUrl, data: {'gid': gid});

          final result = response.data as Map<String, dynamic>;
          if (result['code'] == 0) {
            qrCodeUrl = result['data']?['scanQrcode'] as String?;
          }
        }
      }

      return qrCodeUrl;
    } catch (e) {
      throw Exception('获取二维码图片失败: $e');
    }
  }

  Future<Uint8List?> downloadQrCode(String qrCodeUrl) async {
    try {
      // 确保URL完整
      String fullUrl = qrCodeUrl;
      if (qrCodeUrl.startsWith('/')) {
        fullUrl = '$baseUrl$qrCodeUrl';
      }

      final response = await _dio.get(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200) {
        return response.data as Uint8List;
      }
      return null;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  Future<Map<String, dynamic>> loginAndGetQrCodeData(
    String username,
    String password,
  ) async {
    try {
      // 获取登录页面参数
      final params = await getLoginPage();

      // 发送2FA检测请求
      final state = await mfaDetect(username, password, params);
      if (state == null) {
        throw Exception('不需要2FA验证或检测失败');
      }

      // 获取二维码数据
      final qrCodeData = await getQrCodeData(state);
      if (qrCodeData == null) {
        throw Exception('获取二维码数据失败');
      }

      return qrCodeData;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> getQrCodeUrl(Map<String, dynamic> qrCodeData) async {
    final qrCodeUrl = await getQrCodeImage(qrCodeData);
    if (qrCodeUrl == null) {
      throw Exception('获取二维码URL失败');
    }

    return qrCodeUrl;
  }

  String getGid(Map<String, dynamic> qrCodeData) {
    return qrCodeData['gid'] as String;
  }
}

// TODO 添加扫描登录
// 提前请求资源
// 确认码
// 待扫描 1 SENT
// 已扫描 8 SCANED
// 已取消 5 CANCEL
// 已确认 2 VALID
// code: -1 失效 （300s)
// 信任设备在第一个login请求的trustAgent字段
// {code: 0, data: { status: 1, statusCode: "SENT"}, message: null}
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _JxufeLogin = JxufeLogin();

  bool _isLoading = false;
  String? _errorMessage;
  Uint8List? _qrCodeBytes;
  bool _passwordVisible = false;

  // 江西财经大学主题色
  final Color _primaryColor = const Color(0xFFC3282E);
  final Color _secondaryColor = const Color(0xFF8B0000);
  final Color _backgroundColor = const Color(0xFFF5F5F5);
  final Color _inputBgColor = const Color(0xFFF8F8F8);
  final Color _borderColor = const Color(0xFFE0E0E0);
  final Color _textColor = const Color(0xFF333333);
  final Color _hintColor = const Color(0xFF999999);

  @override
  void initState() {
    super.initState();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _errorMessage = '请输入校园卡号';
      });
      return;
    } else if (password.isEmpty) {
      setState(() {
        _errorMessage = '请输入密码';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _qrCodeBytes = null;
    });

    try {
      final qrCodeData = await _JxufeLogin.loginAndGetQrCodeData(
        username,
        password,
      );

      final qrCodeUrl = await _JxufeLogin.getQrCodeUrl(qrCodeData);
      final gid = _JxufeLogin.getGid(qrCodeData);

      final qrCodeBytes = await _JxufeLogin.downloadQrCode(qrCodeUrl);
      final verifyCode = int.parse(path.basenameWithoutExtension(qrCodeUrl));

      if (qrCodeBytes != null) {
        setState(() {
          _qrCodeBytes = qrCodeBytes;
        });

        _showQrCodeDialog(
          qrCodeBytes,
          verifyCode,
          '安全验证',
          '当前登录环境异常，需通过安全验证确认是本人操作',
          '使用微信或者企业微信扫一扫完成验证',
        );

        QRCodePoller().startPolling(gid);
      } else {
        setState(() {
          _errorMessage = '获取二维码失败';
        });
      }
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
                            controller: _usernameController,
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
                              Color(0xFF14c468),
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
                              Color(0xFF73A9EC),
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
                      Text(
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

  Dialog _buildQrCodeDialog(
    Uint8List qrCodeBytes,
    int verifyCode,
    String title,
    String info,
    String tips,
  ) {
    return Dialog(
      backgroundColor: Colors.transparent, // 透明背景
      insetPadding: const EdgeInsets.symmetric(horizontal: 20), // 左右边距
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(0x26),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      info,
                      style: TextStyle(fontSize: 13, color: _hintColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // 二维码卡片
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _inputBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  children: [
                    Image.memory(
                      _qrCodeBytes!,
                      height: 200,
                      width: 200,
                      fit: BoxFit.contain,
                    ),

                    const SizedBox(height: 16),

                    Text(
                      tips,
                      style: TextStyle(fontSize: 13, color: _hintColor),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showQrCodeDialog(
    Uint8List qrCodeBytes,
    int verifyCode,
    String title,
    String info,
    String tips,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(0x1A), // 半透明背景
      barrierDismissible: true, // 点击背景关闭
      builder: (context) =>
          _buildQrCodeDialog(qrCodeBytes, verifyCode, title, info, tips),
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
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

/// 二维码状态枚举
enum QRCodeStatus {
  pendingScan(1, 'SENT', '待扫描'),
  scanned(8, 'SCANED', '已扫描'), // SCANED是一个官方的拼写错误，请不要修改它为SCANNED
  canceled(5, 'CANCEL', '手机端已拒绝'),
  confirmed(2, 'VALID', '手机端已确认');

  final int status;
  final String statusCode;
  final String description;

  const QRCodeStatus(this.status, this.statusCode, this.description);

  static QRCodeStatus? fromValue(int status) {
    for (var value in values) {
      if (value.status == status) return value;
    }
    return null;
  }
}

/// 二维码轮询服务
class QRCodePoller {
  // 单例模式
  static final QRCodePoller _instance = QRCodePoller._internal();
  factory QRCodePoller() => _instance;
  QRCodePoller._internal();

  static const String _baseUrl = 'https://ssl.jxufe.edu.cn';
  static const String _statusPath = '/attest/api/guard/qrcode/status';

  // 使用 Dio 实例
  final Dio _dio = Dio();

  Timer? _pollingTimer;
  bool _isPolling = false;
  CancelToken? _cancelToken;

  /// 配置 Dio 请求头
  void _configureDio() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.headers = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Connection': 'keep-alive',
      'Content-Type': 'application/json; charset=UTF-8',
      // 'Cookie':
      //     'Hm_lvt_d605d8df6bf5ca8a54fe078683196518=1769601206; '
      //     'HMACCOUNT=95DD7CFF9EC39F39; '
      //     'Hm_lpvt_d605d8df6bf5ca8a54fe078683196518=1769601426',
      'Host': 'ssl.jxufe.edu.cn',
      'Origin': 'https://ssl.jxufe.edu.cn',
      'Referer':
          'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D0b0f3d2b6be14bd0b3c1ecc955bdb832',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
      'X-Requested-With': 'XMLHttpRequest',
      'sec-ch-ua':
          '"Not(A:Brand";v="8", "Chromium";v="144", "Microsoft Edge";v="144"',
      'sec-ch-ua-mobile': '?0',
    };
  }

  void startPolling(String gid) {
    if (_isPolling) {
      print('轮询已在运行中');
      return;
    }

    _isPolling = true;
    _cancelToken = CancelToken();
    print('开始轮询，gid: $gid');

    // 配置 Dio
    _configureDio();

    // 开始轮询
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isPolling) {
        timer.cancel();
        return;
      }
      _checkStatus(gid);
    });

    // 立即执行第一次请求
    _checkStatus(gid);
  }

  /// 停止轮询
  void stopPolling() {
    _isPolling = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _cancelToken?.cancel('用户停止轮询');
    _cancelToken = null;
    print('轮询已停止');
  }

  /// 检查二维码状态
  Future<void> _checkStatus(String gid) async {
    try {
      final response = await _dio.post(
        _statusPath,
        data: {'gid': gid},
        cancelToken: _cancelToken,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        final code = data['code'] as int;

        // 二维码失效
        if (code == -1) {
          print('二维码已失效');
          stopPolling();
          return;
        }

        // 正常状态
        if (code == 0 && data['data'] != null) {
          final Map<String, dynamic> statusData = data['data'];
          final int status = statusData['status'];
          final String statusCode = statusData['statusCode'];

          final qrStatus = QRCodeStatus.fromValue(status);
          if (qrStatus != null) {
            // 输出状态日志
            print(
              '二维码状态: ${qrStatus.description} '
              '(status: $status, statusCode: $statusCode)',
            );

            // 如果是确认或取消状态，停止轮询
            if (qrStatus == QRCodeStatus.confirmed ||
                qrStatus == QRCodeStatus.canceled) {
              print('二维码最终状态: ${qrStatus.description}，停止轮询');
              stopPolling();
            }
          } else {
            print('未知状态: status=$status, statusCode=$statusCode');
          }
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;

      print('轮询请求异常: ${e.message}');
    } catch (e) {
      print('轮询请求异常: $e');
    }
  }

  /// 检查是否在轮询中
  bool get isPolling => _isPolling;

  /// 清理资源
  void dispose() {
    stopPolling();
    _dio.close();
  }
}
