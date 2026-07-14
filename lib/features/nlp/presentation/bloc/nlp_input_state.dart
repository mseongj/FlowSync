import '../../domain/entities/chat_message.dart';
import '../../domain/entities/ai_scheduling_response.dart';

abstract class NlpInputState {}

class NlpInitial extends NlpInputState {
  final List<ChatMessage> chatHistory;
  NlpInitial({this.chatHistory = const []});
}

class NlpProcessing extends NlpInputState {
  final List<ChatMessage> chatHistory;
  NlpProcessing(this.chatHistory);
}

class NlpResponseReady extends NlpInputState {
  final List<ChatMessage> chatHistory;
  final AiSchedulingResponse aiResponse;
  
  NlpResponseReady(this.chatHistory, this.aiResponse);
}

class NlpError extends NlpInputState {
  final List<ChatMessage> chatHistory;
  final String message;
  final bool isCircuitOpen;
  
  NlpError(this.chatHistory, this.message, {this.isCircuitOpen = false});
}
