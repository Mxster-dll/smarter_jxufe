// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assessment_method.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssessmentMethodAdapter extends TypeAdapter<AssessmentMethod> {
  @override
  final int typeId = 4;

  @override
  AssessmentMethod read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssessmentMethod.exam;
      case 1:
        return AssessmentMethod.coursework;
      case 2:
        return AssessmentMethod.unknown;
      default:
        return AssessmentMethod.exam;
    }
  }

  @override
  void write(BinaryWriter writer, AssessmentMethod obj) {
    switch (obj) {
      case AssessmentMethod.exam:
        writer.writeByte(0);
        break;
      case AssessmentMethod.coursework:
        writer.writeByte(1);
        break;
      case AssessmentMethod.unknown:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssessmentMethodAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
