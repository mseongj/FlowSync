import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/nlp_command.dart';
import '../../domain/entities/ai_scheduling_response.dart';

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

  // Deterministic Tokenizer (Simple NER using Regex for demo)
  NlpCommand tokenize(String rawText) {
    final tokenMap = <String, String>{};
    var tokenizedText = rawText;

    // A very basic simulated NER for names starting with Capital letters
    // In production, use google_mlkit_entity_extraction
    final nameExp = RegExp(r'\b[A-Z][a-z]+\b');
    var personCount = 1;

    for (final match in nameExp.allMatches(rawText)) {
      final name = match.group(0)!;
      // Skip common non-names
      if ([
        'Meeting',
        'Dentist',
        'Doctor',
        'Dinner',
        'Lunch',
        'Tomorrow',
        'Today',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ].contains(name)) {
        continue;
      }

      final token = '[PERSON_$personCount]';
      tokenMap[token] = name;
      tokenizedText = tokenizedText.replaceAll(name, token);
      personCount++;
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

  Future<AiSchedulingResponse> processCommand(
    NlpCommand command, {
    List<Map<String, String>> chatHistory = const [],
  }) async {
    if (_isCircuitOpen()) {
      throw CircuitOpenException();
    }

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
      return AiSchedulingResponse.fromJson(data);
    } catch (e) {
      _recordFailure();

      // Try local fallback before giving up
      final fallback = _tryLocalFallback(command);
      if (fallback != null) {
        return fallback;
      }

      throw CircuitOpenException('API Error: ${e.toString()}');
    }
  }

  /// Local fallback NLP: parses simple scheduling patterns offline
  /// when the Edge Function is unavailable.
  AiSchedulingResponse? _tryLocalFallback(NlpCommand command) {
    final text = command.tokenizedText.toLowerCase();
    final now = DateTime.now();

    // --- Time Extraction ---
    DateTime? startTime;
    DateTime? endTime;

    // Pattern: "내일" / "tomorrow"
    final isTomorrow =
        text.contains('내일') || text.contains('tomorrow');
    final isToday =
        text.contains('오늘') || text.contains('today');
    final baseDate = isTomorrow
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    // Pattern: "3시" or "3pm" or "15시" or "at 3"
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
      // Default to today if no date mentioned but time was found
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

    // Build reply message
    final timeStr = startTime != null
        ? '${startTime.month}/${startTime.day} '
            '${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')}'
        : '시간 미정';

    return AiSchedulingResponse(
      intent: 'CREATE_EVENT',
      eventTitleTokenized: title,
      locationTokenized: '',
      startTime: startTime,
      endTime: endTime,
      participantsTokenized: const [],
      aiReplyMessage:
          '📅 "$title" 일정을 $timeStr에 생성할까요?\n'
          '(오프라인 모드 — 로컬 분석 결과)',
    );
  }
}
