// lib/constants/api_constants.dart
class ApiConstants {
  static const String baseUrl = 'https://ssl.jxufe.edu.cn/cas';
  static const String mfBaseUrl = 'https://ssl.jxufe.edu.cn/mf';

  // 登录相关
  static const String login = '$baseUrl/login';
  static const String publicKey = '$baseUrl/jwt/publicKey';
  static const String captcha = '$baseUrl/captcha.jpg';
  static const String qrCode = '$baseUrl/qr/qrcode';
  static const String mfaDetect = '$baseUrl/mfa/detect';
  static const String mfaInit = '$baseUrl/mfa/initByType';
  static const String sendSms = '$baseUrl/passwordlessTokenSend';

  // 双因子认证
  static const String attestServerUrl = '$mfBaseUrl/api/guard';
  static const String qrCodeStatus = '$attestServerUrl/qrcode/status';

  // 个人中心
  static const String forgotPassword = '$baseUrl/personal/forgotYourPassword';
  static const String activeAccount = '$baseUrl/personal/activeYourAccount';

  // 联合登录
  static const String federatedLogin = '$baseUrl/federatedRedirect';
}
