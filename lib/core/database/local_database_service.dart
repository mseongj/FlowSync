import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';
import 'calendar_event_adapter.dart';
import '../../features/schedule/domain/entities/calendar_event.dart';

@lazySingleton
class LocalDatabaseService {
  Future<void> initialize() async {
    await Hive.initFlutter();
    Hive.registerAdapter(EventVisibilityAdapter());
    Hive.registerAdapter(CalendarEventAdapter());
    
    await Hive.openBox('calendar_events');
  }

  Future<void> saveEvent(CalendarEvent event) async {
    final box = Hive.box('calendar_events');
    await box.put(event.id, event);
  }

  List<CalendarEvent> getEventsForDay(DateTime date) {
    final box = Hive.box('calendar_events');
    return box.values
        .whereType<CalendarEvent>()
        .where((e) {
          final start = e.startTime;
          return start.year == date.year &&
                 start.month == date.month &&
                 start.day == date.day;
        })
        .toList();
  }

  List<CalendarEvent> getAllEvents() {
    final box = Hive.box('calendar_events');
    return box.values.whereType<CalendarEvent>().toList();
  }

  Stream<BoxEvent> watchEvents() {
    return Hive.box('calendar_events').watch();
  }
}
