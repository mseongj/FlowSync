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

/// Edge Function SSE 스트리밍 수신 중 상태.
/// [partialText]: 현재까지 수신된 AI 응답 텍스트 (점진적으로 갱신됨)
class NlpStreaming extends NlpInputState {
  final List<ChatMessage> chatHistory;
  final String partialText;

  NlpStreaming(this.chatHistory, this.partialText);
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
