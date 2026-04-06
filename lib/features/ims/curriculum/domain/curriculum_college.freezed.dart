// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'curriculum_college.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$CurriculumCollege {
  String get code => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $CurriculumCollegeCopyWith<CurriculumCollege> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurriculumCollegeCopyWith<$Res> {
  factory $CurriculumCollegeCopyWith(
          CurriculumCollege value, $Res Function(CurriculumCollege) then) =
      _$CurriculumCollegeCopyWithImpl<$Res, CurriculumCollege>;
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class _$CurriculumCollegeCopyWithImpl<$Res, $Val extends CurriculumCollege>
    implements $CurriculumCollegeCopyWith<$Res> {
  _$CurriculumCollegeCopyWithImpl(this._value, this._then);

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
abstract class _$$CurriculumCollegeImplCopyWith<$Res>
    implements $CurriculumCollegeCopyWith<$Res> {
  factory _$$CurriculumCollegeImplCopyWith(_$CurriculumCollegeImpl value,
          $Res Function(_$CurriculumCollegeImpl) then) =
      __$$CurriculumCollegeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String code, String name});
}

/// @nodoc
class __$$CurriculumCollegeImplCopyWithImpl<$Res>
    extends _$CurriculumCollegeCopyWithImpl<$Res, _$CurriculumCollegeImpl>
    implements _$$CurriculumCollegeImplCopyWith<$Res> {
  __$$CurriculumCollegeImplCopyWithImpl(_$CurriculumCollegeImpl _value,
      $Res Function(_$CurriculumCollegeImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_$CurriculumCollegeImpl(
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

class _$CurriculumCollegeImpl implements _CurriculumCollege {
  const _$CurriculumCollegeImpl({required this.code, required this.name});

  @override
  final String code;
  @override
  final String name;

  @override
  String toString() {
    return 'CurriculumCollege(code: $code, name: $name)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurriculumCollegeImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name));
  }

  @override
  int get hashCode => Object.hash(runtimeType, code, name);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CurriculumCollegeImplCopyWith<_$CurriculumCollegeImpl> get copyWith =>
      __$$CurriculumCollegeImplCopyWithImpl<_$CurriculumCollegeImpl>(
          this, _$identity);
}

abstract class _CurriculumCollege implements CurriculumCollege {
  const factory _CurriculumCollege(
      {required final String code,
      required final String name}) = _$CurriculumCollegeImpl;

  @override
  String get code;
  @override
  String get name;
  @override
  @JsonKey(ignore: true)
  _$$CurriculumCollegeImplCopyWith<_$CurriculumCollegeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
