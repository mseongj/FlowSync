enum EventVisibility {
  public,
  private,
  secret
}

class CalendarEvent {
  final String id;
  final String familyId;
  final String creatorId;
  final String title;
  final String description;
  final String location;
  final DateTime startTime;
  final DateTime endTime;
  final EventVisibility visibility;
  final bool isOfflineCreated;
  /// Display name of the creator — populated from Supabase join.
  /// Null for local-only events or the current user's own events.
  final String? creatorName;

  CalendarEvent({
    required this.id,
    required this.familyId,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.visibility,
    this.isOfflineCreated = false,
    this.creatorName,
  });

  /// Reconstructs a [CalendarEvent] from a Supabase `calendar_events` row.
  ///
  /// Pass [creatorName] when the query JOINs on `profiles.display_name`.
  factory CalendarEvent.fromSupabaseJson(
    Map<String, dynamic> json, {
    String? creatorName,
  }) {
    return CalendarEvent(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      endTime: DateTime.parse(json['end_time'] as String).toLocal(),
      visibility: _visibilityFromString(json['visibility'] as String?),
      isOfflineCreated: false,
      creatorName: creatorName,
    );
  }

  CalendarEvent copyWith({
    String? id,
    String? familyId,
    String? creatorId,
    String? title,
    String? description,
    String? location,
    DateTime? startTime,
    DateTime? endTime,
    EventVisibility? visibility,
    bool? isOfflineCreated,
    String? creatorName,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      familyId: familyId ?? this.familyId,
      creatorId: creatorId ?? this.creatorId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      visibility: visibility ?? this.visibility,
      isOfflineCreated: isOfflineCreated ?? this.isOfflineCreated,
      creatorName: creatorName ?? this.creatorName,
    );
  }

  /// Serializes this event into the payload expected by the Supabase
  /// `calendar_events` table.
  ///
  /// [isOfflineCreated] is intentionally omitted: it is a local-only sync
  /// flag and is not stored remotely. Timestamps are written as UTC ISO-8601
  /// strings for `timestamptz` columns.
  Map<String, dynamic> toSupabaseJson() {
    return <String, dynamic>{
      'id': id,
      'family_id': familyId,
      'creator_id': creatorId,
      'title': title,
      'description': description,
      'location': location,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime.toUtc().toIso8601String(),
      'visibility': visibility.name,
    };
  }

  static EventVisibility _visibilityFromString(String? value) {
    switch (value) {
      case 'private':
        return EventVisibility.private;
      case 'secret':
        return EventVisibility.secret;
      case 'public':
      default:
        return EventVisibility.public;
    }
  }
}
