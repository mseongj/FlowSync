import 'package:flutter/material.dart';
import '../models/schedule.dart';
import '../services/gemini_service.dart';

class ScheduleProvider with ChangeNotifier {
  final List<Schedule> _schedules = [];
  final GeminiService _geminiService;

  ScheduleProvider(this._geminiService);

  List<Schedule> get schedules => [..._schedules];

  List<Schedule> getSchedulesForDay(DateTime day) {
    return _schedules.where((s) => 
      s.startTime.year == day.year &&
      s.startTime.month == day.month &&
      s.startTime.day == day.day
    ).toList();
  }

  void addSchedule(Schedule schedule) {
    _schedules.add(schedule);
    notifyListeners();
  }

  void removeSchedule(String id) {
    _schedules.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  Future<void> processAIInput(String text) async {
    final newSchedules = await _geminiService.parseScheduleFromText(text);
    for (var schedule in newSchedules) {
      _schedules.add(schedule);
    }
    notifyListeners();
  }
}
