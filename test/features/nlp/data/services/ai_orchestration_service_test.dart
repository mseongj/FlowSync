import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/core/llm/llama_ffi_service.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockLlamaFfiService extends Mock implements LlamaFfiService {}

void main() {
  late AiOrchestrationService service;
  late MockSupabaseClient mockSupabase;
  late MockLlamaFfiService mockLlama;

  setUp(() {
    mockSupabase = MockSupabaseClient();
    mockLlama = MockLlamaFfiService();
    // isLoaded는 기본 false → Speculative Decoding 비활성화 상태로 테스트
    when(() => mockLlama.isLoaded).thenReturn(false);
    service = AiOrchestrationService(mockSupabase, mockLlama);
  });

  group('Tokenizer (Multi-Attribute PII)', () {
    test('should tokenize a single name', () {
      final result = service.tokenize('Meeting with Alice at the park');
      expect(result.tokenizedText, 'Meeting with [PERSON_1] at the park');
      expect(result.tokenMap, {'[PERSON_1]': 'Alice'});
    });

    test('should tokenize multiple names', () {
      final result = service.tokenize('Alice and Bob at the park');
      expect(result.tokenizedText, '[PERSON_1] and [PERSON_2] at the park');
      expect(result.tokenMap.length, 2);
      expect(result.tokenMap['[PERSON_1]'], 'Alice');
      expect(result.tokenMap['[PERSON_2]'], 'Bob');
    });

    test('should return empty tokenMap when no names present', () {
      final result = service.tokenize('tomorrow at 3pm at the office');
      expect(result.tokenizedText, 'tomorrow at 3pm at the office');
      expect(result.tokenMap, isEmpty);
    });

    test('should exclude common non-name words', () {
      final result = service.tokenize('Meeting at Dentist for Lunch');
      expect(result.tokenizedText, 'Meeting at Dentist for Lunch');
      expect(result.tokenMap, isEmpty);
    });

    test('should tokenize Korean name with particle 랑', () {
      final result = service.tokenize('내일 민지랑 카페에서 미팅');
      expect(result.tokenizedText, '내일 [PERSON_1]랑 카페에서 미팅');
      expect(result.tokenMap, {'[PERSON_1]': '민지'});
    });

    test('should tokenize Korean name with particle 이랑', () {
      final result = service.tokenize('수현이랑 3시에 회의');
      expect(result.tokenizedText, '[PERSON_1]이랑 3시에 회의');
      expect(result.tokenMap, {'[PERSON_1]': '수현'});
    });

    test('should tokenize Korean name with particle 하고', () {
      final result = service.tokenize('지은이하고 점심 먹기');
      expect(result.tokenizedText, '[PERSON_1]하고 점심 먹기');
      expect(result.tokenMap, {'[PERSON_1]': '지은이'});
    });

    test('should tokenize Korean name with particle 씨', () {
      final result = service.tokenize('김태우씨 미팅 잡아줘');
      expect(result.tokenizedText, '[PERSON_1]씨 미팅 잡아줘');
      expect(result.tokenMap, {'[PERSON_1]': '김태우'});
    });

    test('should tokenize multiple Korean names', () {
      final result = service.tokenize('민지랑 수현이랑 같이 저녁');
      expect(result.tokenMap.length, 2);
      expect(result.tokenMap['[PERSON_1]'], '민지');
      expect(result.tokenMap['[PERSON_2]'], '수현');
    });

    test('should not tokenize Korean non-name words as names', () {
      final result = service.tokenize('내일 카페에서 점심');
      expect(result.tokenizedText, '내일 카페에서 점심');
      expect(result.tokenMap, isEmpty);
    });

    test('should tokenize mixed Korean and English names', () {
      final result = service.tokenize('민지랑 Alice 미팅 잡아줘');
      expect(result.tokenMap.length, 2);
      expect(result.tokenMap.values.toSet(), {'민지', 'Alice'});
    });

    // ── Multi-attribute PII: Phone, Email, Location ──────────────────

    test('should tokenize phone numbers', () {
      final result = service.tokenize('내일 010-1234-5678로 연락줘');
      expect(result.tokenizedText, '내일 [PHONE_1]로 연락줘');
      expect(result.tokenMap['[PHONE_1]'], '010-1234-5678');
    });

    test('should tokenize email addresses', () {
      final result = service.tokenize('초대장은 user@test.com으로 전송해줘');
      expect(result.tokenizedText, '초대장은 [EMAIL_1]으로 전송해줘');
      expect(result.tokenMap['[EMAIL_1]'], 'user@test.com');
    });

    test('should tokenize location with postposition 에서', () {
      final result = service.tokenize('내일 스타벅스에서 만나');
      expect(result.tokenizedText, '내일 [LOC_1]에서 만나');
      expect(result.tokenMap['[LOC_1]'], '스타벅스');
    });

    test('should tokenize facility suffix location like 강남역', () {
      final result = service.tokenize('강남역 3번 출구 미팅');
      expect(result.tokenizedText, '[LOC_1] 3번 출구 미팅');
      expect(result.tokenMap['[LOC_1]'], '강남역');
    });

    test('should tokenize complex sentence with multiple PII attributes', () {
      final result = service.tokenize('내일 010-9876-5432 민지랑 강남역에서 미팅');
      expect(result.tokenMap.containsKey('[PHONE_1]'), true);
      expect(result.tokenMap.containsKey('[PERSON_1]'), true);
      expect(result.tokenMap.containsKey('[LOC_1]'), true);
      expect(result.tokenMap['[PHONE_1]'], '010-9876-5432');
      expect(result.tokenMap['[PERSON_1]'], '민지');
      expect(result.tokenMap['[LOC_1]'], '강남역');
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

    test('hydrateAll should restore title, location, and message simultaneously', () {
      final response = AiSchedulingResponse(
        intent: 'CREATE_EVENT',
        eventTitleTokenized: '[PERSON_1]와의 미팅',
        locationTokenized: '[LOC_1]',
        startTime: DateTime.utc(2026, 9, 10, 14),
        endTime: DateTime.utc(2026, 9, 10, 15),
        participantsTokenized: const ['[PERSON_1]'],
        aiReplyMessage: '[LOC_1]에서 [PERSON_1]와 일정 생성',
      );

      final tokenMap = {
        '[PERSON_1]': '민지',
        '[LOC_1]': '스타벅스',
      };

      final fullyHydrated = response.hydrateAll(tokenMap);

      expect(fullyHydrated.eventTitleTokenized, '민지와의 미팅');
      expect(fullyHydrated.locationTokenized, '스타벅스');
      expect(fullyHydrated.aiReplyMessage, '스타벅스에서 민지와 일정 생성');
      expect(fullyHydrated.participantsTokenized, ['민지']);
    });
  });

  group('Local Early-Exit', () {
    test('canLocalEarlyExit should be true for simple single-turn utterances with clear time', () {
      final command = service.tokenize('내일 2시 미팅');
      expect(service.canLocalEarlyExit(command), true);
    });

    test('canLocalEarlyExit should be false if multi-turn history exists', () {
      final command = service.tokenize('내일 2시 미팅');
      final chatHistory = [
        {'role': 'user', 'text': '안녕'},
        {'role': 'model', 'text': '안녕하세요!'},
      ];
      expect(service.canLocalEarlyExit(command, chatHistory: chatHistory), false);
    });

    test('canLocalEarlyExit should be false for negotiation or conflict keywords', () {
      final command1 = service.tokenize('민지랑 시간 겹치는지 조율해줘');
      expect(service.canLocalEarlyExit(command1), false);

      final command2 = service.tokenize('기존 일정 4시로 변경해줘');
      expect(service.canLocalEarlyExit(command2), false);

      final command3 = service.tokenize('내일 회의 취소해줘');
      expect(service.canLocalEarlyExit(command3), false);
    });

    test('processCommand should return early-exit response without invoking network', () async {
      final command = service.tokenize('내일 3시 팀 미팅');
      final response = await service.processCommand(command);

      expect(response.intent, 'CREATE_EVENT');
      expect(response.eventTitleTokenized, '미팅');
      // 로컬 파서가 반환하는 메시지에 일정 정보가 포함되어야 함
      expect(response.aiReplyMessage, contains('미팅'));
      // Early-Exit이므로 네트워크 호출 없어야 함
      verifyNever(() => mockSupabase.functions);
    });
  });
}
