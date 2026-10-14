import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flow_sync/core/llm/llama_ffi_service.dart';
import 'package:flow_sync/features/nlp/data/services/ai_orchestration_service.dart';
import 'package:flow_sync/features/nlp/data/services/partial_reply_extractor.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_stream_chunk.dart';

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

    test('canLocalEarlyExit should be true for simple single-turn utterance without PII', () {
      // DP-ICL 합의는 확률적이므로 processCommand의 실제 경로(Early-Exit vs Cloud)는
      // canLocalEarlyExit 테스트와 별도로 검증함.
      final command = service.tokenize('내일 3시 팀 미팅');
      // 단순 발화: 시간 존재, 복잡 키워드 없음 → Early-Exit 가능
      expect(service.canLocalEarlyExit(command), true);
    });
  });

  group('processCommandStream pipeline', () {
    // Gemini는 JSON을 조각으로 스트리밍한다 → 클라이언트는 aiReplyMessage만 보여야 함
    const sseLines = [
      r'data: {"type":"token","chunk":"{\"intent\":\"QUERY\",\"aiRe"}',
      '',
      r'data: {"type":"token","chunk":"plyMessage\":\"언제로 "}',
      '',
      r'data: {"type":"token","chunk":"할까요?\",\"conflicts\":[]}"}',
      '',
      'data: {"type":"final","payload":{"intent":"QUERY",'
          '"aiReplyMessage":"언제로 할까요?","participantsTokenized":[],'
          '"conflicts":[],"cloudLogprobs":[-0.1,-0.1]}}',
      '',
    ];

    late int transportCalls;
    late List<Map<String, dynamic>> sentBodies;

    void useTransport(Stream<String> Function() lines) {
      service.sseTransportOverride = (body) {
        transportCalls++;
        sentBodies.add(body);
        return lines();
      };
    }

    setUp(() {
      transportCalls = 0;
      sentBodies = [];
    });

    test('emits only reply-text deltas (no raw JSON) then final', () async {
      useTransport(() => Stream.fromIterable(sseLines));

      final chunks = await service
          .processCommandStream(service.tokenize('민지랑 언제 만날지 조율해줘'))
          .toList();

      final tokens = chunks.whereType<NlpTokenChunk>().map((c) => c.text).join();
      expect(tokens, '언제로 할까요?');
      expect(tokens.contains('{'), isFalse);
      expect(chunks.last, isA<NlpFinalChunk>());
      expect((chunks.last as NlpFinalChunk).response.intent, 'QUERY');
    });

    test('forwards server cascade reset as NlpResetChunk', () async {
      useTransport(() => Stream.fromIterable([
            r'data: {"type":"token","chunk":"{\"aiReplyMessage\":\"bad"}',
            'data: {"type":"reset","reason":"FALLBACK_LOW_QUALITY"}',
            ...sseLines,
          ]));

      final chunks = await service
          .processCommandStream(service.tokenize('민지랑 언제 만날지 조율해줘'))
          .toList();

      final resetIdx = chunks.indexWhere((c) => c is NlpResetChunk);
      expect(resetIdx, greaterThan(0));
      final afterReset = chunks
          .skip(resetIdx + 1)
          .whereType<NlpTokenChunk>()
          .map((c) => c.text)
          .join();
      expect(afterReset, '언제로 할까요?');
    });

    test('attaches Llama draft tokens to the request when model is loaded', () async {
      when(() => mockLlama.isLoaded).thenReturn(true);
      when(() => mockLlama.generateDraft(any())).thenAnswer(
        (_) async =>
            LlamaDraftResult(tokens: const [1, 2], logprobs: const [-0.2, -0.3]),
      );
      useTransport(() => Stream.fromIterable(sseLines));

      await service
          .processCommandStream(service.tokenize('민지랑 언제 만날지 조율해줘'))
          .toList();

      expect(sentBodies.single['draftTokens'], [1, 2]);
    });

    test('skips draft when generation exceeds latency budget', () async {
      when(() => mockLlama.isLoaded).thenReturn(true);
      when(() => mockLlama.generateDraft(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return LlamaDraftResult(tokens: const [1], logprobs: const [-0.1]);
      });
      useTransport(() => Stream.fromIterable(sseLines));

      await service
          .processCommandStream(service.tokenize('민지랑 언제 만날지 조율해줘'))
          .toList();

      expect(sentBodies.single.containsKey('draftTokens'), isFalse);
    });

    test('falls back to local parser when SSE stream reports an error', () async {
      useTransport(() => Stream.fromIterable([
            'data: {"type":"error","message":"boom"}',
          ]));

      final chunks = await service
          .processCommandStream(
            service.tokenize('내일 3시 팀 미팅'),
            enableEarlyExit: false,
          )
          .toList();

      expect(chunks.single, isA<NlpFinalChunk>());
      expect((chunks.single as NlpFinalChunk).response.startTime, isNotNull);
    });

    test('clears partial text (reset) before local fallback on mid-stream failure', () async {
      useTransport(() async* {
        yield r'data: {"type":"token","chunk":"{\"aiReplyMessage\":\"부분"}';
        throw Exception('connection dropped');
      });

      final chunks = await service
          .processCommandStream(
            service.tokenize('내일 3시 팀 미팅'),
            enableEarlyExit: false,
          )
          .toList();

      expect(chunks[0], isA<NlpTokenChunk>());
      expect(chunks[1], isA<NlpResetChunk>());
      expect(chunks[2], isA<NlpFinalChunk>());
    });

    test('falls back to local parser on network failure', () async {
      useTransport(() => Stream.error(Exception('offline')));

      final chunks = await service
          .processCommandStream(
            service.tokenize('내일 3시 팀 미팅'),
            enableEarlyExit: false,
          )
          .toList();

      expect(chunks.single, isA<NlpFinalChunk>());
    });

    test('falls back when stream ends without a final payload', () async {
      useTransport(() => Stream.fromIterable(sseLines.take(2)));

      final chunks = await service
          .processCommandStream(
            service.tokenize('내일 3시 팀 미팅'),
            enableEarlyExit: false,
          )
          .toList();

      expect(chunks.last, isA<NlpFinalChunk>());
    });

    test('throws CircuitOpenException when cloud fails and local parser cannot help', () async {
      useTransport(() => Stream.error(Exception('offline')));

      expect(
        service.processCommandStream(service.tokenize('안녕')).toList(),
        throwsA(isA<CircuitOpenException>()),
      );
    });

    test('skips the cloud when Early-Exit consensus succeeds', () async {
      useTransport(() => Stream.fromIterable(sseLines));

      // DP-ICL 합의는 확률적이므로 여러 번 시도해 최소 1회는 로컬 처리되는지 확인
      const attempts = 20;
      for (var i = 0; i < attempts; i++) {
        final chunks = await service
            .processCommandStream(service.tokenize('내일 3시 팀 미팅'))
            .toList();
        expect(chunks.last, isA<NlpFinalChunk>());
      }
      expect(transportCalls, lessThan(attempts));
    });
  });

  group('PartialReplyExtractor', () {
    test('returns empty until aiReplyMessage starts', () {
      expect(PartialReplyExtractor.extract('{"intent":"CRE'), '');
    });

    test('decodes escapes and stops at closing quote', () {
      expect(
        PartialReplyExtractor.extract(r'{"aiReplyMessage":"a\"b\nc\u00e9","x":1}'),
        'a"b\ncé',
      );
    });

    test('holds back a truncated escape sequence', () {
      expect(PartialReplyExtractor.extract(r'{"aiReplyMessage":"ab\u00'), 'ab');
      expect(PartialReplyExtractor.extract(r'{"aiReplyMessage":"ab\'), 'ab');
    });

    test('add() yields incremental deltas across fragments', () {
      final ex = PartialReplyExtractor();
      expect(ex.add('{"aiReplyMes'), '');
      expect(ex.add('sage":"안녕'), '안녕');
      expect(ex.add('하세요","conflicts":[]}'), '하세요');
      expect(ex.reply, '안녕하세요');
      ex.reset();
      expect(ex.reply, '');
    });
  });
}
