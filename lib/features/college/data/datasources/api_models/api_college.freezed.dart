// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_college.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ApiCollege _$ApiCollegeFromJson(Map<String, dynamic> json) {
  return _ApiCollege.fromJson(json);
}

/// @nodoc
mixin _$ApiCollege {
  String get code => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ApiCollegeCopyWith<ApiCollege> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ApiCollegeCopyWith<$Res> {
  factory $ApiCollegeCopyWith(
          ApiCollege value, $Res Function(ApiCollege) then) =
      _$ApiCollegeCopyWithImpl<$Res, ApiCollege>;
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class _$ApiCollegeCopyWithImpl<$Res, $Val extends ApiCollege>
    implements $ApiCollegeCopyWith<$Res> {
  _$ApiCollegeCopyWithImpl(this._value, this._then);

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
abstract class _$$ApiCollegeImplCopyWith<$Res>
    implements $ApiCollegeCopyWith<$Res> {
  factory _$$ApiCollegeImplCopyWith(
          _$ApiCollegeImpl value, $Res Function(_$ApiCollegeImpl) then) =
      __$$ApiCollegeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class __$$ApiCollegeImplCopyWithImpl<$Res>
    extends _$ApiCollegeCopyWithImpl<$Res, _$ApiCollegeImpl>
    implements _$$ApiCollegeImplCopyWith<$Res> {
  __$$ApiCollegeImplCopyWithImpl(
      _$ApiCollegeImpl _value, $Res Function(_$ApiCollegeImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_$ApiCollegeImpl(
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
class _$ApiCollegeImpl implements _ApiCollege {
  const _$ApiCollegeImpl({required this.code, required this.name});

  factory _$ApiCollegeImpl.fromJson(Map<String, dynamic> json) =>
      _$$ApiCollegeImplFromJson(json);

  @override
  final String code;
  @override
  final String name;

  @override
  String toString() {
    return 'ApiCollege(code: $code, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiCollegeImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, code, name);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiCollegeImplCopyWith<_$ApiCollegeImpl> get copyWith =>
      __$$ApiCollegeImplCopyWithImpl<_$ApiCollegeImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ApiCollegeImplToJson(
      this,
    );
  }
}

abstract class _ApiCollege implements ApiCollege {
  const factory _ApiCollege(
      {required final String code,
      required final String name}) = _$ApiCollegeImpl;

  factory _ApiCollege.fromJson(Map<String, dynamic> json) =
      _$ApiCollegeImpl.fromJson;

  @override
  String get code;
  @override
  String get name;
  @override
  @JsonKey(ignore: true)
  _$$ApiCollegeImplCopyWith<_$ApiCollegeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
