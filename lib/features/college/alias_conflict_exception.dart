class AliasConflictException implements Exception {
  final String? message;

  AliasConflictException([this.message]);

  @override
  String toString() => 'AliasConflictException: $message';
}
