// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'major.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MajorAdapter extends TypeAdapter<Major> {
  @override
  final int typeId = 1;

  @override
  Major read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Major(
      id: fields[0] as String,
      name: fields[1] as String,
      code: fields[2] as String,
      year: fields[3] as int,
      collegeName: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Major obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.code)
      ..writeByte(3)
      ..write(obj.year)
      ..writeByte(4)
      ..write(obj.collegeName);
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
