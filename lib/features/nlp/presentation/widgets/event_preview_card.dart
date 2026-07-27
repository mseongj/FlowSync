import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';

class EventPreviewCard extends StatefulWidget {
  final AiSchedulingResponse aiResponse;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;

  const EventPreviewCard({
    super.key,
    required this.aiResponse,
    required this.onConfirm,
    required this.onEdit,
  });

  @override
  State<EventPreviewCard> createState() => _EventPreviewCardState();
}

class _EventPreviewCardState extends State<EventPreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '시간 미정';
    return DateFormat('M/d (E) h:mm a', 'ko').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final response = widget.aiResponse;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.primaryContainer,
                colorScheme.primaryContainer.withValues(alpha: 0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.event_available,
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '새 일정 제안',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Event details
                if (response.eventTitleTokenized != null)
                  _DetailRow(
                    icon: Icons.title,
                    label: response.eventTitleTokenized!,
                    colorScheme: colorScheme,
                  ),
                if (response.startTime != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.access_time_rounded,
                    label: _formatTime(response.startTime),
                    colorScheme: colorScheme,
                  ),
                ],
                if (response.endTime != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.timelapse_rounded,
                    label: '~ ${_formatTime(response.endTime)}',
                    colorScheme: colorScheme,
                  ),
                ],
                if (response.locationTokenized != null &&
                    response.locationTokenized!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    label: response.locationTokenized!,
                    colorScheme: colorScheme,
                  ),
                ],

                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('수정'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(
                            color: colorScheme.outline.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onConfirm,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('확인'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}
