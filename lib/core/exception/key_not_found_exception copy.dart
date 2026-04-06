class KeyNotFoundException implements Exception {
  final String? message;

  KeyNotFoundException([this.message]);

  @override
  String toString() => 'KeyNotFoundException: $message';
}
