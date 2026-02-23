// lib/components/mfa_dialog.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/api_constants.dart';

class MfaDialog extends StatefulWidget {
  final String state;

  MfaDialog({required this.state});

  @override
  _MfaDialogState createState() => _MfaDialogState();
}

class _MfaDialogState extends State<MfaDialog> {
  int _selectedType = 3;
  bool _trustAgent = false;
  String? _qrCodeUrl;
  bool _qrCodeScanned = false;
  String? _callbackCode;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initMfa();
  }

  Future<void> _initMfa() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.mfaInit}/qrcode?state=${widget.state}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          setState(() {
            _qrCodeUrl = data['data']['qrCode']['scanQrcode'];
            _callbackCode = data['data']['callbackCode'];
          });
          _startPolling();
        }
      }
    } catch (e) {
      print('初始化MFA失败: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      await _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    try {
      final response = await http.post(
        Uri.parse('https://ssl.jxufe.edu.cn/mf/api/guard/qrcode/status'),
        body: json.encode({'gid': widget.state}),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          final status = data['data']['status'];

          if (status == 2) {
            setState(() {
              _qrCodeScanned = true;
            });
            _pollingTimer?.cancel();
            _handleSubmit();
          } else if (status == 8) {
            setState(() {
              _qrCodeScanned = true;
            });
          } else if (status == 9) {
            setState(() {
              _qrCodeUrl = null;
              _callbackCode = null;
            });
            _pollingTimer?.cancel();
          }
        }
      }
    } catch (e) {
      print('轮询状态失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('安全验证'),
      content: Container(
        width: 500,
        height: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.info, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '当前登录环境异常，需通过安全验证确认是本人操作后才可继续登录。请选择安全验证方式！',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20),
              CheckboxListTile(
                title: Text('登录成功后，设为可信客户端'),
                value: _trustAgent,
                onChanged: (value) {
                  setState(() {
                    _trustAgent = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),

              SizedBox(height: 20),
              Row(
                children: [
                  Image.network(
                    'https://ssl.jxufe.edu.cn/cas/themes/mf/images/safe/qrcode.png',
                    width: 32,
                    height: 32,
                  ),
                  SizedBox(width: 10),
                  Text('使用客户端扫码'),
                ],
              ),

              SizedBox(height: 20),
              if (_qrCodeUrl != null) ...[
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _qrCodeScanned
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 48,
                              ),
                              SizedBox(height: 10),
                              Text('扫码成功'),
                            ],
                          ),
                        )
                      : Image.network(_qrCodeUrl!),
                ),

                SizedBox(height: 10),
                Text('支持微信、企业微信的扫一扫功能，完成安全验证'),
              ],

              if (_callbackCode != null) ...[
                SizedBox(height: 10),
                Text(
                  '确认码：$_callbackCode',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ],

              if (_qrCodeScanned) ...[
                SizedBox(height: 10),
                Text('请在手机上点击同意以完成安全验证'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _pollingTimer?.cancel();
            Navigator.pop(context);
          },
          child: Text('取消'),
        ),
        ElevatedButton(
          onPressed: _handleSubmit,
          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFC3282E)),
          child: Text('确 定'),
        ),
      ],
    );
  }

  void _handleSubmit() {
    _pollingTimer?.cancel();
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
