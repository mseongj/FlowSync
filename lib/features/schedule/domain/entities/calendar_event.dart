enum EventVisibility { public, private, secret }

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
  });

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
    );
  }
}
