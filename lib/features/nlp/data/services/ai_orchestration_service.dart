import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/core/config/env.dart';
import 'package:flow_sync/core/llm/llama_ffi_service.dart';
import 'package:flow_sync/core/llm/speculative_decode_manager.dart';
import 'package:flow_sync/core/privacy/differential_privacy_service.dart';
import 'package:flow_sync/core/privacy/dp_icl_consensus.dart';
import 'package:flow_sync/features/nlp/data/services/partial_reply_extractor.dart';
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
  final LlamaFfiService _llama;

  // Circuit Breaker State
  CircuitState _circuitState = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;

  final int _maxFailures = 2;
  final Duration _cooldownPeriod = const Duration(minutes: 5);

  AiOrchestrationService(this._supabase, this._llama);

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
        // Speculative Decoding: Draft 토큰 생성 시도 (백그라운드 isolate)
        final draft = await _tryGenerateDraft(command);

        final body = <String, dynamic>{
          'text': command.tokenizedText,
          if (chatHistory.isNotEmpty) 'chatHistory': chatHistory,
          // Draft가 있으면 Edge Function에 전송
          if (draft != null)
            ...SpeculativeDecodeManager.serializeDraft(draft),
        };

        final response = await _supabase.functions.invoke(
          'nlp-agent-function',
          body: body,
        );

        if (response.status >= 400) {
          throw Exception('Edge function error: ${response.status}');
        }

        final data = response.data as Map<String, dynamic>;

        // Speculative Decoding: Draft가 있으면 Accept/Reject 판정
        if (draft != null) {
          final cloudLogprobs =
              SpeculativeDecodeManager.extractCloudLogprobs(data);
          final result = SpeculativeDecodeManager.evaluate(
            draftResult: draft,
            cloudLogprobs: cloudLogprobs,
          );
          debugPrint('📊 [Speculative] $result');
        }

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
  /// [processCommand]와 동일한 파이프라인을 스트리밍 형태로 제공:
  ///   0. Local Early-Exit + DP-ICL 합의 → 네트워크 없이 즉시 [NlpFinalChunk]
  ///   1. Circuit Open → 오프라인 로컬 파서 폴백
  ///   2. Llama Draft 생성 → Edge Function에 첨부 (Speculative Decoding)
  ///   3. SSE 수신: [NlpTokenChunk] → [NlpFinalChunk]
  ///   4. 최종 응답 수신 전 실패 시 → 로컬 파서 폴백
  Stream<NlpStreamChunk> processCommandStream(
    NlpCommand command, {
    List<Map<String, String>> chatHistory = const [],
    bool enableEarlyExit = true,
  }) async* {
    // ── 0. Local Early-Exit + DP-ICL Noisy Consensus ─────────────────
    if (enableEarlyExit &&
        canLocalEarlyExit(command, chatHistory: chatHistory)) {
      final consensusResult = DpIclConsensus.runConsensus(
        command,
        (subset) => _tryLocalFallback(subset),
      );
      if (consensusResult != null) {
        debugPrint('⚡ [Stream Early-Exit + DP] 로컬 엔진 즉시 생성: "${command.rawText}"');
        yield NlpFinalChunk(_applyDpNoise(consensusResult));
        return;
      }
      debugPrint('🔒 [DP-ICL] 합의 불충분 → Cloud 경유');
    }

    // ── 1. Circuit Open → 오프라인 파서 ──────────────────────────────
    if (_isCircuitOpen()) {
      final fallback = _tryLocalFallback(command);
      if (fallback != null) {
        debugPrint('🔌 [Circuit Open] 로컬 파서 폴백');
        yield NlpFinalChunk(fallback);
        return;
      }
      throw CircuitOpenException();
    }

    // ── 2. Speculative Decoding: Draft 생성 (백그라운드 isolate) ──────
    final draft = await _tryGenerateDraft(command);

    final body = <String, dynamic>{
      'text': command.tokenizedText,
      if (chatHistory.isNotEmpty) 'chatHistory': chatHistory,
      if (draft != null) ...SpeculativeDecodeManager.serializeDraft(draft),
    };

    var receivedFinal = false;
    var yieldedTokens = false;
    final extractor = PartialReplyExtractor();
    try {
      // ── 3. 실시간 SSE 수신 (라인 단위로 도착 즉시 처리) ──────────────
      await for (final line in _openSseLines(body)) {
        final chunk = _parseSseLine(line, draft: draft, extractor: extractor);
        if (chunk == null) continue;
        if (chunk is NlpFinalChunk) receivedFinal = true;
        if (chunk is NlpTokenChunk) yieldedTokens = true;
        yield chunk;
      }

      if (!receivedFinal) {
        throw Exception('SSE stream ended without final payload');
      }
      _recordSuccess();
    } catch (e) {
      _recordFailure();

      // 최종 응답을 아직 못 받았다면 로컬 파서로 복구 시도
      if (!receivedFinal) {
        final fallback = _tryLocalFallback(command);
        if (fallback != null) {
          debugPrint('🛟 [Stream] Cloud 실패 → 로컬 파서 폴백: $e');
          // 이미 화면에 그려진 부분 답변은 지운다
          if (yieldedTokens) yield NlpResetChunk('local_fallback');
          yield NlpFinalChunk(fallback);
          return;
        }
      }
      throw CircuitOpenException('API Error: ${e.toString()}');
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // SSE 전송 계층
  // ──────────────────────────────────────────────────────────────────────

  /// 서버가 SSE 라인을 보내지 않고 멈춘 경우 끊어내는 유휴 타임아웃.
  static const _sseIdleTimeout = Duration(seconds: 20);

  /// 연결 수립(응답 헤더 수신)까지의 타임아웃.
  static const _sseConnectTimeout = Duration(seconds: 15);

  /// Draft 생성이 Cloud 요청을 지연시키지 않도록 하는 예산.
  /// 초과 시 Draft 없이 Cloud로 바로 진행한다.
  static const _draftBudget = Duration(milliseconds: 800);

  /// 테스트용: SSE 라인 공급자를 교체한다 (요청 body를 받아 라인 스트림 반환).
  @visibleForTesting
  Stream<String> Function(Map<String, dynamic> body)? sseTransportOverride;

  /// Edge Function에 스트리밍 요청을 보내고 응답을 **도착하는 즉시** 라인 단위로 yield.
  ///
  /// `supabase.functions.invoke()`는 응답 본문 전체를 버퍼링하므로
  /// 실시간 타이핑 효과가 불가능하다 → `http` StreamedResponse로 직접 수신.
  Stream<String> _openSseLines(Map<String, dynamic> body) async* {
    final override = sseTransportOverride;
    if (override != null) {
      yield* override(body);
      return;
    }

    final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/nlp-agent-function')
        .replace(queryParameters: {'streaming': 'true'});
    final accessToken =
        _supabase.auth.currentSession?.accessToken ?? Env.supabaseAnonKey;

    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Authorization': 'Bearer $accessToken',
          'apikey': Env.supabaseAnonKey,
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          'X-FlowSync-Streaming': 'true',
        })
        ..body = jsonEncode(body);

      final response = await client.send(request).timeout(_sseConnectTimeout);

      if (response.statusCode >= 400) {
        final errBody = await response.stream.bytesToString();
        throw Exception('Edge function error: ${response.statusCode} $errBody');
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/event-stream')) {
        // 구버전 서버(JSON 응답) 호환: 단일 final 라인으로 변환
        final text = await response.stream.bytesToString();
        yield 'data: ${jsonEncode({'type': 'final', 'payload': jsonDecode(text)})}';
        return;
      }

      yield* response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_sseIdleTimeout);
    } finally {
      client.close();
    }
  }

  /// Llama 모델이 로드되어 있으면 Draft 토큰을 생성. 실패/예산 초과 시 null.
  Future<LlamaDraftResult?> _tryGenerateDraft(NlpCommand command) async {
    try {
      if (!_llama.isLoaded) return null;
      Future<LlamaDraftResult?> draftFuture() async =>
          _llama.generateDraft(command.tokenizedText);
      return await draftFuture().timeout(_draftBudget, onTimeout: () {
        debugPrint('🦙 [Speculative] Draft 예산(${_draftBudget.inMilliseconds}ms) 초과 → 생략');
        return null;
      });
    } catch (e) {
      debugPrint('🦙 [Speculative] Draft 생성 예외 → 생략: $e');
      return null;
    }
  }

  /// Cloud 응답의 `cloudLogprobs`로 Draft Accept/Reject 판정 (로깅용).
  void _evaluateSpeculative(LlamaDraftResult? draft, Map<String, dynamic> data) {
    if (draft == null) return;
    final cloudLogprobs = SpeculativeDecodeManager.extractCloudLogprobs(data);
    final result = SpeculativeDecodeManager.evaluate(
      draftResult: draft,
      cloudLogprobs: cloudLogprobs,
    );
    debugPrint('📊 [Speculative] $result');
  }

  /// SSE 한 줄을 [NlpStreamChunk]로 변환. 표시할 내용이 없으면 null.
  ///
  /// - `token`: 미완성 JSON 조각 → [PartialReplyExtractor]로 답변 텍스트 delta만 추출
  /// - `reset`: 서버 캐스케이드(Flash-Lite → Flash) 재생성 → 누적 상태 초기화
  /// - `final`: 최종 페이로드 → DP 노이즈 적용 + Speculative 판정
  /// - `error`: 예외로 전파 (상위에서 폴백 처리)
  /// - 잘못된 JSON / `data: ` 이외의 라인은 무시
  NlpStreamChunk? _parseSseLine(
    String line, {
    required PartialReplyExtractor extractor,
    LlamaDraftResult? draft,
  }) {
    if (!line.startsWith('data: ')) return null;
    final jsonStr = line.substring(6).trim();
    if (jsonStr.isEmpty) return null;

    final Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }

    switch (json['type'] as String?) {
      case 'token':
        final delta = extractor.add(json['chunk'] as String? ?? '');
        return delta.isEmpty ? null : NlpTokenChunk(delta);
      case 'reset':
        extractor.reset();
        final reason = json['reason'] as String? ?? 'cascade';
        debugPrint('🔁 [Stream] 서버 캐스케이드 재생성: $reason');
        return NlpResetChunk(reason);
      case 'final':
        final payload = json['payload'];
        if (payload is! Map<String, dynamic>) return null;
        _evaluateSpeculative(draft, payload);
        return NlpFinalChunk(
          _applyDpNoise(AiSchedulingResponse.fromJson(payload)),
        );
      case 'error':
        throw Exception(json['message'] as String? ?? 'SSE stream error');
      default:
        return null;
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
