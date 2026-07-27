import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_command.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_event.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_state.dart';

import 'package:flow_sync/core/database/local_database_service.dart';
import 'package:flow_sync/core/background/sync_queue_manager.dart';

class MockAiOrchestrationService extends Mock
    implements AiOrchestrationService {}

class MockLocalDatabaseService extends Mock implements LocalDatabaseService {}

class MockOfflineSyncQueueManager extends Mock implements OfflineSyncQueueManager {}

void main() {
  late MockAiOrchestrationService mockService;
  late MockLocalDatabaseService mockDb;
  late MockOfflineSyncQueueManager mockSync;

  final testCommand = NlpCommand(
    rawText: 'Meeting with Alice',
    tokenizedText: 'Meeting with [PERSON_1]',
    tokenMap: {'[PERSON_1]': 'Alice'},
    timestamp: DateTime(2026, 7, 15),
  );

  final testResponse = AiSchedulingResponse(
    intent: 'CREATE_EVENT',
    eventTitleTokenized: 'Meeting with [PERSON_1]',
    participantsTokenized: const ['[PERSON_1]'],
    aiReplyMessage: 'Scheduled meeting with [PERSON_1].',
  );

  setUp(() {
    mockService = MockAiOrchestrationService();
    mockDb = MockLocalDatabaseService();
    mockSync = MockOfflineSyncQueueManager();
  });

  setUpAll(() {
    registerFallbackValue(
      NlpCommand(
        rawText: '',
        tokenizedText: '',
        tokenMap: {},
        timestamp: DateTime(2026),
      ),
    );
  });

  group('NlpInputBloc', () {
    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpResponseReady] on successful message',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommand(any()),
        ).thenAnswer((_) async => testResponse);
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Meeting with Alice')),
      expect: () => [
        isA<NlpProcessing>(),
        isA<NlpResponseReady>().having(
          (s) => s.aiResponse.intent,
          'intent',
          'CREATE_EVENT',
        ),
      ],
    );

    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpError(isCircuitOpen: true)] '
      'when CircuitOpenException is thrown',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommand(any()),
        ).thenThrow(CircuitOpenException('Circuit is open'));
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Meeting with Alice')),
      expect: () => [
        isA<NlpProcessing>(),
        isA<NlpError>().having(
          (s) => s.isCircuitOpen,
          'isCircuitOpen',
          true,
        ),
      ],
    );

    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpInitial] with empty chat on NlpMemoryZeroed',
      build: () => NlpInputBloc(mockService, mockDb, mockSync),
      act: (bloc) => bloc.add(NlpMemoryZeroed()),
      expect: () => [
        isA<NlpInitial>().having(
          (s) => s.chatHistory,
          'chatHistory',
          isEmpty,
        ),
      ],
    );

    blocTest<NlpInputBloc, NlpInputState>(
      'accumulates chat history across multiple messages',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommand(any()),
        ).thenAnswer((_) async => testResponse);
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) async {
        bloc.add(NlpMessageSent('First message'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bloc.add(NlpMessageSent('Second message'));
      },
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<NlpProcessing>(), // 1st msg processing
        isA<NlpResponseReady>(), // 1st msg response
        isA<NlpProcessing>(), // 2nd msg processing
        isA<NlpResponseReady>().having(
          (s) => s.chatHistory.where((m) => !m.isPending).length,
          'non-pending messages',
          4, // 2 user + 2 ai
        ),
      ],
    );

    blocTest<NlpInputBloc, NlpInputState>(
      'removes pending message from final state on success',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommand(any()),
        ).thenAnswer((_) async => testResponse);
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Hello')),
      expect: () => [
        isA<NlpProcessing>().having(
          (s) => s.chatHistory.any((m) => m.isPending),
          'has pending message',
          true,
        ),
        isA<NlpResponseReady>().having(
          (s) => s.chatHistory.any((m) => m.isPending),
          'has pending message',
          false,
        ),
      ],
    );

    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpError(isCircuitOpen: false)] '
      'on general exception',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommand(any()),
        ).thenThrow(Exception('Random failure'));
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Hello')),
      expect: () => [
        isA<NlpProcessing>(),
        isA<NlpError>().having(
          (s) => s.isCircuitOpen,
          'isCircuitOpen',
          false,
        ),
      ],
    );
  });
}
