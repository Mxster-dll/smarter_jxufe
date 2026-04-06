// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'curriculum.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$Curriculum {
  @HiveField(0)
  int get year => throw _privateConstructorUsedError;
  @HiveField(1)
  College get college => throw _privateConstructorUsedError;
  @HiveField(2)
  Major get major => throw _privateConstructorUsedError;
  @HiveField(3)
  List<Course> get courses => throw _privateConstructorUsedError;
  @HiveField(4)
  DateTime? get lastUpdated => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $CurriculumCopyWith<Curriculum> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurriculumCopyWith<$Res> {
  factory $CurriculumCopyWith(
          Curriculum value, $Res Function(Curriculum) then) =
      _$CurriculumCopyWithImpl<$Res, Curriculum>;
  @useResult
  $Res call(
      {@HiveField(0) int year,
      @HiveField(1) College college,
      @HiveField(2) Major major,
      @HiveField(3) List<Course> courses,
      @HiveField(4) DateTime? lastUpdated});
}

/// @nodoc
class _$CurriculumCopyWithImpl<$Res, $Val extends Curriculum>
    implements $CurriculumCopyWith<$Res> {
  _$CurriculumCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? year = null,
    Object? college = null,
    Object? major = null,
    Object? courses = null,
    Object? lastUpdated = freezed,
  }) {
    return _then(_value.copyWith(
      year: null == year
          ? _value.year
          : year // ignore: cast_nullable_to_non_nullable
              as int,
      college: null == college
          ? _value.college
          : college // ignore: cast_nullable_to_non_nullable
              as College,
      major: null == major
          ? _value.major
          : major // ignore: cast_nullable_to_non_nullable
              as Major,
      courses: null == courses
          ? _value.courses
          : courses // ignore: cast_nullable_to_non_nullable
              as List<Course>,
      lastUpdated: freezed == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CurriculumImplCopyWith<$Res>
    implements $CurriculumCopyWith<$Res> {
  factory _$$CurriculumImplCopyWith(
          _$CurriculumImpl value, $Res Function(_$CurriculumImpl) then) =
      __$$CurriculumImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@HiveField(0) int year,
      @HiveField(1) College college,
      @HiveField(2) Major major,
      @HiveField(3) List<Course> courses,
      @HiveField(4) DateTime? lastUpdated});
}

/// @nodoc
class __$$CurriculumImplCopyWithImpl<$Res>
    extends _$CurriculumCopyWithImpl<$Res, _$CurriculumImpl>
    implements _$$CurriculumImplCopyWith<$Res> {
  __$$CurriculumImplCopyWithImpl(
      _$CurriculumImpl _value, $Res Function(_$CurriculumImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? year = null,
    Object? college = null,
    Object? major = null,
    Object? courses = null,
    Object? lastUpdated = freezed,
  }) {
    return _then(_$CurriculumImpl(
      year: null == year
          ? _value.year
          : year // ignore: cast_nullable_to_non_nullable
              as int,
      college: null == college
          ? _value.college
          : college // ignore: cast_nullable_to_non_nullable
              as College,
      major: null == major
          ? _value.major
          : major // ignore: cast_nullable_to_non_nullable
              as Major,
      courses: null == courses
          ? _value._courses
          : courses // ignore: cast_nullable_to_non_nullable
              as List<Course>,
      lastUpdated: freezed == lastUpdated
          ? _value.lastUpdated
          : lastUpdated // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc

class _$CurriculumImpl implements _Curriculum {
  const _$CurriculumImpl(
      {@HiveField(0) required this.year,
      @HiveField(1) required this.college,
      @HiveField(2) required this.major,
      @HiveField(3) required final List<Course> courses,
      @HiveField(4) this.lastUpdated})
      : _courses = courses;

  @override
  @HiveField(0)
  final int year;
  @override
  @HiveField(1)
  final College college;
  @override
  @HiveField(2)
  final Major major;
  final List<Course> _courses;
  @override
  @HiveField(3)
  List<Course> get courses {
    if (_courses is EqualUnmodifiableListView) return _courses;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_courses);
  }

  @override
  @HiveField(4)
  final DateTime? lastUpdated;

  @override
  String toString() {
    return 'Curriculum(year: $year, college: $college, major: $major, courses: $courses, lastUpdated: $lastUpdated)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurriculumImpl &&
            (identical(other.year, year) || other.year == year) &&
            (identical(other.college, college) || other.college == college) &&
            (identical(other.major, major) || other.major == major) &&
            const DeepCollectionEquality().equals(other._courses, _courses) &&
            (identical(other.lastUpdated, lastUpdated) ||
                other.lastUpdated == lastUpdated));
  }

  @override
  int get hashCode => Object.hash(runtimeType, year, college, major,
      const DeepCollectionEquality().hash(_courses), lastUpdated);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CurriculumImplCopyWith<_$CurriculumImpl> get copyWith =>
      __$$CurriculumImplCopyWithImpl<_$CurriculumImpl>(this, _$identity);
}

abstract class _Curriculum implements Curriculum {
  const factory _Curriculum(
      {@HiveField(0) required final int year,
      @HiveField(1) required final College college,
      @HiveField(2) required final Major major,
      @HiveField(3) required final List<Course> courses,
      @HiveField(4) final DateTime? lastUpdated}) = _$CurriculumImpl;

  @override
  @HiveField(0)
  int get year;
  @override
  @HiveField(1)
  College get college;
  @override
  @HiveField(2)
  Major get major;
  @override
  @HiveField(3)
  List<Course> get courses;
  @override
  @HiveField(4)
  DateTime? get lastUpdated;
  @override
  @JsonKey(ignore: true)
  _$$CurriculumImplCopyWith<_$CurriculumImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
