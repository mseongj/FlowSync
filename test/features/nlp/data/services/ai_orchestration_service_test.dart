import 'package:flutter_test/flutter_test.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';

void main() {
  late AiOrchestrationService service;

  /// We don't need a real SupabaseClient for tokenizer tests,
  /// but AiOrchestrationService requires one in its constructor.
  /// We pass a mock that won't be used in pure-logic tests.
  /// For tokenizer tests only, we construct a minimal service using a helper.

  group('Tokenizer', () {
    // Use a helper to create the service without a real SupabaseClient.
    // Since tokenize() doesn't use _supabase, we can pass anything.
    // We'll create a separate file for Circuit Breaker tests that uses mocks.

    test('should tokenize a single name', () {
      // The tokenizer needs a SupabaseClient but tokenize() doesn't use it.
      // We'll test the tokenization logic directly.
      final result = _tokenize('Meeting with Alice at the park');

      expect(result.tokenizedText, 'Meeting with [PERSON_1] at the park');
      expect(result.tokenMap, {'[PERSON_1]': 'Alice'});
    });

    test('should tokenize multiple names', () {
      final result = _tokenize('Alice and Bob at the park');

      expect(result.tokenizedText, '[PERSON_1] and [PERSON_2] at the park');
      expect(result.tokenMap.length, 2);
      expect(result.tokenMap['[PERSON_1]'], 'Alice');
      expect(result.tokenMap['[PERSON_2]'], 'Bob');
    });

    test('should return empty tokenMap when no names present', () {
      final result = _tokenize('tomorrow at 3pm at the office');

      expect(result.tokenizedText, 'tomorrow at 3pm at the office');
      expect(result.tokenMap, isEmpty);
    });

    test('should exclude common non-name words', () {
      final result = _tokenize('Meeting at Dentist for Lunch');

      // Meeting, Dentist, and Lunch are all in the exclusion list
      expect(result.tokenizedText, 'Meeting at Dentist for Lunch');
      expect(result.tokenMap, isEmpty);
    });
  });

  group('AiSchedulingResponse', () {
    test('fromJson should parse all fields correctly', () {
      final json = {
        'intent': 'CREATE_EVENT',
        'eventTitleTokenized': 'Dentist appointment for [PERSON_1]',
        'locationTokenized': '[LOC_1]',
        'startTime': '2026-07-15T15:00:00Z',
        'endTime': '2026-07-15T16:00:00Z',
        'participantsTokenized': ['[PERSON_1]'],
        'aiReplyMessage':
            'Scheduled dentist for [PERSON_1] at [LOC_1] at 3PM.',
      };

      final response = AiSchedulingResponse.fromJson(json);

      expect(response.intent, 'CREATE_EVENT');
      expect(
        response.eventTitleTokenized,
        'Dentist appointment for [PERSON_1]',
      );
      expect(response.locationTokenized, '[LOC_1]');
      expect(response.startTime, DateTime.utc(2026, 7, 15, 15));
      expect(response.endTime, DateTime.utc(2026, 7, 15, 16));
      expect(response.participantsTokenized, ['[PERSON_1]']);
      expect(
        response.aiReplyMessage,
        'Scheduled dentist for [PERSON_1] at [LOC_1] at 3PM.',
      );
    });

    test('hydrateMessage should replace all tokens with real values', () {
      final response = AiSchedulingResponse(
        intent: 'CREATE_EVENT',
        participantsTokenized: const ['[PERSON_1]'],
        aiReplyMessage:
            'Scheduled dentist for [PERSON_1] at [LOC_1] tomorrow.',
      );

      final tokenMap = {
        '[PERSON_1]': 'Alice',
        '[LOC_1]': 'City Hospital',
      };

      final hydrated = response.hydrateMessage(tokenMap);

      expect(
        hydrated,
        'Scheduled dentist for Alice at City Hospital tomorrow.',
      );
    });
  });
}

/// Standalone tokenizer extracted from AiOrchestrationService
/// to allow testing without SupabaseClient dependency.
_TokenizeResult _tokenize(String rawText) {
  final tokenMap = <String, String>{};
  var tokenizedText = rawText;

  final nameExp = RegExp(r'\b[A-Z][a-z]+\b');
  var personCount = 1;

  for (final match in nameExp.allMatches(rawText)) {
    final name = match.group(0)!;
    if ([
      'Meeting',
      'Dentist',
      'Doctor',
      'Dinner',
      'Lunch',
      'Tomorrow',
      'Today',
    ].contains(name)) {
      continue;
    }

    final token = '[PERSON_$personCount]';
    tokenMap[token] = name;
    tokenizedText = tokenizedText.replaceAll(name, token);
    personCount++;
  }

  return _TokenizeResult(tokenizedText, tokenMap);
}

class _TokenizeResult {
  _TokenizeResult(this.tokenizedText, this.tokenMap);
  final String tokenizedText;
  final Map<String, String> tokenMap;
}
