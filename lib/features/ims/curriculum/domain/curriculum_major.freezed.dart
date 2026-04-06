// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'curriculum_major.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$CurriculumMajor {
  String get code => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $CurriculumMajorCopyWith<CurriculumMajor> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurriculumMajorCopyWith<$Res> {
  factory $CurriculumMajorCopyWith(
          CurriculumMajor value, $Res Function(CurriculumMajor) then) =
      _$CurriculumMajorCopyWithImpl<$Res, CurriculumMajor>;
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class _$CurriculumMajorCopyWithImpl<$Res, $Val extends CurriculumMajor>
    implements $CurriculumMajorCopyWith<$Res> {
  _$CurriculumMajorCopyWithImpl(this._value, this._then);

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
abstract class _$$CurriculumMajorImplCopyWith<$Res>
    implements $CurriculumMajorCopyWith<$Res> {
  factory _$$CurriculumMajorImplCopyWith(_$CurriculumMajorImpl value,
          $Res Function(_$CurriculumMajorImpl) then) =
      __$$CurriculumMajorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class __$$CurriculumMajorImplCopyWithImpl<$Res>
    extends _$CurriculumMajorCopyWithImpl<$Res, _$CurriculumMajorImpl>
    implements _$$CurriculumMajorImplCopyWith<$Res> {
  __$$CurriculumMajorImplCopyWithImpl(
      _$CurriculumMajorImpl _value, $Res Function(_$CurriculumMajorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_$CurriculumMajorImpl(
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

class _$CurriculumMajorImpl implements _CurriculumMajor {
  const _$CurriculumMajorImpl({required this.code, required this.name});

  @override
  final String code;
  @override
  final String name;

  @override
  String toString() {
    return 'CurriculumMajor(code: $code, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurriculumMajorImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name));
  }

  @override
  int get hashCode => Object.hash(runtimeType, code, name);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CurriculumMajorImplCopyWith<_$CurriculumMajorImpl> get copyWith =>
      __$$CurriculumMajorImplCopyWithImpl<_$CurriculumMajorImpl>(
          this, _$identity);
}

abstract class _CurriculumMajor implements CurriculumMajor {
  const factory _CurriculumMajor(
      {required final String code,
      required final String name}) = _$CurriculumMajorImpl;

  @override
  String get code;
  @override
  String get name;
  @override
  @JsonKey(ignore: true)
  _$$CurriculumMajorImplCopyWith<_$CurriculumMajorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
