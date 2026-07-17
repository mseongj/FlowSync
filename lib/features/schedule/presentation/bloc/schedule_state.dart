part of 'schedule_bloc.dart';

abstract class ScheduleState {}

class ScheduleLoading extends ScheduleState {}

class ScheduleLoaded extends ScheduleState {
  final DateTime selectedDate;
  final List<CalendarEvent> selectedDateEvents;
  final List<CalendarEvent> allEvents; // useful for marking days with events on calendar

  ScheduleLoaded({
    required this.selectedDate,
    required this.selectedDateEvents,
    required this.allEvents,
  });

  ScheduleLoaded copyWith({
    DateTime? selectedDate,
    List<CalendarEvent>? selectedDateEvents,
    List<CalendarEvent>? allEvents,
  }) {
    return ScheduleLoaded(
      selectedDate: selectedDate ?? this.selectedDate,
      selectedDateEvents: selectedDateEvents ?? this.selectedDateEvents,
      allEvents: allEvents ?? this.allEvents,
    );
  }
}

class ScheduleError extends ScheduleState {
  final String message;
  ScheduleError(this.message);
}
