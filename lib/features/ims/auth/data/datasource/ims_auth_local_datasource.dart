import 'package:hive/hive.dart';

class ImsAuthLocalDataSource {
  final Box<String> _box;

  ImsAuthLocalDataSource(this._box);

  Future<void> saveJsessionId(String jsessionId) =>
      _box.put('JSESSIONID', jsessionId);

  String? getJsessionId() => _box.get('JSESSIONID');

  Future<void> clearJsessionId() => _box.delete('JSESSIONID');
}
