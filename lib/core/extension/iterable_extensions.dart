extension DistinctBy<E> on Iterable<E> {
  Iterable<E> distinctBy<K>(K Function(E) keySelector) {
    final seen = <K>{};
    return where((e) => seen.add(keySelector(e)));
  }
}
