class College {
  final String code, name;

  const College(this.code, this.name);

  @override
  toString() => '$name ($code)';
}

class Major {
  final String code, name;

  const Major(this.code, this.name);

  @override
  toString() => '$name ($code)';
}
