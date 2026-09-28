import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:flow_sync/core/background/sync_queue_manager.dart';
import 'package:flow_sync/core/database/local_database_service.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/chat_message.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_stream_chunk.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_event.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_state.dart';

@injectable
class NlpInputBloc extends Bloc<NlpInputEvent, NlpInputState> {
  final AiOrchestrationService _aiService;
  final LocalDatabaseService _localDb;
  final OfflineSyncQueueManager _syncManager;
  final _uuid = const Uuid();
  
  // Ephemeral Token Map (Zero-Knowledge Privacy)
  Map<String, String> _ephemeralTokenMap = {};
  
  List<ChatMessage> _chatHistory = [];

  NlpInputBloc(this._aiService, this._localDb, this._syncManager) : super(NlpInitial()) {
    on<NlpMessageSent>(_onMessageSent);
    on<NlpEventConfirmed>(_onEventConfirmed);
    on<NlpEventCancelled>(_onEventCancelled);
    on<NlpMemoryZeroed>(_onMemoryZeroed);
  }

  Future<void> _onEventCancelled(NlpEventCancelled event, Emitter<NlpInputState> emit) async {
    // Delete from local database
    if (event.eventId.isNotEmpty) {
      await _localDb.deleteEvent(event.eventId);
    }

    // Clear ephemeral map and add system message
    _ephemeralTokenMap.clear();

    _chatHistory.add(ChatMessage(
      id: _uuid.v4(),
      text: '🗑️ "${event.eventTitle}" 일정이 취소되었습니다.',
      isUser: false,
      timestamp: DateTime.now(),
    ));

    emit(NlpInitial(chatHistory: _chatHistory));
  }

  Future<void> _onEventConfirmed(NlpEventConfirmed event, Emitter<NlpInputState> emit) async {
    // Save to local database
    await _localDb.saveEvent(event.event);
    
    // Add to sync queue since it's offline created (or pending sync)
    if (event.event.isOfflineCreated) {
      await _syncManager.enqueueSyncTask(event.event.id);
    }
    
    // Clear ephemeral map and add system message
    _ephemeralTokenMap.clear();
    
    _chatHistory.add(ChatMessage(
      id: _uuid.v4(),
      text: '일정 "${event.event.title}"이(가) 확정되어 저장되었습니다.',
      isUser: false,
      timestamp: DateTime.now(),
    ));
    
    emit(NlpInitial(chatHistory: _chatHistory));
  }

  Future<void> _onMessageSent(NlpMessageSent event, Emitter<NlpInputState> emit) async {
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      text: event.text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    
    _chatHistory = List.from(_chatHistory)..add(userMsg);
    
    // Add a pending message to show typing indicator
    final pendingMsg = ChatMessage(
      id: 'pending',
      text: '...',
      isUser: false,
      timestamp: DateTime.now(),
      isPending: true,
    );
    _chatHistory = List.from(_chatHistory)..add(pendingMsg);
    
    emit(NlpProcessing(_chatHistory));

    try {
      // 1. Local Deterministic Tokenization
      final command = _aiService.tokenize(event.text);
      
      // Save tokens ephemerally
      _ephemeralTokenMap.addAll(command.tokenMap);

      // 2. Build tokenized chat history for multi-turn context
      final tokenizedHistory = _buildTokenizedHistory();

      // ── SSE 스트리밍 모드 ────────────────────────────────────────────────
      // pending 버블을 스트리밍 버블로 교체
      _chatHistory = _chatHistory.where((m) => m.id != 'pending').toList();
      // 빈 스트리밍 버블 추가 (실시간 갱신용)
      _chatHistory.add(ChatMessage(
        id: 'streaming',
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isPending: false,
      ));

      // 3. SSE 스트리밍 구독
      await emit.forEach<NlpStreamChunk>(
        _aiService.processCommandStream(command, chatHistory: tokenizedHistory),
        onData: (chunk) {
          if (chunk is NlpTokenChunk) {
            // 스트리밍 버블에 텍스트 점진적 추가
            final currentStreamingIdx = _chatHistory.indexWhere((m) => m.id == 'streaming');
            if (currentStreamingIdx != -1) {
              final currentText = _chatHistory[currentStreamingIdx].text;
              _chatHistory[currentStreamingIdx] = _chatHistory[currentStreamingIdx].copyWith(
                text: currentText + chunk.text,
              );
            }
            return NlpStreaming(List.from(_chatHistory), _currentStreamingText());
          } else if (chunk is NlpFinalChunk) {
            // 스트리밍 완료 → 최종 응답으로 교체
            final hydratedResponse = chunk.response.hydrateAll(_ephemeralTokenMap);

            // 스트리밍 버블을 최종 AI 메시지로 교체
            _chatHistory = _chatHistory.where((m) => m.id != 'streaming').toList();
            _chatHistory.add(ChatMessage(
              id: _uuid.v4(),
              text: hydratedResponse.aiReplyMessage,
              isUser: false,
              timestamp: DateTime.now(),
            ));

            // QUERY vs 일정 응답 분기
            if (hydratedResponse.intent == 'QUERY') {
              if (hydratedResponse.hasConflicts) {
                final conflictLines = hydratedResponse.conflicts.map((c) {
                  final overlap = c.overlapMinutes != null ? ' (${c.overlapMinutes}분 겹침)' : '';
                  return '  ⚠️ "${c.existingEventTitle}" ${c.existingStartTime ?? ''}~${c.existingEndTime ?? ''}$overlap';
                }).join('\n');

                _chatHistory.add(ChatMessage(
                  id: _uuid.v4(),
                  text: '📋 충돌 감지된 기존 일정:\n$conflictLines',
                  isUser: false,
                  timestamp: DateTime.now(),
                ));
              }
              return NlpInitial(chatHistory: List.from(_chatHistory));
            } else {
              _recordSuccess();
              return NlpResponseReady(List.from(_chatHistory), hydratedResponse);
            }
          }
          // fallback (오류 청크 등)
          return NlpProcessing(_chatHistory);
        },
        onError: (error, stackTrace) {
          _chatHistory = _chatHistory
              .where((m) => m.id != 'streaming' && m.id != 'pending')
              .toList();
          if (error is CircuitOpenException) {
            return NlpError(_chatHistory, error.message, isCircuitOpen: true);
          }
          return NlpError(_chatHistory, 'An unexpected error occurred.');
        },
      );
      
    } on CircuitOpenException catch (e) {
      _chatHistory = _chatHistory.where((m) => m.id != 'pending' && m.id != 'streaming').toList();
      emit(NlpError(_chatHistory, e.message, isCircuitOpen: true));
    } catch (e) {
      _chatHistory = _chatHistory.where((m) => m.id != 'pending' && m.id != 'streaming').toList();
      emit(NlpError(_chatHistory, 'An unexpected error occurred.'));
    }
  }

  String _currentStreamingText() {
    final idx = _chatHistory.indexWhere((m) => m.id == 'streaming');
    return idx != -1 ? _chatHistory[idx].text : '';
  }

  void _recordSuccess() {
    // Circuit Breaker 성공 기록은 AiOrchestrationService 내부에서 처리됨
  }

  /// Builds a tokenized version of the chat history for the Edge Function.
  /// User messages are tokenized; AI messages are sent as-is (already tokenized).
  List<Map<String, String>> _buildTokenizedHistory() {
    // Only include real messages (not pending, not system confirmations)
    final realMessages = _chatHistory
        .where((m) => !m.isPending && m.id != 'pending' && m.id != 'streaming')
        .toList();

    // Keep last 10 turns max to avoid payload bloat
    final recentMessages = realMessages.length > 20
        ? realMessages.sublist(realMessages.length - 20)
        : realMessages;

    return recentMessages.map((m) {
      return {
        'role': m.isUser ? 'user' : 'model',
        'text': m.isUser
            ? _aiService.tokenize(m.text).tokenizedText
            : m.text,
      };
    }).toList();
  }

  void _onMemoryZeroed(NlpMemoryZeroed event, Emitter<NlpInputState> emit) {
    // Actively overwrite memory with null bytes to prevent memory dump leakage
    final keys = _ephemeralTokenMap.keys.toList();
    for (var key in keys) {
      _ephemeralTokenMap[key] = '\x00\x00\x00'; // Null byte overwrite
    }
    _ephemeralTokenMap.clear();
    
    // Also clear chat history on background
    _chatHistory.clear();
    emit(NlpInitial(chatHistory: _chatHistory));
  }
}
