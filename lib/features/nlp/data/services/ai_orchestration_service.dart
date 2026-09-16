import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/core/privacy/differential_privacy_service.dart';
import 'package:flow_sync/core/privacy/dp_icl_consensus.dart';
import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_command.dart';
import 'package:flow_sync/features/nlp/domain/entities/nlp_stream_chunk.dart';

class CircuitOpenException implements Exception {
  final String message;
  CircuitOpenException([
    this.message = 'AI Assistant is resting. Opening manual form.',
  ]);
}

enum CircuitState { closed, open, halfOpen }

@lazySingleton
class AiOrchestrationService {
  final SupabaseClient _supabase;

  // Circuit Breaker State
  CircuitState _circuitState = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;

  final int _maxFailures = 2;
  final Duration _cooldownPeriod = const Duration(minutes: 5);

  AiOrchestrationService(this._supabase);

  // ── Korean non-name words (scheduling vocabulary) ──────────────────
  static final _koreanNonNames = {
    '미팅', '회의', '약속', '일정', '저녁', '점심', '아침',
    '내일', '오늘', '모레', '다음', '이번', '저번', '지난',
    '월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일',
    '시간', '장소', '카페', '학교', '회사', '병원', '치과',
    '식사', '수업', '출발', '도착', '예약', '취소', '변경',
  };

  // ── English non-name words ────────────────────────────────────────
  static final _englishNonNames = {
    'Meeting', 'Dentist', 'Doctor', 'Dinner', 'Lunch',
    'Tomorrow', 'Today', 'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday', 'Sunday',
  };

  // ── Korean non-location words ──────────────────────────────────────
  static final _koreanNonLocations = {
    '여기', '거기', '저기', '어디', '언제', '앞', '뒤', '위', '밑', '옆',
    '사이', '가운데', '스스로', '앞으로', '차례', '임의', '시간', '지금', '먼저',
    '내일', '오늘', '모레', '미팅', '회의', '약속', '일정', '식사', '출발', '도착',
    '카페', '학교', '회사', '병원', '치과', '장소',
  };

  // Deterministic Multi-Attribute Tokenizer (PII: Phone, Email, Location, Person)
  NlpCommand tokenize(String rawText) {
    final tokenMap = <String, String>{};
    var tokenizedText = rawText;
    var personCount = 1;
    var locCount = 1;
    var phoneCount = 1;
    var emailCount = 1;

    // ── 1. Phone Number Detection ──────────────────────────────────
    final phoneExp = RegExp(r'\b(01[016789]-?\d{3,4}-?\d{4}|0\d{1,2}-?\d{3,4}-?\d{4})\b');
    for (final match in phoneExp.allMatches(rawText)) {
      final phone = match.group(0)!;
      if (tokenMap.containsValue(phone)) continue;

      final token = '[PHONE_$phoneCount]';
      tokenMap[token] = phone;
      tokenizedText = tokenizedText.replaceAll(phone, token);
      phoneCount++;
    }

    // ── 2. Email Detection ────────────────────────────────────────
    final emailExp = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
    for (final match in emailExp.allMatches(rawText)) {
      final email = match.group(0)!;
      if (tokenMap.containsValue(email)) continue;

      final token = '[EMAIL_$emailCount]';
      tokenMap[token] = email;
      tokenizedText = tokenizedText.replaceAll(email, token);
      emailCount++;
    }

    // ── 3. Location Detection (Korean postpositions & place suffixes) ──
    // 3-A: Places followed by '에서' or '서' (e.g. "스타벅스에서", "회의실에서")
    final locParticleExp = RegExp(r'([가-힣A-Za-z0-9]{2,10}?)(에서|서)');
    for (final match in locParticleExp.allMatches(rawText)) {
      final loc = match.group(1)!;
      final particle = match.group(2)!;
      if (_koreanNonLocations.contains(loc)) continue;
      if (tokenMap.containsValue(loc)) continue;

      final token = '[LOC_$locCount]';
      tokenMap[token] = loc;
      tokenizedText = tokenizedText.replaceAll('$loc$particle', '$token$particle');
      tokenizedText = tokenizedText.replaceAll(loc, token);
      locCount++;
    }

    // 3-B: Specific facility / station suffixes (역, 빌딩, 타워, 센터)
    final locSuffixExp = RegExp(r'([가-힣]{2,6}(역|빌딩|타워|센터|공원|호텔))');
    for (final match in locSuffixExp.allMatches(rawText)) {
      final loc = match.group(1)!;
      if (_koreanNonLocations.contains(loc)) continue;
      if (tokenMap.containsValue(loc)) continue;

      final token = '[LOC_$locCount]';
      tokenMap[token] = loc;
      tokenizedText = tokenizedText.replaceAll(loc, token);
      locCount++;
    }

    // ── 4. Korean Name Detection via Particle Patterns ──────────────
    final koreanNameWithParticle = RegExp(
      r'([가-힣]{2,4}?)(이랑|이한테|이에게|이가|이는|이를|이의|이와|랑|하고|과|와|에게|한테|씨)',
    );

    for (final match in koreanNameWithParticle.allMatches(rawText)) {
      final name = match.group(1)!;
      final particle = match.group(2)!;

      if (_koreanNonNames.contains(name)) continue;
      if (_koreanNonLocations.contains(name)) continue;
      if (tokenMap.containsValue(name)) continue;

      final token = '[PERSON_$personCount]';
      tokenMap[token] = name;
      tokenizedText = tokenizedText.replaceAll('$name$particle', '$token$particle');
      tokenizedText = tokenizedText.replaceAll(name, token);
      personCount++;
    }

    // ── 5. English Name Detection (Capital-letter words) ────────────
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

    // ── Debug Logging ───────────────────────────────────────────────
    debugPrint('🔑 [Tokenizer] 원문: "$rawText"');
    debugPrint('🔑 [Tokenizer] 토큰: "$tokenizedText"');
    if (tokenMap.isNotEmpty) {
      debugPrint('🔑 [Tokenizer] 맵: $tokenMap');
    } else {
      debugPrint('🔑 [Tokenizer] PII 감지 없음 (토큰 0개)');
    }

    return NlpCommand(
      rawText: rawText,
      tokenizedText: tokenizedText,
      tokenMap: tokenMap,
      timestamp: DateTime.now(),
    );
  }

  bool _isCircuitOpen() {
    if (_circuitState == CircuitState.open) {
      final timeSinceLastFailure =
          DateTime.now().difference(_lastFailureTime!);
      if (timeSinceLastFailure > _cooldownPeriod) {
        _circuitState = CircuitState.halfOpen;
        return false;
      }
      return true;
    }
    return false;
  }

  void _recordSuccess() {
    _failureCount = 0;
    _circuitState = CircuitState.closed;
  }

  void _recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    if (_failureCount >= _maxFailures) {
      _circuitState = CircuitState.open;
    }
  }

  /// Evaluates whether the command is eligible for Local Early-Exit (0ms latency, no network).
  bool canLocalEarlyExit(
    NlpCommand command, {
    List<Map<String, String>> chatHistory = const [],
  }) {
    // Multi-turn context requires cloud reasoning
    if (chatHistory.isNotEmpty) return false;

    final text = command.rawText.toLowerCase();

    // Check for negotiation, conflict, or modification keywords
    final complexKeywords = [
      '조율', '겹치', '비는', '언제', '변경', '옮겨', '바꿔', '취소', '삭제',
      '미뤄', '당겨', '시간표', '스케줄', '가능한', '확인해', 'reschedule',
      'conflict', 'find time', 'overlap', 'cancel',
    ];
    for (final kw in complexKeywords) {
      if (text.contains(kw)) return false;
    }

    // Must have a clear time indicator
    final hasTime = text.contains('내일') ||
        text.contains('오늘') ||
        text.contains('tomorrow') ||
        text.contains('today') ||
        RegExp(r'\d{1,2}시').hasMatch(text) ||
        RegExp(r'\d{1,2}\s*(am|pm)').hasMatch(text);

    if (!hasTime) return false;

    // Verify local fallback can successfully parse this command
    return _tryLocalFallback(command) != null;
  }

  Future<AiSchedulingResponse> processCommand(
    NlpCommand command, {
    List<Map<String, String>> chatHistory = const [],
    bool enableEarlyExit = true,
  }) async {
    // ── 0. Local Early-Exit for Simple Utterances (0ms Latency) ─────
    if (enableEarlyExit &&
        canLocalEarlyExit(command, chatHistory: chatHistory)) {
      // DP-ICL Noisy Consensus: k=3 서브셋으로 환각 여부 검증
      final consensusResult = DpIclConsensus.runConsensus(
        command,
        (subset) => _tryLocalFallback(subset),
      );

      if (consensusResult != null) {
        // 합의 통과 → Laplace 시간 노이즈 주입
        final noisedResponse = _applyDpNoise(consensusResult);
        debugPrint('⚡ [Local Early-Exit + DP] 로컬 엔진 즉시 생성: "${command.rawText}"');
        return noisedResponse;
      }
      // 합의 실패(τ_dp 미만) → Cloud 경유 (Early-Exit 포기)
      debugPrint('🔒 [DP-ICL] 합의 불충분 → Cloud 경유');
    }

    // ── 1. Cloud Execution via Circuit Breaker ──────────────────────
    if (!_isCircuitOpen()) {
      try {
        final response = await _supabase.functions.invoke(
          'nlp-agent-function',
          body: {
            'text': command.tokenizedText,
            if (chatHistory.isNotEmpty) 'chatHistory': chatHistory,
          },
        );

        if (response.status >= 400) {
          throw Exception('Edge function error: ${response.status}');
        }

        final data = response.data as Map<String, dynamic>;

        _recordSuccess();
        // Cloud 응답에도 DP 시간 노이즈 주입
        return _applyDpNoise(AiSchedulingResponse.fromJson(data));
      } catch (e) {
        _recordFailure();

        final fallback = _tryLocalFallback(command);
        if (fallback != null) {
          return fallback;
        }

        throw CircuitOpenException('API Error: ${e.toString()}');
      }
    }

    // Circuit is open: skip the API, but still allow offline parsing.
    final fallback = _tryLocalFallback(command);
    if (fallback != null) {
      return fallback;
    }

    throw CircuitOpenException();
  }

  // ──────────────────────────────────────────────────────────────────────
  // DP 노이즈 적용 헬퍼
  // ──────────────────────────────────────────────────────────────────────

  /// [AiSchedulingResponse]의 startTime / endTime에 Laplace 노이즈를 가산.
  /// QUERY, CANCEL intent는 시간 필드가 없으므로 그대로 반환.
  AiSchedulingResponse _applyDpNoise(AiSchedulingResponse response) {
    if (response.startTime == null) return response;

    final (noisedStart, noisedEnd) =
        DifferentialPrivacyService.injectEventTimeNoise(
      response.startTime!,
      response.endTime ?? response.startTime!.add(const Duration(hours: 1)),
    );

    // 과거 방지 가드
    final guardedStart = DifferentialPrivacyService.guardAgainstPast(
      noisedStart,
      response.startTime!,
    );

    debugPrint(
      '🔒 [DP] 시간 노이즈 주입: ${response.startTime} → $guardedStart (Δ: '
      '${guardedStart.difference(response.startTime!).inMinutes}분)',
    );

    return response.copyWith(
      startTime: guardedStart,
      endTime: noisedEnd,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // SSE 스트리밍 수신
  // ──────────────────────────────────────────────────────────────────────

  /// Edge Function SSE 스트리밍을 구독하여 [NlpStreamChunk] 시퀀스를 yield.
  ///
  /// - 토큰 청크 수신 시 [NlpTokenChunk] yield → 채팅 버블 실시간 갱신
  /// - 최종 페이로드 수신 시 [NlpFinalChunk] yield → [AiSchedulingResponse] 파싱
  Stream<NlpStreamChunk> processCommandStream(
    NlpCommand command, {
    List<Map<String, String>> chatHistory = const [],
  }) async* {
    if (_isCircuitOpen()) {
      throw CircuitOpenException();
    }

    try {
      final request = await _supabase.functions.invoke(
        'nlp-agent-function',
        body: {
          'text': command.tokenizedText,
          if (chatHistory.isNotEmpty) 'chatHistory': chatHistory,
        },
        headers: {'X-FlowSync-Streaming': 'true'},
        method: HttpMethod.post,
        queryParameters: {'streaming': 'true'},
      );

      // Supabase invoke는 SSE를 직접 스트리밍 지원하지 않으므로
      // 단일 응답에서 SSE 라인을 파싱하는 방식으로 처리
      final rawData = request.data;
      if (rawData is String) {
        yield* _parseSseLines(rawData);
      } else if (rawData is Map<String, dynamic>) {
        // JSON 폴백 (스트리밍 미지원 환경)
        yield NlpFinalChunk(
          _applyDpNoise(AiSchedulingResponse.fromJson(rawData)),
        );
      }

      _recordSuccess();
    } catch (e) {
      _recordFailure();
      rethrow;
    }
  }

  /// SSE 형식의 raw 문자열에서 [NlpStreamChunk]를 파싱.
  Stream<NlpStreamChunk> _parseSseLines(String raw) async* {
    final lines = raw.split('\n');
    for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final jsonStr = line.substring(6).trim();
      if (jsonStr.isEmpty) continue;

      try {
        final json = Map<String, dynamic>.from(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
        final type = json['type'] as String?;

        if (type == 'token') {
          yield NlpTokenChunk(json['chunk'] as String? ?? '');
        } else if (type == 'final') {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            yield NlpFinalChunk(
              _applyDpNoise(AiSchedulingResponse.fromJson(payload)),
            );
          }
        } else if (type == 'error') {
          throw Exception(json['message'] as String? ?? 'SSE stream error');
        }
      } catch (_) {
        // 개별 라인 파싱 실패는 무시
      }
    }
  }


  /// Local fallback NLP: parses simple scheduling patterns offline
  /// or provides instant Local Early-Exit.
  AiSchedulingResponse? _tryLocalFallback(
    NlpCommand command, {
    bool isEarlyExit = false,
  }) {
    final text = command.tokenizedText.toLowerCase();
    final now = DateTime.now();

    // --- Time Extraction ---
    DateTime? startTime;
    DateTime? endTime;

    final isTomorrow =
        text.contains('내일') || text.contains('tomorrow');
    final isToday =
        text.contains('오늘') || text.contains('today');
    final baseDate = isTomorrow
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    final koreanTime = RegExp(r'(\d{1,2})시');
    final englishTime = RegExp(r'(\d{1,2})\s*(am|pm)', caseSensitive: false);
    final atTime = RegExp(r'at\s+(\d{1,2})');

    final koreanMatch = koreanTime.firstMatch(text);
    final englishMatch = englishTime.firstMatch(text);
    final atMatch = atTime.firstMatch(text);

    if (koreanMatch != null) {
      final hour = int.parse(koreanMatch.group(1)!);
      startTime = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour,
      );
    } else if (englishMatch != null) {
      var hour = int.parse(englishMatch.group(1)!);
      final isPm =
          englishMatch.group(2)!.toLowerCase() == 'pm';
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      startTime = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour,
      );
    } else if (atMatch != null) {
      final hour = int.parse(atMatch.group(1)!);
      startTime = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        hour < 7 ? hour + 12 : hour,
      );
    }

    if (startTime != null && !isTomorrow && !isToday) {
      startTime = DateTime(
        now.year,
        now.month,
        now.day,
        startTime.hour,
      );
    }

    endTime = startTime?.add(const Duration(hours: 1));

    // --- Intent Detection ---
    final isCreate = text.contains('미팅') ||
        text.contains('회의') ||
        text.contains('약속') ||
        text.contains('일정') ||
        text.contains('meeting') ||
        text.contains('schedule') ||
        text.contains('잡아') ||
        text.contains('만들') ||
        text.contains('추가') ||
        startTime != null;

    if (!isCreate) return null;

    // --- Title Extraction ---
    var title = '새 일정';
    if (text.contains('미팅') || text.contains('meeting')) {
      title = '미팅';
    } else if (text.contains('회의')) {
      title = '회의';
    } else if (text.contains('약속')) {
      title = '약속';
    } else if (text.contains('dentist') || text.contains('치과')) {
      title = '치과 예약';
    } else if (text.contains('dinner') || text.contains('저녁')) {
      title = '저녁 식사';
    } else if (text.contains('lunch') || text.contains('점심')) {
      title = '점심 식사';
    }

    // --- Location Extraction from TokenMap ---
    String? location;
    final locEntry = command.tokenMap.entries
        .where((e) => e.key.startsWith('[LOC_'))
        .firstOrNull;
    if (locEntry != null) {
      location = locEntry.key; // Keep tokenized; hydrateAll will restore it
    }

    // --- Participants Extraction from TokenMap ---
    final participants = command.tokenMap.keys
        .where((k) => k.startsWith('[PERSON_'))
        .toList();

    // Build reply message
    final timeStr = startTime != null
        ? '${startTime.month}/${startTime.day} '
            '${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}'
        : '시간 미정';

    final modeTag = isEarlyExit
        ? '(⚡ 초고속 로컬 분석 완료)'
        : '(오프라인 모드 — 로컬 분석 결과)';

    return AiSchedulingResponse(
      intent: 'CREATE_EVENT',
      eventTitleTokenized: title,
      locationTokenized: location ?? '',
      startTime: startTime,
      endTime: endTime,
      participantsTokenized: participants,
      aiReplyMessage: '📅 "$title" 일정을 $timeStr에 생성할까요?\n$modeTag',
    );
  }
}
