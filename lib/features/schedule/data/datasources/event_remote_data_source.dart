import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/calendar_event.dart';

@injectable
class EventRemoteDataSource {
  final SupabaseClient _supabase;

  EventRemoteDataSource(this._supabase);

  /// Pushes a [CalendarEvent] to the Supabase `calendar_events` table using upsert.
  Future<void> pushEvent(CalendarEvent event) async {
    await _supabase
        .from('calendar_events')
        .upsert(event.toSupabaseJson());
  }
}
