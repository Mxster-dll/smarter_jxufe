// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'CreditHour.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CreditHour _$CreditHourFromJson(Map<String, dynamic> json) {
  return _CreditHour.fromJson(json);
}

/// @nodoc
mixin _$CreditHour {
  @HiveField(0)
  int get total => throw _privateConstructorUsedError;
  @HiveField(1)
  int get lecture => throw _privateConstructorUsedError;
  @HiveField(2)
  int get lab => throw _privateConstructorUsedError;
  @HiveField(3)
  int get practice => throw _privateConstructorUsedError;
  @HiveField(4)
  int get other => throw _privateConstructorUsedError;
  @HiveField(5)
  double get weekly => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CreditHourCopyWith<CreditHour> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreditHourCopyWith<$Res> {
  factory $CreditHourCopyWith(
          CreditHour value, $Res Function(CreditHour) then) =
      _$CreditHourCopyWithImpl<$Res, CreditHour>;
  @useResult
  $Res call(
      {@HiveField(0) int total,
      @HiveField(1) int lecture,
      @HiveField(2) int lab,
      @HiveField(3) int practice,
      @HiveField(4) int other,
      @HiveField(5) double weekly});
}

/// @nodoc
class _$CreditHourCopyWithImpl<$Res, $Val extends CreditHour>
    implements $CreditHourCopyWith<$Res> {
  _$CreditHourCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? total = null,
    Object? lecture = null,
    Object? lab = null,
    Object? practice = null,
    Object? other = null,
    Object? weekly = null,
  }) {
    return _then(_value.copyWith(
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      lecture: null == lecture
          ? _value.lecture
          : lecture // ignore: cast_nullable_to_non_nullable
              as int,
      lab: null == lab
          ? _value.lab
          : lab // ignore: cast_nullable_to_non_nullable
              as int,
      practice: null == practice
          ? _value.practice
          : practice // ignore: cast_nullable_to_non_nullable
              as int,
      other: null == other
          ? _value.other
          : other // ignore: cast_nullable_to_non_nullable
              as int,
      weekly: null == weekly
          ? _value.weekly
          : weekly // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreditHourImplCopyWith<$Res>
    implements $CreditHourCopyWith<$Res> {
  factory _$$CreditHourImplCopyWith(
          _$CreditHourImpl value, $Res Function(_$CreditHourImpl) then) =
      __$$CreditHourImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@HiveField(0) int total,
      @HiveField(1) int lecture,
      @HiveField(2) int lab,
      @HiveField(3) int practice,
      @HiveField(4) int other,
      @HiveField(5) double weekly});
}

/// @nodoc
class __$$CreditHourImplCopyWithImpl<$Res>
    extends _$CreditHourCopyWithImpl<$Res, _$CreditHourImpl>
    implements _$$CreditHourImplCopyWith<$Res> {
  __$$CreditHourImplCopyWithImpl(
      _$CreditHourImpl _value, $Res Function(_$CreditHourImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? total = null,
    Object? lecture = null,
    Object? lab = null,
    Object? practice = null,
    Object? other = null,
    Object? weekly = null,
  }) {
    return _then(_$CreditHourImpl(
      total: null == total
          ? _value.total
          : total // ignore: cast_nullable_to_non_nullable
              as int,
      lecture: null == lecture
          ? _value.lecture
          : lecture // ignore: cast_nullable_to_non_nullable
              as int,
      lab: null == lab
          ? _value.lab
          : lab // ignore: cast_nullable_to_non_nullable
              as int,
      practice: null == practice
          ? _value.practice
          : practice // ignore: cast_nullable_to_non_nullable
              as int,
      other: null == other
          ? _value.other
          : other // ignore: cast_nullable_to_non_nullable
              as int,
      weekly: null == weekly
          ? _value.weekly
          : weekly // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CreditHourImpl implements _CreditHour {
  const _$CreditHourImpl(
      {@HiveField(0) required this.total,
      @HiveField(1) required this.lecture,
      @HiveField(2) required this.lab,
      @HiveField(3) required this.practice,
      @HiveField(4) required this.other,
      @HiveField(5) required this.weekly});

  factory _$CreditHourImpl.fromJson(Map<String, dynamic> json) =>
      _$$CreditHourImplFromJson(json);

  @override
  @HiveField(0)
  final int total;
  @override
  @HiveField(1)
  final int lecture;
  @override
  @HiveField(2)
  final int lab;
  @override
  @HiveField(3)
  final int practice;
  @override
  @HiveField(4)
  final int other;
  @override
  @HiveField(5)
  final double weekly;

  @override
  String toString() {
    return 'CreditHour(total: $total, lecture: $lecture, lab: $lab, practice: $practice, other: $other, weekly: $weekly)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreditHourImpl &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.lecture, lecture) || other.lecture == lecture) &&
            (identical(other.lab, lab) || other.lab == lab) &&
            (identical(other.practice, practice) ||
                other.practice == practice) &&
            (identical(other.other, this.other) || other.other == this.other) &&
            (identical(other.weekly, weekly) || other.weekly == weekly));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, total, lecture, lab, practice, other, weekly);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreditHourImplCopyWith<_$CreditHourImpl> get copyWith =>
      __$$CreditHourImplCopyWithImpl<_$CreditHourImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CreditHourImplToJson(
      this,
    );
  }
}

abstract class _CreditHour implements CreditHour {
  const factory _CreditHour(
      {@HiveField(0) required final int total,
      @HiveField(1) required final int lecture,
      @HiveField(2) required final int lab,
      @HiveField(3) required final int practice,
      @HiveField(4) required final int other,
      @HiveField(5) required final double weekly}) = _$CreditHourImpl;

  factory _CreditHour.fromJson(Map<String, dynamic> json) =
      _$CreditHourImpl.fromJson;

  @override
  @HiveField(0)
  int get total;
  @override
  @HiveField(1)
  int get lecture;
  @override
  @HiveField(2)
  int get lab;
  @override
  @HiveField(3)
  int get practice;
  @override
  @HiveField(4)
  int get other;
  @override
  @HiveField(5)
  double get weekly;
  @override
  @JsonKey(ignore: true)
  _$$CreditHourImplCopyWith<_$CreditHourImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
