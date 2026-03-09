// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_requirement.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CourseRequirementAdapter extends TypeAdapter<CourseRequirement> {
  @override
  final int typeId = 0;

  @override
  CourseRequirement read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return CourseRequirement.required;
      case 1:
        return CourseRequirement.elective;
      case 2:
        return CourseRequirement.restricted;
      case 3:
        return CourseRequirement.free;
      case 4:
        return CourseRequirement.excellence;
      case 5:
        return CourseRequirement.topNotch;
      case 6:
        return CourseRequirement.innovation;
      case 7:
        return CourseRequirement.major;
      case 8:
        return CourseRequirement.unknown;
      default:
        return CourseRequirement.required;
    }
  }

  @override
  void write(BinaryWriter writer, CourseRequirement obj) {
    switch (obj) {
      case CourseRequirement.required:
        writer.writeByte(0);
        break;
      case CourseRequirement.elective:
        writer.writeByte(1);
        break;
      case CourseRequirement.restricted:
        writer.writeByte(2);
        break;
      case CourseRequirement.free:
        writer.writeByte(3);
        break;
      case CourseRequirement.excellence:
        writer.writeByte(4);
        break;
      case CourseRequirement.topNotch:
        writer.writeByte(5);
        break;
      case CourseRequirement.innovation:
        writer.writeByte(6);
        break;
      case CourseRequirement.major:
        writer.writeByte(7);
        break;
      case CourseRequirement.unknown:
        writer.writeByte(8);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourseRequirementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
