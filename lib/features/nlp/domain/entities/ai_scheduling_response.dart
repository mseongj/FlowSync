/// Represents a detected scheduling conflict with an existing event.
class ScheduleConflict {
  final String existingEventTitle;
  final String? existingStartTime;
  final String? existingEndTime;
  final int? overlapMinutes;

  const ScheduleConflict({
    required this.existingEventTitle,
    this.existingStartTime,
    this.existingEndTime,
    this.overlapMinutes,
  });

  factory ScheduleConflict.fromJson(Map<String, dynamic> json) {
    return ScheduleConflict(
      existingEventTitle: json['existingEventTitle'] as String? ?? '',
      existingStartTime: json['existingStartTime'] as String?,
      existingEndTime: json['existingEndTime'] as String?,
      overlapMinutes: (json['overlapMinutes'] as num?)?.toInt(),
    );
  }
}

class AiSchedulingResponse {
  final String intent;
  final String? eventTitleTokenized;
  final String? locationTokenized;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<String> participantsTokenized;
  final String aiReplyMessage;
  final List<ScheduleConflict> conflicts;

  AiSchedulingResponse({
    required this.intent,
    this.eventTitleTokenized,
    this.locationTokenized,
    this.startTime,
    this.endTime,
    required this.participantsTokenized,
    required this.aiReplyMessage,
    this.conflicts = const [],
  });

  /// Whether any scheduling conflicts were detected.
  bool get hasConflicts => conflicts.isNotEmpty;

  factory AiSchedulingResponse.fromJson(Map<String, dynamic> json) {
    return AiSchedulingResponse(
      intent: json['intent'] as String? ?? 'UNKNOWN',
      eventTitleTokenized: json['eventTitleTokenized'] as String?,
      locationTokenized: json['locationTokenized'] as String?,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      participantsTokenized: List<String>.from(
        (json['participantsTokenized'] as Iterable<dynamic>?) ?? [],
      ),
      aiReplyMessage: json['aiReplyMessage'] as String? ?? '',
      conflicts: (json['conflicts'] as List<dynamic>?)
              ?.map((c) =>
                  ScheduleConflict.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Hydrates the tokenized response back into raw text using the local TokenMap
  String hydrateMessage(Map<String, String> tokenMap) {
    String hydrated = aiReplyMessage;
    tokenMap.forEach((token, rawValue) {
      hydrated = hydrated.replaceAll(token, rawValue);
    });
    return hydrated;
  }
}
