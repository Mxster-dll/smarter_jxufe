// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'college.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CollegeAdapter extends TypeAdapter<College> {
  @override
  final int typeId = 7;

  @override
  College read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return College(
      fields[0] as String,
      fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, College obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.code)
      ..writeByte(1)
      ..write(obj.name);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollegeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CollegeImpl _$$CollegeImplFromJson(Map<String, dynamic> json) =>
    _$CollegeImpl(
      json['code'] as String,
      json['name'] as String,
    );

Map<String, dynamic> _$$CollegeImplToJson(_$CollegeImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
    };
