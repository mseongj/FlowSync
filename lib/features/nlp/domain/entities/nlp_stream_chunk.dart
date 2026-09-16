import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';

/// Edge Function SSE 스트리밍에서 수신되는 청크 타입 계층.
sealed class NlpStreamChunk {}

/// AI 응답 텍스트의 부분 청크 (실시간 타이핑 효과용).
final class NlpTokenChunk extends NlpStreamChunk {
  final String text;
  NlpTokenChunk(this.text);
}

/// 스트리밍 완료 후 최종 파싱된 응답.
final class NlpFinalChunk extends NlpStreamChunk {
  final AiSchedulingResponse response;
  NlpFinalChunk(this.response);
}
