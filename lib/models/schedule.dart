enum ScheduleCategory {
  meeting,
  personal,
  deadline,
  other
}

class Schedule {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final String? location;
  final ScheduleCategory category;
  final String? description;
  final bool isAIRecommended;

  Schedule({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    this.location,
    required this.category,
    this.description,
    this.isAIRecommended = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'location': location,
      'category': category.name,
      'description': description,
      'isAIRecommended': isAIRecommended,
    };
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as String,
      title: json['title'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      location: json['location'] as String?,
      category: ScheduleCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ScheduleCategory.other,
      ),
      description: json['description'] as String?,
      isAIRecommended: json['isAIRecommended'] as bool? ?? false,
    );
  }
}
