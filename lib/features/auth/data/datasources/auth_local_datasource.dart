import 'package:hive_flutter/hive_flutter.dart';

class AuthLocalDataSource {
  final Box<String> _box;

  AuthLocalDataSource(this._box);

  Future<void> saveTgc(String tgc) => _box.put('tgc', tgc);
  String? getTgc() => _box.get('tgc');
  Future<void> deleteTgc() => _box.delete('tgc');
}
