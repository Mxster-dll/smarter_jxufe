// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CourseAdapter extends TypeAdapter<Course> {
  @override
  final int typeId = 9;

  @override
  Course read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Course(
      code: fields[1] as String,
      name: fields[2] as String,
      credit: fields[3] as double,
      creditHour: fields[4] as CreditHour,
      mainCategory: fields[5] as String,
      subCategory: fields[6] as String,
      tertiaryCategory: fields[7] as String?,
      requirement: fields[8] as CourseRequirement,
      nature: fields[9] as CourseNature,
      importance: fields[10] as CourseImportance,
      assessmentMethod: fields[11] as AssessmentMethod,
      identification: fields[12] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Course obj) {
    writer
      ..writeByte(12)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.credit)
      ..writeByte(4)
      ..write(obj.creditHour)
      ..writeByte(5)
      ..write(obj.mainCategory)
      ..writeByte(6)
      ..write(obj.subCategory)
      ..writeByte(7)
      ..write(obj.tertiaryCategory)
      ..writeByte(8)
      ..write(obj.requirement)
      ..writeByte(9)
      ..write(obj.nature)
      ..writeByte(10)
      ..write(obj.importance)
      ..writeByte(11)
      ..write(obj.assessmentMethod)
      ..writeByte(12)
      ..write(obj.identification);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
