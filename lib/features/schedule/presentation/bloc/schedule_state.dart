part of 'schedule_bloc.dart';

abstract class ScheduleState {}

class ScheduleLoading extends ScheduleState {}

class ScheduleLoaded extends ScheduleState {
  final DateTime selectedDate;
  final List<CalendarEvent> selectedDateEvents;
  /// All events — used for marking days on the calendar.
  final List<CalendarEvent> allEvents;
  /// The family group ID if this user belongs to one; null otherwise.
  final String? familyId;

  ScheduleLoaded({
    required this.selectedDate,
    required this.selectedDateEvents,
    required this.allEvents,
    this.familyId,
  });

  bool get isFamilyView => familyId != null;

  ScheduleLoaded copyWith({
    DateTime? selectedDate,
    List<CalendarEvent>? selectedDateEvents,
    List<CalendarEvent>? allEvents,
    String? familyId,
  }) {
    return ScheduleLoaded(
      selectedDate: selectedDate ?? this.selectedDate,
      selectedDateEvents: selectedDateEvents ?? this.selectedDateEvents,
      allEvents: allEvents ?? this.allEvents,
      familyId: familyId ?? this.familyId,
    );
  }
}

class ScheduleError extends ScheduleState {
  final String message;
  ScheduleError(this.message);
}
