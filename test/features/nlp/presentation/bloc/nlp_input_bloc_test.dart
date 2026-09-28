import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flow_sync/core/background/sync_queue_manager.dart';
import 'package:flow_sync/core/database/local_database_service.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_command.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_stream_chunk.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_event.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_state.dart';

class MockAiOrchestrationService extends Mock
    implements AiOrchestrationService {}

class MockLocalDatabaseService extends Mock implements LocalDatabaseService {}

class MockOfflineSyncQueueManager extends Mock
    implements OfflineSyncQueueManager {}

// ── 헬퍼 ──────────────────────────────────────────────────────────────────
/// SSE 스트리밍을 흉내 내는 Stream: 토큰 청크 1개 → 최종 응답 1개
Stream<NlpStreamChunk> _fakeStream(AiSchedulingResponse response) async* {
  yield NlpTokenChunk(response.aiReplyMessage);
  yield NlpFinalChunk(response);
}

/// 빈 스트림만 반환하는 Stream (오류 시뮬레이션용)
Stream<NlpStreamChunk> _errorStream(Object error) async* {
  throw error;
}

void main() {
  late MockAiOrchestrationService mockService;
  late MockLocalDatabaseService mockDb;
  late MockOfflineSyncQueueManager mockSync;

  final testCommand = NlpCommand(
    rawText: 'Meeting with Alice',
    tokenizedText: 'Meeting with [PERSON_1]',
    tokenMap: const {'[PERSON_1]': 'Alice'},
    timestamp: DateTime(2026, 7, 15),
  );

  final testResponse = AiSchedulingResponse(
    intent: 'CREATE_EVENT',
    eventTitleTokenized: 'Meeting with [PERSON_1]',
    participantsTokenized: const ['[PERSON_1]'],
    aiReplyMessage: 'Scheduled meeting with Alice.',
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
        tokenMap: const {},
        timestamp: DateTime(2026),
      ),
    );
  });

  group('NlpInputBloc (SSE 스트리밍 모드)', () {
    // ── 1. 정상 성공: NlpProcessing → NlpStreaming(토큰) → NlpResponseReady ──
    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpStreaming, NlpResponseReady] on successful message',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommandStream(
            any(),
            chatHistory: any(named: 'chatHistory'),
          ),
        ).thenAnswer((_) => _fakeStream(testResponse));
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Meeting with Alice')),
      expect: () => [
        isA<NlpProcessing>(),
        isA<NlpStreaming>(), // 토큰 청크 수신
        isA<NlpResponseReady>().having(
          (s) => s.aiResponse.intent,
          'intent',
          'CREATE_EVENT',
        ),
      ],
    );

    // ── 2. CircuitOpenException → NlpError(isCircuitOpen: true) ──
    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpError(isCircuitOpen: true)] '
      'when CircuitOpenException is thrown',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommandStream(
            any(),
            chatHistory: any(named: 'chatHistory'),
          ),
        ).thenAnswer((_) => _errorStream(CircuitOpenException('Circuit open')));
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

    // ── 3. NlpMemoryZeroed → NlpInitial(empty) ──
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

    // ── 4. 일반 Exception → NlpError(isCircuitOpen: false) ──
    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpError(isCircuitOpen: false)] '
      'on general exception',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommandStream(
            any(),
            chatHistory: any(named: 'chatHistory'),
          ),
        ).thenAnswer((_) => _errorStream(Exception('Random failure')));
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

    // ── 5. RESCHEDULE intent ──
    blocTest<NlpInputBloc, NlpInputState>(
      'emits [NlpProcessing, NlpStreaming, NlpResponseReady] '
      'with targetEventId on RESCHEDULE intent',
      build: () {
        final rescheduleResponse = AiSchedulingResponse(
          intent: 'RESCHEDULE',
          targetEventId: 'event_uuid_123',
          eventTitleTokenized: 'Meeting with [PERSON_1]',
          participantsTokenized: const ['[PERSON_1]'],
          startTime: DateTime(2026, 7, 15, 15),
          endTime: DateTime(2026, 7, 15, 16),
          aiReplyMessage: 'Rescheduled meeting with Alice.',
        );
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommandStream(
            any(),
            chatHistory: any(named: 'chatHistory'),
          ),
        ).thenAnswer((_) => _fakeStream(rescheduleResponse));
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Move meeting to 3pm')),
      expect: () => [
        isA<NlpProcessing>(),
        isA<NlpStreaming>(),
        isA<NlpResponseReady>()
            .having((s) => s.aiResponse.intent, 'intent', 'RESCHEDULE')
            .having(
              (s) => s.aiResponse.targetEventId,
              'targetEventId',
              'event_uuid_123',
            ),
      ],
    );

    // ── 6. pending 메시지가 최종 상태에서 제거됨 ──
    blocTest<NlpInputBloc, NlpInputState>(
      'streaming bubble is absent from NlpResponseReady chatHistory',
      build: () {
        when(() => mockService.tokenize(any())).thenReturn(testCommand);
        when(
          () => mockService.processCommandStream(
            any(),
            chatHistory: any(named: 'chatHistory'),
          ),
        ).thenAnswer((_) => _fakeStream(testResponse));
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) => bloc.add(NlpMessageSent('Hello')),
      expect: () => [
        isA<NlpProcessing>().having(
          (s) => s.chatHistory.any((m) => m.isPending),
          'has pending message',
          true,
        ),
        isA<NlpStreaming>(), // 스트리밍 버블 (id='streaming')
        isA<NlpResponseReady>().having(
          (s) => s.chatHistory.any((m) => m.id == 'streaming'),
          'streaming bubble removed',
          false,
        ),
      ],
    );

    // ── 7. NlpEventCancelled → localDb.deleteEvent 호출 + NlpInitial ──
    blocTest<NlpInputBloc, NlpInputState>(
      'deletes event from localDb and emits [NlpInitial] on NlpEventCancelled',
      build: () {
        when(() => mockDb.deleteEvent(any())).thenAnswer((_) async {});
        return NlpInputBloc(mockService, mockDb, mockSync);
      },
      act: (bloc) =>
          bloc.add(NlpEventCancelled('event_uuid_123', eventTitle: 'Meeting')),
      expect: () => [
        isA<NlpInitial>().having(
          (s) => s.chatHistory.last.text,
          'cancellation text',
          contains('취소되었습니다'),
        ),
      ],
      verify: (_) {
        verify(() => mockDb.deleteEvent('event_uuid_123')).called(1);
      },
    );
  });
}
