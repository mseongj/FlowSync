import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/schedule.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel _model;

  GeminiService(this.apiKey) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<List<Schedule>> parseScheduleFromText(String text) async {
    final prompt = '''
    사용자의 입력 메시지에서 일정 정보를 추출하여 JSON 배열 형식으로 응답해줘.
    각 일정은 다음 필드를 가져야 해:
    - title: 일정 제목
    - startTime: ISO8601 형식의 시작 시간 (날짜 정보가 없으면 오늘 날짜를 기준으로 추측)
    - endTime: ISO8601 형식의 종료 시간 (알 수 없으면 null)
    - location: 장소 (알 수 없으면 null)
    - category: "meeting", "personal", "deadline", "other" 중 하나
    - description: 상세 설명 (알 수 없으면 null)

    사용자 입력: "$text"
    현재 시각: ${DateTime.now().toIso8601String()}
    ''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final jsonResponse = jsonDecode(response.text ?? '[]');
      
      if (jsonResponse is List) {
        return jsonResponse.map((item) {
          // Add a unique ID and mark as AI recommended
          item['id'] = DateTime.now().millisecondsSinceEpoch.toString() + item['title'];
          item['isAIRecommended'] = true;
          return Schedule.fromJson(item);
        }).toList();
      }
      return [];
    } catch (e) {
      print('Gemini API Error: $e');
      return [];
    }
  }
}
