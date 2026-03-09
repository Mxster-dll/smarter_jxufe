// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'major.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Major _$MajorFromJson(Map<String, dynamic> json) {
  return _Major.fromJson(json);
}

/// @nodoc
mixin _$Major {
  @HiveField(0)
  String get code => throw _privateConstructorUsedError;
  @HiveField(1)
  String get name => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $MajorCopyWith<Major> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MajorCopyWith<$Res> {
  factory $MajorCopyWith(Major value, $Res Function(Major) then) =
      _$MajorCopyWithImpl<$Res, Major>;
  @useResult
  $Res call({@HiveField(0) String code, @HiveField(1) String name});
}

/// @nodoc
class _$MajorCopyWithImpl<$Res, $Val extends Major>
    implements $MajorCopyWith<$Res> {
  _$MajorCopyWithImpl(this._value, this._then);

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
abstract class _$$MajorImplCopyWith<$Res> implements $MajorCopyWith<$Res> {
  factory _$$MajorImplCopyWith(
          _$MajorImpl value, $Res Function(_$MajorImpl) then) =
      __$$MajorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({@HiveField(0) String code, @HiveField(1) String name});
}

/// @nodoc
class __$$MajorImplCopyWithImpl<$Res>
    extends _$MajorCopyWithImpl<$Res, _$MajorImpl>
    implements _$$MajorImplCopyWith<$Res> {
  __$$MajorImplCopyWithImpl(
      _$MajorImpl _value, $Res Function(_$MajorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
  }) {
    return _then(_$MajorImpl(
      null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MajorImpl implements _Major {
  const _$MajorImpl(@HiveField(0) this.code, @HiveField(1) this.name);

  factory _$MajorImpl.fromJson(Map<String, dynamic> json) =>
      _$$MajorImplFromJson(json);

  @override
  @HiveField(0)
  final String code;
  @override
  @HiveField(1)
  final String name;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MajorImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, code, name);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MajorImplCopyWith<_$MajorImpl> get copyWith =>
      __$$MajorImplCopyWithImpl<_$MajorImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MajorImplToJson(
      this,
    );
  }
}

abstract class _Major implements Major {
  const factory _Major(
          @HiveField(0) final String code, @HiveField(1) final String name) =
      _$MajorImpl;

  factory _Major.fromJson(Map<String, dynamic> json) = _$MajorImpl.fromJson;

  @override
  @HiveField(0)
  String get code;
  @override
  @HiveField(1)
  String get name;
  @override
  @JsonKey(ignore: true)
  _$$MajorImplCopyWith<_$MajorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
