import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository.dart';

void main() {
  const repo = DeviceProfileRepository();

  test('fpVisitorId 为 32 位十六进制且同一实例两次一致', () {
    final a = repo.fpVisitorId;
    final b = repo.fpVisitorId;
    expect(a, b);
    expect(a.length, 32);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
  });

  test('userAgent 保持既有浏览器形态', () {
    final ua = repo.userAgent;
    expect(ua, contains('Windows NT 10.0'));
    expect(ua, contains('Chrome/145.0.0.0'));
  });
}
