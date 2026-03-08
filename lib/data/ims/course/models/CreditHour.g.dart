// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'CreditHour.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CreditHourAdapter extends TypeAdapter<CreditHour> {
  @override
  final int typeId = 6;

  @override
  CreditHour read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CreditHour(
      total: fields[0] as int,
      lecture: fields[1] as int,
      lab: fields[2] as int,
      practice: fields[3] as int,
      other: fields[4] as int,
      weekly: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CreditHour obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.total)
      ..writeByte(1)
      ..write(obj.lecture)
      ..writeByte(2)
      ..write(obj.lab)
      ..writeByte(3)
      ..write(obj.practice)
      ..writeByte(4)
      ..write(obj.other)
      ..writeByte(5)
      ..write(obj.weekly);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreditHourAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CreditHourImpl _$$CreditHourImplFromJson(Map<String, dynamic> json) =>
    _$CreditHourImpl(
      total: (json['total'] as num).toInt(),
      lecture: (json['lecture'] as num).toInt(),
      lab: (json['lab'] as num).toInt(),
      practice: (json['practice'] as num).toInt(),
      other: (json['other'] as num).toInt(),
      weekly: (json['weekly'] as num).toDouble(),
    );

Map<String, dynamic> _$$CreditHourImplToJson(_$CreditHourImpl instance) =>
    <String, dynamic>{
      'total': instance.total,
      'lecture': instance.lecture,
      'lab': instance.lab,
      'practice': instance.practice,
      'other': instance.other,
      'weekly': instance.weekly,
    };
