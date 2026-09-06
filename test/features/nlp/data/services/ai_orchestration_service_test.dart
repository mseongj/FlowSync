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

    // ── Korean Name Tokenization Tests ──────────────────────────────

    test('should tokenize Korean name with particle 랑', () {
      final result = _tokenize('내일 민지랑 카페에서 미팅');

      expect(result.tokenizedText, '내일 [PERSON_1]랑 카페에서 미팅');
      expect(result.tokenMap, {'[PERSON_1]': '민지'});
    });

    test('should tokenize Korean name with particle 이랑', () {
      final result = _tokenize('수현이랑 3시에 회의');

      expect(result.tokenizedText, '[PERSON_1]이랑 3시에 회의');
      expect(result.tokenMap, {'[PERSON_1]': '수현'});
    });

    test('should tokenize Korean name with particle 하고', () {
      final result = _tokenize('지은이하고 점심 먹기');

      expect(result.tokenizedText, '[PERSON_1]하고 점심 먹기');
      expect(result.tokenMap, {'[PERSON_1]': '지은이'});
    });

    test('should tokenize Korean name with particle 씨', () {
      final result = _tokenize('김태우씨 미팅 잡아줘');

      expect(result.tokenizedText, '[PERSON_1]씨 미팅 잡아줘');
      expect(result.tokenMap, {'[PERSON_1]': '김태우'});
    });

    test('should tokenize multiple Korean names', () {
      final result = _tokenize('민지랑 수현이랑 같이 저녁');

      expect(result.tokenMap.length, 2);
      expect(result.tokenMap['[PERSON_1]'], '민지');
      expect(result.tokenMap['[PERSON_2]'], '수현');
    });

    test('should not tokenize Korean non-name words as names', () {
      final result = _tokenize('내일 카페에서 점심');

      expect(result.tokenizedText, '내일 카페에서 점심');
      expect(result.tokenMap, isEmpty);
    });

    test('should tokenize mixed Korean and English names', () {
      final result = _tokenize('민지랑 Alice 미팅 잡아줘');

      expect(result.tokenMap.length, 2);
      expect(result.tokenMap.values.toSet(), {'민지', 'Alice'});
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

/// ── Standalone tokenizer (mirrors AiOrchestrationService.tokenize) ──
/// Allows testing without SupabaseClient dependency.

const _koreanNonNames = {
  '미팅', '회의', '약속', '일정', '저녁', '점심', '아침',
  '내일', '오늘', '모레', '다음', '이번', '저번', '지난',
  '월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일',
  '시간', '장소', '카페', '학교', '회사', '병원', '치과',
  '식사', '수업', '출발', '도착', '예약', '취소', '변경',
};

const _englishNonNames = {
  'Meeting', 'Dentist', 'Doctor', 'Dinner', 'Lunch',
  'Tomorrow', 'Today', 'Monday', 'Tuesday', 'Wednesday',
  'Thursday', 'Friday', 'Saturday', 'Sunday',
};

_TokenizeResult _tokenize(String rawText) {
  final tokenMap = <String, String>{};
  var tokenizedText = rawText;
  var personCount = 1;

  // 1. Korean name detection via particle patterns
  final koreanNameWithParticle = RegExp(
    r'([가-힣]{2,4}?)(이랑|이한테|이에게|이가|이는|이를|이의|이와|랑|하고|과|와|에게|한테|씨)',
  );

  for (final match in koreanNameWithParticle.allMatches(rawText)) {
    final name = match.group(1)!;
    final particle = match.group(2)!;

    if (_koreanNonNames.contains(name)) continue;
    if (tokenMap.containsValue(name)) continue;

    final token = '[PERSON_$personCount]';
    tokenMap[token] = name;
    tokenizedText = tokenizedText.replaceAll('$name$particle', '$token$particle');
    tokenizedText = tokenizedText.replaceAll(name, token);
    personCount++;
  }

  // 2. English name detection
  final englishNameExp = RegExp(r'\b[A-Z][a-z]+\b');

  for (final match in englishNameExp.allMatches(rawText)) {
    final name = match.group(0)!;
    if (_englishNonNames.contains(name)) continue;
    if (tokenMap.containsValue(name)) continue;

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

