// lib/models/login_model.dart
class LoginData {
  String username = '';
  String password = '';
  String captcha = '';
  String mobile = '';
  String dynamicCode = '';
  bool rememberMe = false;
  String? execution;
  String? fpVisitorId;
  bool trustAgent = false;

  Map<String, String> toPasswordLoginParams() {
    return {
      'username': username,
      'password': password,
      'captcha': captcha,
      'rememberMe': rememberMe.toString(),
      'currentMenu': '1',
      'failN': '-1',
      'mfaState': '',
      'execution': execution ?? '',
      '_eventId': 'submit',
      'geolocation': '',
      'fpVisitorId': fpVisitorId ?? '',
      'trustAgent': trustAgent.toString(),
    };
  }

  Map<String, String> toSmsLoginParams() {
    return {
      'username': mobile,
      'password': dynamicCode,
      'currentMenu': '2',
      'failN': '-1',
      'execution': execution ?? '',
      '_eventId': 'submitPasswordlessToken',
      'geolocation': '',
      'fpVisitorId': fpVisitorId ?? '',
      'trustAgent': trustAgent.toString(),
    };
  }

  void clear() {
    username = '';
    password = '';
    captcha = '';
    mobile = '';
    dynamicCode = '';
    rememberMe = false;
    trustAgent = false;
  }
}
