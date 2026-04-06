// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_major.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ApiMajor _$ApiMajorFromJson(Map<String, dynamic> json) {
  return _ApiMajor.fromJson(json);
}

/// @nodoc
mixin _$ApiMajor {
  String get code => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ApiMajorCopyWith<ApiMajor> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ApiMajorCopyWith<$Res> {
  factory $ApiMajorCopyWith(ApiMajor value, $Res Function(ApiMajor) then) =
      _$ApiMajorCopyWithImpl<$Res, ApiMajor>;
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class _$ApiMajorCopyWithImpl<$Res, $Val extends ApiMajor>
    implements $ApiMajorCopyWith<$Res> {
  _$ApiMajorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_value.copyWith(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ApiMajorImplCopyWith<$Res>
    implements $ApiMajorCopyWith<$Res> {
  factory _$$ApiMajorImplCopyWith(
          _$ApiMajorImpl value, $Res Function(_$ApiMajorImpl) then) =
      __$$ApiMajorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class __$$ApiMajorImplCopyWithImpl<$Res>
    extends _$ApiMajorCopyWithImpl<$Res, _$ApiMajorImpl>
    implements _$$ApiMajorImplCopyWith<$Res> {
  __$$ApiMajorImplCopyWithImpl(
      _$ApiMajorImpl _value, $Res Function(_$ApiMajorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_$ApiMajorImpl(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ApiMajorImpl implements _ApiMajor {
  const _$ApiMajorImpl({required this.code, required this.name});

  factory _$ApiMajorImpl.fromJson(Map<String, dynamic> json) =>
      _$$ApiMajorImplFromJson(json);

  @override
  final String code;
  @override
  final String name;

  @override
  String toString() {
    return 'ApiMajor(code: $code, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiMajorImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, code, name);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiMajorImplCopyWith<_$ApiMajorImpl> get copyWith =>
      __$$ApiMajorImplCopyWithImpl<_$ApiMajorImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ApiMajorImplToJson(
      this,
    );
  }
}

abstract class _ApiMajor implements ApiMajor {
  const factory _ApiMajor(
      {required final String code,
      required final String name}) = _$ApiMajorImpl;

  factory _ApiMajor.fromJson(Map<String, dynamic> json) =
      _$ApiMajorImpl.fromJson;

  @override
  String get code;
  @override
  String get name;
  @override
  @JsonKey(ignore: true)
  _$$ApiMajorImplCopyWith<_$ApiMajorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
