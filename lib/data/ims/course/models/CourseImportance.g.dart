// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'CourseImportance.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CourseImportanceAdapter extends TypeAdapter<CourseImportance> {
  @override
  final int typeId = 5;

  @override
  CourseImportance read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return CourseImportance.core;
      case 1:
        return CourseImportance.general;
      case 2:
        return CourseImportance.unknown;
      default:
        return CourseImportance.core;
    }
  }

  @override
  void write(BinaryWriter writer, CourseImportance obj) {
    switch (obj) {
      case CourseImportance.core:
        writer.writeByte(0);
        break;
      case CourseImportance.general:
        writer.writeByte(1);
        break;
      case CourseImportance.unknown:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseImportanceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
