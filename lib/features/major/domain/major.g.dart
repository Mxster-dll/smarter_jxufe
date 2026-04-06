// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'major.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MajorAdapter extends TypeAdapter<Major> {
  @override
  final int typeId = 10;

  @override
  Major read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Major(
      fields[0] as String,
      fields[1] as String,
      functionIdIn: (fields[2] as Map?)?.cast<FunctionType, String>(),
    ).._aliases = (fields[3] as List).cast<String>();
  }

  @override
  void write(BinaryWriter writer, Major obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.standardName)
      ..writeByte(2)
      ..write(obj.functionIdIn)
      ..writeByte(3)
      ..write(obj._aliases);
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
