import 'package:get_storage/get_storage.dart';

class ImsSessionManager {
  final String account;
  late final GetStorage _box;

  ImsSessionManager(this.account) {
    _box = GetStorage('ImsSession_$account'); // 每个账号独立文件
  }

  String? get jSessionId => _box.read<String>('JSESSIONID');

  Future<void> saveJSessionId(String? id) async {
    if (id == null) {
      await _box.remove('JSESSIONID');
    } else {
      await _box.write('JSESSIONID', id);
    }
  }

  void clear() => saveJSessionId(null);
}
