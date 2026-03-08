// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'Curriculum.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CurriculumAdapter extends TypeAdapter<Curriculum> {
  @override
  final int typeId = 1;

  @override
  Curriculum read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Curriculum(
      year: fields[0] as int,
      collegeCode: fields[1] as String,
      majorCode: fields[2] as String,
      courses: (fields[3] as List).cast<Course>(),
      lastUpdated: fields[4] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Curriculum obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.year)
      ..writeByte(1)
      ..write(obj.collegeCode)
      ..writeByte(2)
      ..write(obj.majorCode)
      ..writeByte(3)
      ..write(obj.courses)
      ..writeByte(4)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurriculumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CurriculumImpl _$$CurriculumImplFromJson(Map<String, dynamic> json) =>
    _$CurriculumImpl(
      year: (json['year'] as num).toInt(),
      collegeCode: json['collegeCode'] as String,
      majorCode: json['majorCode'] as String,
      courses: (json['courses'] as List<dynamic>)
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.parse(json['lastUpdated'] as String),
    );

Map<String, dynamic> _$$CurriculumImplToJson(_$CurriculumImpl instance) =>
    <String, dynamic>{
      'year': instance.year,
      'collegeCode': instance.collegeCode,
      'majorCode': instance.majorCode,
      'courses': instance.courses,
      'lastUpdated': instance.lastUpdated?.toIso8601String(),
    };
