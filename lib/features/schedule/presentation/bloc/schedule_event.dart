part of 'schedule_bloc.dart';

abstract class ScheduleEvent {}

class ScheduleStarted extends ScheduleEvent {}

class ScheduleDateSelected extends ScheduleEvent {
  final DateTime date;
  ScheduleDateSelected(this.date);
}

class ScheduleEventsUpdated extends ScheduleEvent {
  // Triggered when Hive stream emits a change
}

class ScheduleEventSaved extends ScheduleEvent {
  final CalendarEvent event;
  ScheduleEventSaved(this.event);
}

class ScheduleEventDeleted extends ScheduleEvent {
  final String eventId;
  ScheduleEventDeleted(this.eventId);
}

/// Fired when the device's connectivity status changes.
/// [isOnline] is true when the device has any network connection.
class ScheduleConnectivityChanged extends ScheduleEvent {
  final bool isOnline;
  ScheduleConnectivityChanged({required this.isOnline});
}
