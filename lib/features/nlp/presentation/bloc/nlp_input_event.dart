abstract class NlpInputEvent {}

class NlpMessageSent extends NlpInputEvent {
  final String text;
  NlpMessageSent(this.text);
}

class NlpEventConfirmed extends NlpInputEvent {}

class NlpMemoryZeroed extends NlpInputEvent {}
