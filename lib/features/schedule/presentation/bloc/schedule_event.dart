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
