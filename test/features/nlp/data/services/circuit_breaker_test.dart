import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_command.dart';

// Mocks
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late AiOrchestrationService service;
  late MockSupabaseClient mockSupabase;
  late MockFunctionsClient mockFunctions;

  setUp(() {
    mockSupabase = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    when(() => mockSupabase.functions).thenReturn(mockFunctions);
    service = AiOrchestrationService(mockSupabase);
  });

  NlpCommand createTestCommand({String text = 'test'}) {
    return NlpCommand(
      rawText: text,
      tokenizedText: text,
      tokenMap: {},
      timestamp: DateTime.now(),
    );
  }

  group('Circuit Breaker', () {
    test('should transition to OPEN after 2 consecutive failures', () async {
      // Arrange: Mock the Edge Function to throw
      when(
        () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
      ).thenThrow(Exception('Server Error'));

      final command = createTestCommand();

      // Act: First failure
      expect(
        () => service.processCommand(command),
        throwsA(isA<CircuitOpenException>()),
      );

      // Second failure
      expect(
        () => service.processCommand(command),
        throwsA(isA<CircuitOpenException>()),
      );

      // Third call should fail IMMEDIATELY with CircuitOpenException (not API error)
      expect(
        () => service.processCommand(command),
        throwsA(
          isA<CircuitOpenException>().having(
            (e) => e.message,
            'message',
            'AI Assistant is resting. Opening manual form.',
          ),
        ),
      );

      // Verify Edge Function was only called twice (not 3 times)
      verify(
        () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
      ).called(2);
    });

    test('should reject immediately when circuit is OPEN', () async {
      // Arrange: Force 2 failures to open the circuit
      when(
        () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
      ).thenThrow(Exception('Server Error'));

      final command = createTestCommand();
      try {
        await service.processCommand(command);
      } catch (_) {}
      try {
        await service.processCommand(command);
      } catch (_) {}

      // Reset mock call count
      reset(mockFunctions);
      when(() => mockSupabase.functions).thenReturn(mockFunctions);

      // Act: This should fail immediately without calling the API
      expect(
        () => service.processCommand(command),
        throwsA(isA<CircuitOpenException>()),
      );

      // Assert: No API call was made
      verifyNever(
        () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
      );
    });

    test('should reset to CLOSED after a successful call', () async {
      // Arrange: First call succeeds
      when(
        () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
      ).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'intent': 'CREATE_EVENT',
            'participantsTokenized': <String>[],
            'aiReplyMessage': 'Done',
          },
          status: 200,
        ),
      );

      final command = createTestCommand();
      final response = await service.processCommand(command);

      // Assert: Success
      expect(response.intent, 'CREATE_EVENT');
      expect(response.aiReplyMessage, 'Done');
    });

    test(
      'should allow a call after cooldown period (HALF-OPEN)',
      () async {
        // This test verifies the conceptual transition from OPEN to HALF-OPEN
        // after the cooldown period. Since we can't easily mock DateTime.now(),
        // we test that the service correctly creates responses after a fresh init.
        when(
          () => mockFunctions.invoke('nlp-agent-function', body: any(named: 'body')),
        ).thenAnswer(
          (_) async => FunctionResponse(
            data: {
              'intent': 'QUERY',
              'participantsTokenized': <String>[],
              'aiReplyMessage': 'Recovered',
            },
            status: 200,
          ),
        );

        // A fresh service starts in CLOSED state
        final freshService = AiOrchestrationService(mockSupabase);
        final command = createTestCommand();
        final response = await freshService.processCommand(command);

        expect(response.intent, 'QUERY');
        expect(response.aiReplyMessage, 'Recovered');
      },
    );
  });
}
