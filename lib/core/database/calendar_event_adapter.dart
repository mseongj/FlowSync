import 'package:hive_flutter/hive_flutter.dart';
import '../../features/schedule/domain/entities/calendar_event.dart';

class EventVisibilityAdapter extends TypeAdapter<EventVisibility> {
  @override
  final int typeId = 0;

  @override
  EventVisibility read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return EventVisibility.public;
      case 1:
        return EventVisibility.private;
      case 2:
        return EventVisibility.secret;
      default:
        return EventVisibility.public;
    }
  }

  @override
  void write(BinaryWriter writer, EventVisibility obj) {
    switch (obj) {
      case EventVisibility.public:
        writer.writeByte(0);
        break;
      case EventVisibility.private:
        writer.writeByte(1);
        break;
      case EventVisibility.secret:
        writer.writeByte(2);
        break;
    }
  }
}

class CalendarEventAdapter extends TypeAdapter<CalendarEvent> {
  @override
  final int typeId = 1;

  @override
  CalendarEvent read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CalendarEvent(
      id: fields[0] as String,
      familyId: fields[1] as String,
      creatorId: fields[2] as String,
      title: fields[3] as String,
      description: fields[4] as String,
      location: fields[5] as String,
      startTime: fields[6] as DateTime,
      endTime: fields[7] as DateTime,
      visibility: fields[8] as EventVisibility,
      isOfflineCreated: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, CalendarEvent obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.familyId)
      ..writeByte(2)
      ..write(obj.creatorId)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.location)
      ..writeByte(6)
      ..write(obj.startTime)
      ..writeByte(7)
      ..write(obj.endTime)
      ..writeByte(8)
      ..write(obj.visibility)
      ..writeByte(9)
      ..write(obj.isOfflineCreated);
  }
}
