// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'Course.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Course _$CourseFromJson(Map<String, dynamic> json) {
  return _Course.fromJson(json);
}

/// @nodoc
mixin _$Course {
  @HiveField(1)
  String get code => throw _privateConstructorUsedError;
  @HiveField(2)
  String get name => throw _privateConstructorUsedError;
  @HiveField(3)
  double get credit => throw _privateConstructorUsedError;
  @HiveField(4)
  CreditHour get creditHour => throw _privateConstructorUsedError;
  @HiveField(5)
  String get mainCategory => throw _privateConstructorUsedError;
  @HiveField(6)
  String get subCategory => throw _privateConstructorUsedError;
  @HiveField(7)
  String? get tertiaryCategory => throw _privateConstructorUsedError;
  @HiveField(8)
  CourseRequirement get requirement => throw _privateConstructorUsedError;
  @HiveField(9)
  CourseNature get nature => throw _privateConstructorUsedError;
  @HiveField(10)
  CourseImportance get importance => throw _privateConstructorUsedError;
  @HiveField(11)
  AssessmentMethod get assessmentMethod => throw _privateConstructorUsedError;
  @HiveField(12)
  String get identification => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CourseCopyWith<Course> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CourseCopyWith<$Res> {
  factory $CourseCopyWith(Course value, $Res Function(Course) then) =
      _$CourseCopyWithImpl<$Res, Course>;
  @useResult
  $Res call(
      {@HiveField(1) String code,
      @HiveField(2) String name,
      @HiveField(3) double credit,
      @HiveField(4) CreditHour creditHour,
      @HiveField(5) String mainCategory,
      @HiveField(6) String subCategory,
      @HiveField(7) String? tertiaryCategory,
      @HiveField(8) CourseRequirement requirement,
      @HiveField(9) CourseNature nature,
      @HiveField(10) CourseImportance importance,
      @HiveField(11) AssessmentMethod assessmentMethod,
      @HiveField(12) String identification});

  $CreditHourCopyWith<$Res> get creditHour;
}

/// @nodoc
class _$CourseCopyWithImpl<$Res, $Val extends Course>
    implements $CourseCopyWith<$Res> {
  _$CourseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
    Object? credit = null,
    Object? creditHour = null,
    Object? mainCategory = null,
    Object? subCategory = null,
    Object? tertiaryCategory = freezed,
    Object? requirement = null,
    Object? nature = null,
    Object? importance = null,
    Object? assessmentMethod = null,
    Object? identification = null,
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
      credit: null == credit
          ? _value.credit
          : credit // ignore: cast_nullable_to_non_nullable
              as double,
      creditHour: null == creditHour
          ? _value.creditHour
          : creditHour // ignore: cast_nullable_to_non_nullable
              as CreditHour,
      mainCategory: null == mainCategory
          ? _value.mainCategory
          : mainCategory // ignore: cast_nullable_to_non_nullable
              as String,
      subCategory: null == subCategory
          ? _value.subCategory
          : subCategory // ignore: cast_nullable_to_non_nullable
              as String,
      tertiaryCategory: freezed == tertiaryCategory
          ? _value.tertiaryCategory
          : tertiaryCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      requirement: null == requirement
          ? _value.requirement
          : requirement // ignore: cast_nullable_to_non_nullable
              as CourseRequirement,
      nature: null == nature
          ? _value.nature
          : nature // ignore: cast_nullable_to_non_nullable
              as CourseNature,
      importance: null == importance
          ? _value.importance
          : importance // ignore: cast_nullable_to_non_nullable
              as CourseImportance,
      assessmentMethod: null == assessmentMethod
          ? _value.assessmentMethod
          : assessmentMethod // ignore: cast_nullable_to_non_nullable
              as AssessmentMethod,
      identification: null == identification
          ? _value.identification
          : identification // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $CreditHourCopyWith<$Res> get creditHour {
    return $CreditHourCopyWith<$Res>(_value.creditHour, (value) {
      return _then(_value.copyWith(creditHour: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$CourseImplCopyWith<$Res> implements $CourseCopyWith<$Res> {
  factory _$$CourseImplCopyWith(
          _$CourseImpl value, $Res Function(_$CourseImpl) then) =
      __$$CourseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@HiveField(1) String code,
      @HiveField(2) String name,
      @HiveField(3) double credit,
      @HiveField(4) CreditHour creditHour,
      @HiveField(5) String mainCategory,
      @HiveField(6) String subCategory,
      @HiveField(7) String? tertiaryCategory,
      @HiveField(8) CourseRequirement requirement,
      @HiveField(9) CourseNature nature,
      @HiveField(10) CourseImportance importance,
      @HiveField(11) AssessmentMethod assessmentMethod,
      @HiveField(12) String identification});

  @override
  $CreditHourCopyWith<$Res> get creditHour;
}

/// @nodoc
class __$$CourseImplCopyWithImpl<$Res>
    extends _$CourseCopyWithImpl<$Res, _$CourseImpl>
    implements _$$CourseImplCopyWith<$Res> {
  __$$CourseImplCopyWithImpl(
      _$CourseImpl _value, $Res Function(_$CourseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
    Object? name = null,
    Object? credit = null,
    Object? creditHour = null,
    Object? mainCategory = null,
    Object? subCategory = null,
    Object? tertiaryCategory = freezed,
    Object? requirement = null,
    Object? nature = null,
    Object? importance = null,
    Object? assessmentMethod = null,
    Object? identification = null,
  }) {
    return _then(_$CourseImpl(
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      credit: null == credit
          ? _value.credit
          : credit // ignore: cast_nullable_to_non_nullable
              as double,
      creditHour: null == creditHour
          ? _value.creditHour
          : creditHour // ignore: cast_nullable_to_non_nullable
              as CreditHour,
      mainCategory: null == mainCategory
          ? _value.mainCategory
          : mainCategory // ignore: cast_nullable_to_non_nullable
              as String,
      subCategory: null == subCategory
          ? _value.subCategory
          : subCategory // ignore: cast_nullable_to_non_nullable
              as String,
      tertiaryCategory: freezed == tertiaryCategory
          ? _value.tertiaryCategory
          : tertiaryCategory // ignore: cast_nullable_to_non_nullable
              as String?,
      requirement: null == requirement
          ? _value.requirement
          : requirement // ignore: cast_nullable_to_non_nullable
              as CourseRequirement,
      nature: null == nature
          ? _value.nature
          : nature // ignore: cast_nullable_to_non_nullable
              as CourseNature,
      importance: null == importance
          ? _value.importance
          : importance // ignore: cast_nullable_to_non_nullable
              as CourseImportance,
      assessmentMethod: null == assessmentMethod
          ? _value.assessmentMethod
          : assessmentMethod // ignore: cast_nullable_to_non_nullable
              as AssessmentMethod,
      identification: null == identification
          ? _value.identification
          : identification // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CourseImpl implements _Course {
  const _$CourseImpl(
      {@HiveField(1) required this.code,
      @HiveField(2) required this.name,
      @HiveField(3) required this.credit,
      @HiveField(4) required this.creditHour,
      @HiveField(5) required this.mainCategory,
      @HiveField(6) required this.subCategory,
      @HiveField(7) required this.tertiaryCategory,
      @HiveField(8) required this.requirement,
      @HiveField(9) required this.nature,
      @HiveField(10) required this.importance,
      @HiveField(11) required this.assessmentMethod,
      @HiveField(12) required this.identification});

  factory _$CourseImpl.fromJson(Map<String, dynamic> json) =>
      _$$CourseImplFromJson(json);

  @override
  @HiveField(1)
  final String code;
  @override
  @HiveField(2)
  final String name;
  @override
  @HiveField(3)
  final double credit;
  @override
  @HiveField(4)
  final CreditHour creditHour;
  @override
  @HiveField(5)
  final String mainCategory;
  @override
  @HiveField(6)
  final String subCategory;
  @override
  @HiveField(7)
  final String? tertiaryCategory;
  @override
  @HiveField(8)
  final CourseRequirement requirement;
  @override
  @HiveField(9)
  final CourseNature nature;
  @override
  @HiveField(10)
  final CourseImportance importance;
  @override
  @HiveField(11)
  final AssessmentMethod assessmentMethod;
  @override
  @HiveField(12)
  final String identification;

  @override
  String toString() {
    return 'Course(code: $code, name: $name, credit: $credit, creditHour: $creditHour, mainCategory: $mainCategory, subCategory: $subCategory, tertiaryCategory: $tertiaryCategory, requirement: $requirement, nature: $nature, importance: $importance, assessmentMethod: $assessmentMethod, identification: $identification)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CourseImpl &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.credit, credit) || other.credit == credit) &&
            (identical(other.creditHour, creditHour) ||
                other.creditHour == creditHour) &&
            (identical(other.mainCategory, mainCategory) ||
                other.mainCategory == mainCategory) &&
            (identical(other.subCategory, subCategory) ||
                other.subCategory == subCategory) &&
            (identical(other.tertiaryCategory, tertiaryCategory) ||
                other.tertiaryCategory == tertiaryCategory) &&
            (identical(other.requirement, requirement) ||
                other.requirement == requirement) &&
            (identical(other.nature, nature) || other.nature == nature) &&
            (identical(other.importance, importance) ||
                other.importance == importance) &&
            (identical(other.assessmentMethod, assessmentMethod) ||
                other.assessmentMethod == assessmentMethod) &&
            (identical(other.identification, identification) ||
                other.identification == identification));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      code,
      name,
      credit,
      creditHour,
      mainCategory,
      subCategory,
      tertiaryCategory,
      requirement,
      nature,
      importance,
      assessmentMethod,
      identification);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CourseImplCopyWith<_$CourseImpl> get copyWith =>
      __$$CourseImplCopyWithImpl<_$CourseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CourseImplToJson(
      this,
    );
  }
}

abstract class _Course implements Course {
  const factory _Course(
      {@HiveField(1) required final String code,
      @HiveField(2) required final String name,
      @HiveField(3) required final double credit,
      @HiveField(4) required final CreditHour creditHour,
      @HiveField(5) required final String mainCategory,
      @HiveField(6) required final String subCategory,
      @HiveField(7) required final String? tertiaryCategory,
      @HiveField(8) required final CourseRequirement requirement,
      @HiveField(9) required final CourseNature nature,
      @HiveField(10) required final CourseImportance importance,
      @HiveField(11) required final AssessmentMethod assessmentMethod,
      @HiveField(12) required final String identification}) = _$CourseImpl;

  factory _Course.fromJson(Map<String, dynamic> json) = _$CourseImpl.fromJson;

  @override
  @HiveField(1)
  String get code;
  @override
  @HiveField(2)
  String get name;
  @override
  @HiveField(3)
  double get credit;
  @override
  @HiveField(4)
  CreditHour get creditHour;
  @override
  @HiveField(5)
  String get mainCategory;
  @override
  @HiveField(6)
  String get subCategory;
  @override
  @HiveField(7)
  String? get tertiaryCategory;
  @override
  @HiveField(8)
  CourseRequirement get requirement;
  @override
  @HiveField(9)
  CourseNature get nature;
  @override
  @HiveField(10)
  CourseImportance get importance;
  @override
  @HiveField(11)
  AssessmentMethod get assessmentMethod;
  @override
  @HiveField(12)
  String get identification;
  @override
  @JsonKey(ignore: true)
  _$$CourseImplCopyWith<_$CourseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
