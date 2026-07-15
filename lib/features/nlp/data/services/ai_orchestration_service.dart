import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/nlp_command.dart';
import '../../domain/entities/ai_scheduling_response.dart';

class CircuitOpenException implements Exception {
  final String message;
  CircuitOpenException([this.message = 'AI Assistant is resting. Opening manual form.']);
}

enum CircuitState { closed, open, halfOpen }

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
    Map<String, String> tokenMap = {};
    String tokenizedText = rawText;

    // A very basic simulated NER for names starting with Capital letters 
    // In production, use google_mlkit_entity_extraction
    final nameExp = RegExp(r'\b[A-Z][a-z]+\b');
    int personCount = 1;
    
    for (final match in nameExp.allMatches(rawText)) {
      final name = match.group(0)!;
      // Skip common non-names
      if (['Meeting', 'Dentist', 'Doctor', 'Dinner', 'Lunch', 'Tomorrow', 'Today'].contains(name)) {
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
      final timeSinceLastFailure = DateTime.now().difference(_lastFailureTime!);
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

  Future<AiSchedulingResponse> processCommand(NlpCommand command) async {
    if (_isCircuitOpen()) {
      throw CircuitOpenException();
    }

    try {
      final response = await _supabase.functions.invoke(
        'nlp-agent-function',
        body: {'text': command.tokenizedText},
      );

      if (response.status >= 400) {
        throw Exception('Edge function error: ${response.status}');
      }

      final data = response.data as Map<String, dynamic>;
      
      _recordSuccess();
      return AiSchedulingResponse.fromJson(data);

    } catch (e) {
      _recordFailure();
      // If we failed, re-throw to trigger graceful degradation to manual UI
      throw CircuitOpenException('API Error: ${e.toString()}');
    }
  }
}
