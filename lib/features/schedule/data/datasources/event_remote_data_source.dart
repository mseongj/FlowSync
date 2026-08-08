import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';

/// Describes a real-time change on a calendar event row.
class RealtimeEventChange {
  final String type; // INSERT, UPDATE, DELETE
  final CalendarEvent? event; // null on DELETE
  final String? deletedId; // set on DELETE

  RealtimeEventChange({required this.type, this.event, this.deletedId});
}

@injectable
class EventRemoteDataSource {
  final SupabaseClient _supabase;

  EventRemoteDataSource(this._supabase);

  /// Pushes a [CalendarEvent] to the Supabase `calendar_events` table.
  Future<void> pushEvent(CalendarEvent event) async {
    await _supabase
        .from('calendar_events')
        .upsert(event.toSupabaseJson());
  }

  /// Subscribes to real-time changes on `calendar_events` for a given family.
  /// Returns a [RealtimeChannel] — call `.unsubscribe()` on dispose.
  RealtimeChannel subscribeToFamilyEvents({
    required String familyId,
    required void Function(RealtimeEventChange change) onEvent,
  }) {
    final currentUserId = _supabase.auth.currentUser?.id;

    final channel = _supabase.channel('family-events-$familyId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calendar_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            try {
              final eventType = payload.eventType.name.toUpperCase();

              if (eventType == 'DELETE') {
                final oldRecord = payload.oldRecord;
                final deletedId = oldRecord['id'] as String?;
                onEvent(RealtimeEventChange(
                  type: 'DELETE',
                  deletedId: deletedId,
                ));
                return;
              }

              // INSERT or UPDATE
              final json = payload.newRecord;
              if (json.isEmpty) return;

              final creatorId = json['creator_id'] as String?;
              final isOwn = creatorId == currentUserId;
              final visibility =
                  _visibilityFromString(json['visibility'] as String?);

              CalendarEvent parsedEvent;

              // PRIVATE events from others → redact
              if (!isOwn && visibility == EventVisibility.private) {
                parsedEvent = CalendarEvent(
                  id: json['id'] as String,
                  familyId: json['family_id'] as String,
                  creatorId: creatorId ?? '',
                  title: '바쁨',
                  description: '',
                  location: '',
                  startTime: DateTime.parse(json['start_time'] as String)
                      .toLocal(),
                  endTime: DateTime.parse(json['end_time'] as String)
                      .toLocal(),
                  visibility: EventVisibility.private,
                  creatorName: '가족',
                );
              } else {
                parsedEvent = CalendarEvent.fromSupabaseJson(
                  json,
                  creatorName: isOwn ? null : '가족',
                );
              }

              onEvent(RealtimeEventChange(
                type: eventType,
                event: parsedEvent,
              ));
            } catch (e) {
              debugPrint('⚠️ Realtime parse error: $e');
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// Fetches all events for [familyId] in the given date range.
  Future<List<CalendarEvent>> fetchFamilyEvents({
    required String familyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;

    // Fetch all members' display names first (name may not exist → use empty)
    final membersResponse = await _supabase
        .from('family_members')
        .select('user_id, display_name')
        .eq('family_id', familyId);

    final nameMap = <String, String>{};
    for (final m in membersResponse as List<dynamic>) {
      final row = m as Map<String, dynamic>;
      nameMap[row['user_id'] as String] =
          row['display_name'] as String? ?? '';
    }

    // Fetch events for the date range, filtered by family_id (RLS applies)
    final response = await _supabase
        .from('calendar_events')
        .select()
        .eq('family_id', familyId)
        .gte('start_time', from.toUtc().toIso8601String())
        .lte('start_time', to.toUtc().toIso8601String())
        .order('start_time');

    final events = <CalendarEvent>[];
    for (final row in response as List<dynamic>) {
      final json = row as Map<String, dynamic>;
      final creatorId = json['creator_id'] as String?;
      final isOwn = creatorId == currentUserId;
      final creatorName = isOwn ? null : (nameMap[creatorId] ?? '가족');

      final visibility = _visibilityFromString(json['visibility'] as String?);

      // PRIVATE events from other users → redact fields
      if (!isOwn && visibility == EventVisibility.private) {
        events.add(CalendarEvent(
          id: json['id'] as String,
          familyId: json['family_id'] as String,
          creatorId: creatorId ?? '',
          title: '바쁨',
          description: '',
          location: '',
          startTime:
              DateTime.parse(json['start_time'] as String).toLocal(),
          endTime: DateTime.parse(json['end_time'] as String).toLocal(),
          visibility: EventVisibility.private,
          creatorName: creatorName,
        ));
      } else {
        events.add(
          CalendarEvent.fromSupabaseJson(json, creatorName: creatorName),
        );
      }
    }

    return events;
  }

  static EventVisibility _visibilityFromString(String? value) {
    return switch (value) {
      'private' => EventVisibility.private,
      'secret'  => EventVisibility.secret,
      _         => EventVisibility.public,
    };
  }
}
