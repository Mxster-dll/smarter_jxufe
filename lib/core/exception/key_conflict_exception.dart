class KeyConflictException implements Exception {
  final String? message;

  KeyConflictException([this.message]);

  @override
  String toString() => 'KeyConflictException: $message';
}
