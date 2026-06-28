import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/schedule_provider.dart';
import '../models/schedule.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final TextEditingController _aiController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    final scheduleProvider = Provider.of<ScheduleProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('FlowSync - AI 일정 비서'),
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            eventLoader: (day) {
              return scheduleProvider.getSchedulesForDay(day);
            },
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: _buildScheduleList(scheduleProvider),
          ),
          _buildAIInput(scheduleProvider),
        ],
      ),
    );
  }

  Widget _buildScheduleList(ScheduleProvider provider) {
    final daySchedules = provider.getSchedulesForDay(_selectedDay!);

    if (daySchedules.isEmpty) {
      return Center(child: Text('일정이 없습니다.'));
    }

    return ListView.builder(
      itemCount: daySchedules.itemCount,
      itemBuilder: (context, index) {
        final schedule = daySchedules[index];
        return ListTile(
          leading: Icon(_getCategoryIcon(schedule.category)),
          title: Text(schedule.title),
          subtitle: Text(
            '${DateFormat('HH:mm').format(schedule.startTime)} @ ${schedule.location ?? "장소 미정"}',
          ),
          trailing: schedule.isAIRecommended 
            ? Chip(label: Text('AI', style: TextStyle(fontSize: 10))) 
            : null,
        );
      },
    );
  }

  IconData _getCategoryIcon(ScheduleCategory category) {
    switch (category) {
      case ScheduleCategory.meeting: return Icons.groups;
      case ScheduleCategory.personal: return Icons.person;
      case ScheduleCategory.deadline: return Icons.priority_high;
      case ScheduleCategory.other: return Icons.event;
    }
  }

  Widget _buildAIInput(ScheduleProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _aiController,
              decoration: InputDecoration(
                hintText: '예: 내일 오후 3시에 강남역에서 미팅',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () async {
              if (_aiController.text.isNotEmpty) {
                final text = _aiController.text;
                _aiController.clear();
                await provider.processAIInput(text);
              }
            },
          ),
        ],
      ),
    );
  }
}

extension on List<Schedule> {
  int get itemCount => length;
}
