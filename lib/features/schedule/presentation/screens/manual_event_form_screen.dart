import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:flow_sync/features/nlp/domain/entities/ai_scheduling_response.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';
import 'package:flow_sync/features/schedule/presentation/bloc/schedule_bloc.dart';

class ManualEventFormScreen extends StatefulWidget {
  /// Pre-filled from AI suggestion. Null when creating a brand-new event.
  final AiSchedulingResponse? prefill;

  const ManualEventFormScreen({super.key, this.prefill});

  @override
  State<ManualEventFormScreen> createState() => _ManualEventFormScreenState();
}

class _ManualEventFormScreenState extends State<ManualEventFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _startTime;
  late DateTime _endTime;
  EventVisibility _visibility = EventVisibility.public;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    // Pre-fill from AI suggestion
    final now = DateTime.now();
    _startTime = widget.prefill?.startTime ??
        DateTime(now.year, now.month, now.day, now.hour + 1);
    _endTime = widget.prefill?.endTime ??
        _startTime.add(const Duration(hours: 1));

    if (widget.prefill != null) {
      _titleController.text =
          widget.prefill!.eventTitleTokenized ?? '';
      _locationController.text =
          widget.prefill!.locationTokenized ?? '';
    }

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Date / Time Pickers ──────────────────────────────────────

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      _startTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startTime.hour,
        _startTime.minute,
      );
      // Keep end after start
      if (_endTime.isBefore(_startTime)) {
        _endTime = _startTime.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (picked == null) return;
    setState(() {
      _startTime = DateTime(
        _startTime.year,
        _startTime.month,
        _startTime.day,
        picked.hour,
        picked.minute,
      );
      if (_endTime.isBefore(_startTime)) {
        _endTime = _startTime.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (picked == null) return;
    setState(() {
      _endTime = DateTime(
        _startTime.year,
        _startTime.month,
        _startTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  // ── Save ──────────────────────────────────────────────────────

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final event = CalendarEvent(
      id: const Uuid().v4(),
      familyId: 'family_1',
      creatorId: 'user_1',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      location: _locationController.text.trim(),
      startTime: _startTime,
      endTime: _endTime.isBefore(_startTime)
          ? _startTime.add(const Duration(hours: 1))
          : _endTime,
      visibility: _visibility,
      isOfflineCreated: true,
    );

    context.read<ScheduleBloc>().add(ScheduleEventSaved(event));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('일정이 저장되었습니다 ✅'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    context.pop();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAiPrefilled = widget.prefill != null;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: CustomScrollView(
            slivers: [
              // Gradient app bar
              SliverAppBar(
                expandedHeight: 140,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
                  title: Text(
                    isAiPrefilled ? 'AI 제안 수정' : '새 일정',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.tertiary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: isAiPrefilled
                        ? Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Chip(
                                avatar: const Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'AI 자동 채움',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                side: const BorderSide(color: Colors.transparent),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 제목 ────────────────────────────────
                        _SectionCard(
                          icon: Icons.title_rounded,
                          label: '제목',
                          colorScheme: colorScheme,
                          child: TextFormField(
                            controller: _titleController,
                            decoration: _fieldDecoration('일정 제목을 입력하세요'),
                            style: const TextStyle(fontSize: 16),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? '제목을 입력해 주세요'
                                    : null,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── 날짜 & 시간 ──────────────────────────
                        _SectionCard(
                          icon: Icons.calendar_today_rounded,
                          label: '날짜 & 시간',
                          colorScheme: colorScheme,
                          child: Column(
                            children: [
                              // Date row
                              _PickerRow(
                                label: '날짜',
                                value: DateFormat(
                                  'y년 M월 d일 (E)',
                                  'ko',
                                ).format(_startTime),
                                onTap: _pickStartDate,
                                colorScheme: colorScheme,
                              ),
                              const Divider(height: 1),
                              // Start time
                              _PickerRow(
                                label: '시작',
                                value: DateFormat('a h:mm', 'ko')
                                    .format(_startTime),
                                onTap: _pickStartTime,
                                colorScheme: colorScheme,
                              ),
                              const Divider(height: 1),
                              // End time
                              _PickerRow(
                                label: '종료',
                                value: DateFormat('a h:mm', 'ko')
                                    .format(_endTime),
                                onTap: _pickEndTime,
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── 장소 ────────────────────────────────
                        _SectionCard(
                          icon: Icons.location_on_outlined,
                          label: '장소',
                          colorScheme: colorScheme,
                          child: TextFormField(
                            controller: _locationController,
                            decoration: _fieldDecoration('장소를 입력하세요 (선택)'),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── 설명 ────────────────────────────────
                        _SectionCard(
                          icon: Icons.notes_rounded,
                          label: '메모',
                          colorScheme: colorScheme,
                          child: TextFormField(
                            controller: _descriptionController,
                            decoration: _fieldDecoration('메모를 입력하세요 (선택)'),
                            maxLines: 3,
                            minLines: 1,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── 공개 범위 ────────────────────────────
                        _SectionCard(
                          icon: Icons.lock_outline_rounded,
                          label: '공개 범위',
                          colorScheme: colorScheme,
                          child: _VisibilitySelector(
                            value: _visibility,
                            onChanged: (v) => setState(() => _visibility = v),
                            colorScheme: colorScheme,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ── 저장 버튼 ────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text(
                              '일정 저장',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  final ColorScheme colorScheme;

  const _SectionCard({
    required this.icon,
    required this.label,
    required this.child,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilitySelector extends StatelessWidget {
  final EventVisibility value;
  final ValueChanged<EventVisibility> onChanged;
  final ColorScheme colorScheme;

  const _VisibilitySelector({
    required this.value,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SegmentedButton<EventVisibility>(
        segments: const [
          ButtonSegment(
            value: EventVisibility.public,
            icon: Icon(Icons.public, size: 16),
            label: Text('전체'),
          ),
          ButtonSegment(
            value: EventVisibility.private,
            icon: Icon(Icons.people_outline, size: 16),
            label: Text('가족'),
          ),
          ButtonSegment(
            value: EventVisibility.secret,
            icon: Icon(Icons.lock, size: 16),
            label: Text('나만'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor:
              colorScheme.primary.withValues(alpha: 0.12),
          selectedForegroundColor: colorScheme.primary,
        ),
      ),
    );
  }
}
