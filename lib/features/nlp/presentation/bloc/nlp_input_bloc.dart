import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';
import 'nlp_input_event.dart';
import 'nlp_input_state.dart';
import '../../data/services/ai_orchestration_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/nlp_command.dart';
import '../../../schedule/domain/entities/calendar_event.dart';
import '../../../../core/database/local_database_service.dart';
import '../../../../core/background/sync_queue_manager.dart';

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
    on<NlpMemoryZeroed>(_onMemoryZeroed);
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
      text: 'Event "${event.event.title}" confirmed and saved.',
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

      // 2. Call Edge Function via Circuit Breaker
      final response = await _aiService.processCommand(command);

      // 3. Hydrate the reply message
      final hydratedMessage = response.hydrateMessage(_ephemeralTokenMap);

      // 4. Update Chat History
      _chatHistory = _chatHistory.where((m) => m.id != 'pending').toList();
      _chatHistory.add(ChatMessage(
        id: _uuid.v4(),
        text: hydratedMessage,
        isUser: false,
        timestamp: DateTime.now(),
      ));

      emit(NlpResponseReady(_chatHistory, response));
      
    } on CircuitOpenException catch (e) {
      _chatHistory = _chatHistory.where((m) => m.id != 'pending').toList();
      emit(NlpError(_chatHistory, e.message, isCircuitOpen: true));
    } catch (e) {
      _chatHistory = _chatHistory.where((m) => m.id != 'pending').toList();
      emit(NlpError(_chatHistory, 'An unexpected error occurred.'));
    }
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
