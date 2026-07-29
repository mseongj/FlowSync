import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';

import 'package:flow_sync/core/crypto/event_crypto_service.dart';
import 'package:flow_sync/core/database/calendar_event_adapter.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';

@lazySingleton
class LocalDatabaseService {
  final EventCryptoService _crypto;

  LocalDatabaseService(this._crypto);

  Future<void> initialize() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(EventVisibilityAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(CalendarEventAdapter());
    }
    await Hive.openBox<CalendarEvent>('calendar_events');
  }

  /// Saves the event. For SECRET events, encrypts title/description/location
  /// before writing to Hive so plaintext never rests on disk unprotected.
  Future<void> saveEvent(CalendarEvent event) async {
    final box = Hive.box<CalendarEvent>('calendar_events');
    final isSecret = event.visibility == EventVisibility.secret;

    final storedEvent = isSecret
        ? event.copyWith(
            title: await _crypto.encrypt(event.title),
            description: await _crypto.encrypt(event.description),
            location: await _crypto.encrypt(event.location),
          )
        : event;

    await box.put(storedEvent.id, storedEvent);
  }

  /// Returns events for [date], decrypting SECRET fields on the fly.
  Future<List<CalendarEvent>> getEventsForDay(DateTime date) async {
    final box = Hive.box<CalendarEvent>('calendar_events');
    final raw = box.values
        .whereType<CalendarEvent>()
        .where((e) {
          final start = e.startTime;
          return start.year == date.year &&
              start.month == date.month &&
              start.day == date.day;
        })
        .toList();

    return _decryptAll(raw);
  }

  /// Returns all events, decrypting SECRET fields on the fly.
  Future<List<CalendarEvent>> getAllEvents() async {
    final box = Hive.box<CalendarEvent>('calendar_events');
    return _decryptAll(box.values.whereType<CalendarEvent>().toList());
  }

  Future<List<CalendarEvent>> _decryptAll(List<CalendarEvent> events) async {
    final result = <CalendarEvent>[];
    for (final e in events) {
      if (e.visibility == EventVisibility.secret) {
        result.add(
          e.copyWith(
            title: await _crypto.decryptIf(e.title, condition: true),
            description:
                await _crypto.decryptIf(e.description, condition: true),
            location: await _crypto.decryptIf(e.location, condition: true),
          ),
        );
      } else {
        result.add(e);
      }
    }
    return result;
  }

  Future<void> deleteEvent(String id) async {
    final box = Hive.box<CalendarEvent>('calendar_events');
    await box.delete(id);
  }

  Stream<BoxEvent> watchEvents() {
    return Hive.box<CalendarEvent>('calendar_events').watch();
  }
}
