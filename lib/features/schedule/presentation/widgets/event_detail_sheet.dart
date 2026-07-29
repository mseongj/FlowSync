import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';
import 'package:flow_sync/features/schedule/presentation/bloc/schedule_bloc.dart';

/// Premium bottom sheet that shows event details with delete & edit actions.
class EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;

  const EventDetailSheet({super.key, required this.event});

  static Future<void> show(BuildContext context, CalendarEvent event) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider<ScheduleBloc>.value(
        value: context.read<ScheduleBloc>(),
        child: EventDetailSheet(event: event),
      ),
    );
  }

  Color _visibilityColor(ColorScheme cs) {
    return switch (event.visibility) {
      EventVisibility.public  => cs.primary,
      EventVisibility.private => const Color(0xFFFF9800),
      EventVisibility.secret  => const Color(0xFFE53935),
    };
  }

  String _visibilityLabel() {
    return switch (event.visibility) {
      EventVisibility.public  => '공개',
      EventVisibility.private => '비공개',
      EventVisibility.secret  => '비밀',
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
    final visColor = _visibilityColor(cs);
    final timeFormat = DateFormat('yyyy.MM.dd  HH:mm', 'ko');

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Visibility badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: visColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: visColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_visibilityIcon(), size: 14, color: visColor),
                      const SizedBox(width: 4),
                      Text(
                        _visibilityLabel(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: visColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.isOfflineCreated) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          size: 13,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '동기화 대기 중',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                event.visibility == EventVisibility.secret
                    ? '🔒 비밀 일정'
                    : event.title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Details
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: '시작',
            value: timeFormat.format(event.startTime),
            cs: cs,
          ),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: '종료',
            value: timeFormat.format(event.endTime),
            cs: cs,
          ),
          if (event.location.isNotEmpty)
            _InfoRow(
              icon: Icons.place_rounded,
              label: '장소',
              value: event.location,
              cs: cs,
            ),
          if (event.description.isNotEmpty &&
              event.visibility != EventVisibility.secret)
            _InfoRow(
              icon: Icons.notes_rounded,
              label: '메모',
              value: event.description,
              cs: cs,
            ),

          const SizedBox(height: 24),
          const Divider(height: 1, indent: 24, endIndent: 24),
          const SizedBox(height: 16),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Delete button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmDelete(context),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: cs.error,
                    ),
                    label: Text(
                      '삭제',
                      style: TextStyle(color: cs.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Edit button
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/event/edit');
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('수정'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    final bloc = context.read<ScheduleBloc>();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text(
          '"${event.title.isEmpty ? '비밀 일정' : event.title}"을 삭제할까요?\n이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              bloc.add(ScheduleEventDeleted(event.id));
              Navigator.pop(dialogCtx);  // close dialog
              Navigator.pop(context);   // close sheet
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
