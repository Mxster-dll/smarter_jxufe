// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'CourseNature.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CourseNatureAdapter extends TypeAdapter<CourseNature> {
  @override
  final int typeId = 3;

  @override
  CourseNature read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return CourseNature.theory;
      case 1:
        return CourseNature.practical;
      case 2:
        return CourseNature.unknown;
      default:
        return CourseNature.theory;
    }
  }

  @override
  void write(BinaryWriter writer, CourseNature obj) {
    switch (obj) {
      case CourseNature.theory:
        writer.writeByte(0);
        break;
      case CourseNature.practical:
        writer.writeByte(1);
        break;
      case CourseNature.unknown:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseNatureAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
