import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:flow_sync/features/family/presentation/bloc/family_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/widgets/nlp_bottom_sheet.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';
import 'package:flow_sync/features/schedule/presentation/bloc/schedule_bloc.dart';
import 'package:flow_sync/features/schedule/presentation/widgets/event_detail_sheet.dart';

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
    return BlocListener<FamilyBloc, FamilyState>(
      listener: (context, familyState) {
        // When family is identified, sync family events into ScheduleBloc
        if (familyState is FamilyLoaded || familyState is FamilyJoined) {
          final family = familyState is FamilyLoaded
              ? familyState.family
              : (familyState as FamilyJoined).family;

          final currentUserId =
              Supabase.instance.client.auth.currentUser?.id ?? '';

          context.read<ScheduleBloc>().add(
                FamilyGroupSet(
                  familyId: family.id,
                  currentUserId: currentUserId,
                ),
              );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<ScheduleBloc, ScheduleState>(
            builder: (context, state) {
              if (state is ScheduleLoaded && state.isFamilyView) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('FlowSync'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.family_restroom_rounded,
                            size: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '가족',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return const Text('FlowSync');
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.family_restroom_rounded),
              tooltip: '가족 그룹',
              onPressed: () => context.push('/family'),
            ),
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
                    calendarStyle: CalendarStyle(
                      markerDecoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: state.selectedDateEvents.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_available_rounded,
                                  size: 52,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.18),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '이 날에는 일정이 없어요',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.38),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: state.selectedDateEvents.length,
                            itemBuilder: (context, index) {
                              final event = state.selectedDateEvents[index];
                              return _EventCard(
                                event: event,
                                onTap: () =>
                                    EventDetailSheet.show(context, event),
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
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'fab_new_event',
              onPressed: () => context.push('/event/new'),
              tooltip: '새 일정 추가',
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'fab_ai_sync',
              onPressed: () => _openAiChat(context),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI Sync'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Premium Event Card ─────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  Color _visibilityColor(ColorScheme cs) {
    return switch (event.visibility) {
      EventVisibility.public  => cs.primary,
      EventVisibility.private => const Color(0xFFFF9800),
      EventVisibility.secret  => const Color(0xFFE53935),
    };
  }

  IconData _visibilityIcon() {
    return switch (event.visibility) {
      EventVisibility.public  => Icons.public_rounded,
      EventVisibility.private => Icons.lock_outline_rounded,
      EventVisibility.secret  => Icons.shield_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeFormat = DateFormat('HH:mm', 'ko');
    final accentColor = _visibilityColor(cs);
    final isSecret = event.visibility == EventVisibility.secret;
    final isFamilyEvent = event.creatorName != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.2),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title row
                            Row(
                              children: [
                                Icon(
                                  _visibilityIcon(),
                                  size: 14,
                                  color: accentColor.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isSecret ? '🔒 비밀 일정' : event.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Time + location
                            Text(
                              '${timeFormat.format(event.startTime)} – '
                              '${timeFormat.format(event.endTime)}'
                              '${event.location.isNotEmpty && !isSecret ? '  ·  ${event.location}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Family member badge
                            if (isFamilyEvent) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_rounded,
                                    size: 12,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    event.creatorName!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Offline sync badge
                      if (event.isOfflineCreated) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: '동기화 대기 중',
                          child: Icon(
                            Icons.cloud_upload_outlined,
                            size: 16,
                            color: Colors.orange.shade400,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
