class AiSchedulingResponse {
  final String intent;
  final String? eventTitleTokenized;
  final String? locationTokenized;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<String> participantsTokenized;
  final String aiReplyMessage;

  AiSchedulingResponse({
    required this.intent,
    this.eventTitleTokenized,
    this.locationTokenized,
    this.startTime,
    this.endTime,
    required this.participantsTokenized,
    required this.aiReplyMessage,
  });

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
