// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'major.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MajorAdapter extends TypeAdapter<Major> {
  @override
  final int typeId = 8;

  @override
  Major read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Major(
      fields[0] as String,
      fields[1] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Major obj) {
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
      other is MajorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MajorImpl _$$MajorImplFromJson(Map<String, dynamic> json) => _$MajorImpl(
      json['code'] as String,
      json['name'] as String,
    );

Map<String, dynamic> _$$MajorImplToJson(_$MajorImpl instance) =>
    <String, dynamic>{
      'code': instance.code,
      'name': instance.name,
    };
