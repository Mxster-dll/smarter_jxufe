// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'function_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FunctionTypeAdapter extends TypeAdapter<FunctionType> {
  @override
  final int typeId = 7;

  @override
  FunctionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FunctionType.curriculum;
      default:
        return FunctionType.curriculum;
    }
  }

  @override
  void write(BinaryWriter writer, FunctionType obj) {
    switch (obj) {
      case FunctionType.curriculum:
        writer.writeByte(0);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
