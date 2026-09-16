import '../../../../features/schedule/domain/entities/calendar_event.dart';

abstract class NlpInputEvent {}

class NlpMessageSent extends NlpInputEvent {
  final String text;
  NlpMessageSent(this.text);
}

class NlpEventConfirmed extends NlpInputEvent {
  final CalendarEvent event;
  NlpEventConfirmed(this.event);
}

class NlpEventCancelled extends NlpInputEvent {
  final String eventId;
  final String eventTitle;
  NlpEventCancelled(this.eventId, {this.eventTitle = '일정'});
}

class NlpMemoryZeroed extends NlpInputEvent {}
