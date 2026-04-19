// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'curriculum.dart';

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
      collegeId: fields[1] as String,
      majorId: fields[2] as String,
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
      ..write(obj.collegeId)
      ..writeByte(2)
      ..write(obj.majorId)
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
