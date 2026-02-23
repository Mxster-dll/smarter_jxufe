// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:smarter_jxufe/components/mfa_dialog.dart';
import 'package:smarter_jxufe/constants/api_constants.dart';
import 'package:smarter_jxufe/constants/app_strings.dart';
import 'package:smarter_jxufe/constants/app_colors.dart';
import 'package:smarter_jxufe/utils/encryption_utils.dart';
import 'package:smarter_jxufe/models/login_model.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _currentTab = 0;
  bool _isMobile = false;
  bool _qrCodeEnabled = true;
  bool _showCaptcha = false;
  String _captchaUrl = ApiConstants.captcha;

  LoginData _loginData = LoginData();
  bool _isLoading = false;
  String _errorMessage = '';
  String? _publicKey;
  String? _fpVisitorId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController!.addListener(() {
      setState(() {
        _currentTab = _tabController!.index;
      });
    });

    _checkDeviceType();
    _loadPublicKey();
    _checkCaptchaShow();
    _initFingerprint();
    _loadRememberedData();
  }

  void _checkDeviceType() {
    // TODO: 实际应用中根据User-Agent判断
    _isMobile = false;
  }

  Future<void> _loadPublicKey() async {
    try {
      final response = await http.get(Uri.parse(ApiConstants.publicKey));
      if (response.statusCode == 200) {
        setState(() {
          _publicKey = response.body;
        });
      }
    } catch (e) {
      print('加载公钥失败: $e');
    }
  }

  void _checkCaptchaShow() {
    // TODO: 根据登录失败次数判断
    setState(() {
      _showCaptcha = false;
    });
  }

  Future<void> _initFingerprint() async {
    // TODO: 实现浏览器指纹
    _fpVisitorId = 'temp_fingerprint_id';
  }

  Future<void> _loadRememberedData() async {
    // TODO: 从shared_preferences加载记住的账号
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: NetworkImage('https://ssl.jxufe.edu.cn/cas/file/png/bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildLogoSection(),
              _buildLoginCard(),
              _buildCopyright(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: EdgeInsets.only(top: 60, bottom: 30),
      child: Image.network(
        'https://ssl.jxufe.edu.cn/cas/file/png/logo.png',
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            AppStrings.appTitle,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: 450,
      margin: EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: '账号密码登录'),
                Tab(text: '手机动态码登录'),
                Tab(text: '扫码登录'),
              ],
            ),
          ),
          Container(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPasswordLogin(),
                _buildSmsLogin(),
                _buildQrCodeLogin(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordLogin() {
    return Padding(
      padding: EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: AppStrings.usernameHint,
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _loginData.username = value,
          ),
          SizedBox(height: 20),
          TextField(
            obscureText: true,
            decoration: InputDecoration(
              labelText: AppStrings.passwordHint,
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => _loginData.password = value,
          ),

          if (_showCaptcha) ...[
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: AppStrings.captchaHint,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _loginData.captcha = value,
                  ),
                ),
                SizedBox(width: 10),
                GestureDetector(
                  onTap: _refreshCaptcha,
                  child: Container(
                    width: 120,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Image.network(
                      '$_captchaUrl?r=${DateTime.now().millisecondsSinceEpoch}',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: 20),
          Row(
            children: [
              Checkbox(
                value: _loginData.rememberMe,
                onChanged: (value) {
                  setState(() {
                    _loginData.rememberMe = value ?? false;
                  });
                },
              ),
              Text(AppStrings.rememberMe),
              Spacer(),
              TextButton(
                onPressed: _handleForgotPassword,
                child: Text(AppStrings.forgotPassword),
              ),
            ],
          ),

          SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: _isLoading ? null : _handlePasswordLogin,
            child: _isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : Text(AppStrings.loginTitle, style: TextStyle(fontSize: 16)),
          ),

          if (_errorMessage.isNotEmpty) ...[
            SizedBox(height: 15),
            _buildErrorMessage(_errorMessage),
          ],

          SizedBox(height: 20),
          Text(
            '其他方式登录',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),

          SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialLoginButton('微信', Icons.wechat),
              SizedBox(width: 20),
              _buildSocialLoginButton('企业微信', Icons.business),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: AppColors.error),
          SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialLoginButton(String text, IconData icon) {
    return OutlinedButton.icon(
      onPressed: () => _handleSocialLogin(text),
      icon: Icon(icon),
      label: Text(text),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.grey[300]!),
      ),
    );
  }

  Widget _buildSmsLogin() {
    return Padding(
      padding: EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: '手机号',
              hintText: AppStrings.mobileHint,
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) => _loginData.mobile = value,
          ),

          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: '动态码',
                    hintText: AppStrings.smsHint,
                    prefixIcon: Icon(Icons.message),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => _loginData.dynamicCode = value,
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: _sendSmsCode,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.grey[200],
                ),
                child: Text(AppStrings.sendSms),
              ),
            ],
          ),

          SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: Size(double.infinity, 50),
            ),
            onPressed: _handleSmsLogin,
            child: Text(AppStrings.loginTitle, style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCodeLogin() {
    return Padding(
      padding: EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Image.network(
              '${ApiConstants.qrCode}?r=${DateTime.now().millisecondsSinceEpoch}',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(child: Text('加载二维码失败'));
              },
            ),
          ),

          SizedBox(height: 20),
          Text(
            AppStrings.qrScanHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),

          SizedBox(height: 20),
          OutlinedButton(onPressed: _refreshQrCode, child: Text('刷新二维码')),
        ],
      ),
    );
  }

  Widget _buildCopyright() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 30),
      child: Text(
        AppStrings.copyright,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  void _refreshCaptcha() {
    setState(() {
      _captchaUrl =
          '${ApiConstants.captcha}?r=${DateTime.now().millisecondsSinceEpoch}';
    });
  }

  void _refreshQrCode() {
    setState(() {});
  }

  Future<void> _sendSmsCode() async {
    if (_loginData.mobile.isEmpty || !_isValidPhone(_loginData.mobile)) {
      _showError('请输入正确的手机号');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.sendSms),
        body: {'username': _loginData.mobile},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data']['success']) {
          _showSuccess('已发送');
        } else {
          _showError('发送失败');
        }
      } else {
        _showError('发送失败');
      }
    } catch (e) {
      _showError('发送失败: $e');
    }
  }

  Future<void> _handlePasswordLogin() async {
    if (_loginData.username.isEmpty) {
      _showError('请输入校园卡号');
      return;
    }

    if (_loginData.password.isEmpty) {
      _showError('请输入登录密码');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final mfaResponse = await http.post(
        Uri.parse(ApiConstants.mfaDetect),
        body: {
          'username': _loginData.username,
          'password': _encryptPassword(_loginData.password),
          'fpVisitorId': _fpVisitorId ?? '',
        },
      );

      if (mfaResponse.statusCode == 200) {
        final data = json.decode(mfaResponse.body);
        if (data['code'] == 0 && data['data']['need'] == true) {
          _showMfaDialog(data['data']['state']);
        } else {
          await _submitLogin();
        }
      } else {
        await _submitLogin();
      }
    } catch (e) {
      _showError('登录失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submitLogin() async {
    final execution = ""; // TODO: 从服务器获取

    final response = await http.post(
      Uri.parse(ApiConstants.login),
      body: {
        'username': _loginData.username,
        'password': _encryptPassword(_loginData.password),
        'captcha': _loginData.captcha,
        'rememberMe': _loginData.rememberMe.toString(),
        'currentMenu': '1',
        'failN': '-1',
        'mfaState': '',
        'execution': execution,
        '_eventId': 'submit',
        'geolocation': '',
        'fpVisitorId': _fpVisitorId ?? '',
        'trustAgent': '',
      },
    );

    if (response.statusCode == 200) {
      _showSuccess('登录成功');
      // TODO: 跳转到主页
    } else {
      _showError('账号或密码错误');
    }
  }

  Future<void> _handleSmsLogin() async {
    if (_loginData.mobile.isEmpty || !_isValidPhone(_loginData.mobile)) {
      _showError('请输入正确的手机号');
      return;
    }

    if (_loginData.dynamicCode.isEmpty) {
      _showError('请输入动态密码');
      return;
    }

    final execution = ""; // TODO: 从服务器获取

    try {
      final response = await http.post(
        Uri.parse(ApiConstants.login),
        body: {
          'username': _loginData.mobile,
          'password': _loginData.dynamicCode,
          'currentMenu': '2',
          'failN': '-1',
          'execution': execution,
          '_eventId': 'submitPasswordlessToken',
          'geolocation': '',
          'fpVisitorId': _fpVisitorId ?? '',
          'trustAgent': '',
        },
      );

      if (response.statusCode == 200) {
        _showSuccess('登录成功');
      } else {
        _showError('登录失败');
      }
    } catch (e) {
      _showError('登录失败: $e');
    }
  }

  void _showMfaDialog(String state) {
    showDialog(
      context: context,
      builder: (context) => MfaDialog(state: state),
    );
  }

  String _encryptPassword(String password) {
    if (_publicKey != null) {
      // TODO: 实现RSA加密
      return EncryptionUtils.rsaEncrypt(password, _publicKey!);
    }
    return password;
  }

  bool _isValidPhone(String phone) {
    final regex = RegExp(r'^1[0-9]{10}$');
    return regex.hasMatch(phone);
  }

  void _handleForgotPassword() {
    // TODO: 跳转到忘记密码页面
  }

  void _handleSocialLogin(String type) {
    // TODO: 处理社交登录
    print('选择$type登录');
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
}
