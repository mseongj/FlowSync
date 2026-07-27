import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/widgets/nlp_bottom_sheet.dart';
import 'package:flow_sync/features/schedule/presentation/bloc/schedule_bloc.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openAiChat(BuildContext context) {
    final getIt = GetIt.instance;
    final hasNlp = getIt.isRegistered<NlpInputBloc>();

    if (!hasNlp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'AI 기능을 사용할 수 없습니다. 서버 연결을 확인해 주세요.',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Use BlocProvider.value to pass the existing NlpInputBloc
    // from the widget tree into the modal bottom sheet's new context.
    final nlpBloc = context.read<NlpInputBloc>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<NlpInputBloc>.value(
        value: nlpBloc,
        child: const NlpBottomSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowSync Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Settings screen navigation
            },
          ),
        ],
      ),
      body: BlocBuilder<ScheduleBloc, ScheduleState>(
        builder: (context, state) {
          if (state is ScheduleLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ScheduleLoaded) {
            return Column(
              children: [
                TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: state.selectedDate,
                  currentDay: DateTime.now(),
                  selectedDayPredicate: (day) =>
                      isSameDay(state.selectedDate, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    context
                        .read<ScheduleBloc>()
                        .add(ScheduleDateSelected(selectedDay));
                  },
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Month',
                  },
                  eventLoader: (day) {
                    return state.allEvents.where((e) {
                      return e.startTime.year == day.year &&
                          e.startTime.month == day.month &&
                          e.startTime.day == day.day;
                    }).toList();
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: state.selectedDateEvents.isEmpty
                      ? const Center(
                          child: Text('No events for this day.'),
                        )
                      : ListView.builder(
                          itemCount: state.selectedDateEvents.length,
                          itemBuilder: (context, index) {
                            final event =
                                state.selectedDateEvents[index];
                            final timeFormat = DateFormat('h:mm a');
                            return ListTile(
                              leading: const Icon(Icons.event),
                              title: Text(event.title),
                              subtitle: Text(
                                '${timeFormat.format(event.startTime)}'
                                ' - '
                                '${timeFormat.format(event.endTime)}'
                                '\n${event.location}',
                              ),
                              isThreeLine: true,
                            );
                          },
                        ),
                ),
              ],
            );
          } else {
            return const Center(
              child: Text('Error loading schedule'),
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAiChat(context),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI Sync'),
      ),
    );
  }
}
