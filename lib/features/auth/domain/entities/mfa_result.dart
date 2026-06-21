class MfaResult {
  final bool needMfa;
  final String mfaState;

  const MfaResult({required this.needMfa, required this.mfaState});
}
