import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:flow_sync/features/family/presentation/bloc/family_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_bloc.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_event.dart';
import 'package:flow_sync/features/nlp/presentation/bloc/nlp_input_state.dart';
import 'package:flow_sync/features/nlp/presentation/widgets/animated_ai_status.dart';
import 'package:flow_sync/features/nlp/presentation/widgets/chat_history_list.dart';
import 'package:flow_sync/features/nlp/presentation/widgets/event_preview_card.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';

class NlpBottomSheet extends StatefulWidget {
  const NlpBottomSheet({super.key});

  @override
  State<NlpBottomSheet> createState() => _NlpBottomSheetState();
}

class _NlpBottomSheetState extends State<NlpBottomSheet>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const _quickActions = [
    '내일 3시 미팅 잡아줘',
    '오늘 저녁 약속 추가',
    '이번 주 일정 보여줘',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Zero-Knowledge Security: wipe ephemeral tokens
      context.read<NlpInputBloc>().add(NlpMemoryZeroed());
      Navigator.of(context).pop();
    }
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    context.read<NlpInputBloc>().add(NlpMessageSent(trimmed));
    _textController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(28),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.surface.withValues(alpha: 0.92),
                colorScheme.surface.withValues(alpha: 0.96),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              children: [
                // Drag handle
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.tertiary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      BlocBuilder<NlpInputBloc, NlpInputState>(
                        builder: (context, state) {
                          final isProcessing = state is NlpProcessing;
                          return AnimatedAiStatus(isProcessing: isProcessing);
                        },
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                Divider(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  height: 16,
                ),

                // Chat area
                Expanded(
                  child: BlocConsumer<NlpInputBloc, NlpInputState>(
                    listener: (context, state) {
                      if (state is NlpError && state.isCircuitOpen) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'AI가 쉬고 있어요. 수동 입력을 이용해 주세요.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                        Navigator.of(context).pop();
                      }
                    },
                    builder: (context, state) {
                      return _buildChatContent(context, state, colorScheme);
                    },
                  ),
                ),

                // Input bar
                _buildInputBar(context, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatContent(
    BuildContext context,
    NlpInputState state,
    ColorScheme colorScheme,
  ) {
    // Determine chat messages from state
    var chatHistory = <dynamic>[];
    if (state is NlpInitial) {
      chatHistory = state.chatHistory;
    } else if (state is NlpProcessing) {
      chatHistory = state.chatHistory;
    } else if (state is NlpResponseReady) {
      chatHistory = state.chatHistory;
    } else if (state is NlpError) {
      chatHistory = state.chatHistory;
    }

    // Empty state — show welcome + quick actions
    if (chatHistory.isEmpty) {
      return _buildEmptyState(colorScheme);
    }

    // Chat + optional event card
    return Column(
      children: [
        Expanded(
          child: ChatHistoryList(
            messages: List.from(chatHistory),
          ),
        ),
        if (state is NlpResponseReady &&
            (state.aiResponse.intent == 'CREATE_EVENT' ||
                state.aiResponse.intent == 'RESCHEDULE'))
          _SlideUpFadeIn(
            child: EventPreviewCard(
              aiResponse: state.aiResponse,
              onConfirm: () {
                // Get real user/family IDs from auth & bloc state
                final userId =
                    Supabase.instance.client.auth.currentUser?.id ?? '';
                final familyState = context.read<FamilyBloc>().state;
                final familyId = familyState is FamilyLoaded
                    ? familyState.family.id
                    : (familyState is FamilyInviteReady
                        ? familyState.family.id
                        : '');

                final eventId = (state.aiResponse.intent == 'RESCHEDULE' &&
                        state.aiResponse.targetEventId != null)
                    ? state.aiResponse.targetEventId!
                    : const Uuid().v4();

                final event = CalendarEvent(
                  id: eventId,
                  familyId: familyId,
                  creatorId: userId,
                  title: state.aiResponse.eventTitleTokenized ?? '새 일정',
                  description: state.aiResponse.intent == 'RESCHEDULE'
                      ? 'AI가 수정한 일정'
                      : 'AI가 생성한 일정',
                  location: state.aiResponse.locationTokenized ?? '',
                  startTime:
                      state.aiResponse.startTime ?? DateTime.now(),
                  endTime: state.aiResponse.endTime ??
                      DateTime.now().add(const Duration(hours: 1)),
                  visibility: EventVisibility.public,
                  isOfflineCreated: true,
                );
                context
                    .read<NlpInputBloc>()
                    .add(NlpEventConfirmed(event));
                Navigator.of(context).pop();
              },
              onEdit: () {
                Navigator.of(context).pop();
                context.push('/event/edit', extra: state.aiResponse);
              },
            ),
          ),
        if (state is NlpResponseReady &&
            state.aiResponse.intent == 'CANCEL')
          _SlideUpFadeIn(
            child: EventCancelCard(
              aiResponse: state.aiResponse,
              onConfirmCancel: () {
                context.read<NlpInputBloc>().add(
                      NlpEventCancelled(
                        state.aiResponse.targetEventId ?? '',
                        eventTitle:
                            state.aiResponse.eventTitleTokenized ?? '일정',
                      ),
                    );
                Navigator.of(context).pop();
              },
              onDismiss: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        if (state is NlpError && !state.isCircuitOpen)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.1),
                    colorScheme.tertiary.withValues(alpha: 0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 40,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI에게 일정을 말해보세요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '자연어로 일정을 입력하면\nAI가 자동으로 분석합니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _quickActions.map((action) {
                return ActionChip(
                  avatar: Icon(
                    Icons.flash_on,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  label: Text(
                    action,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  backgroundColor:
                      colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  onPressed: () => _sendMessage(action),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: '일정을 입력하세요...',
                    hintStyle: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child: Icon(
                        Icons.mic_none_rounded,
                        color:
                            colorScheme.onSurface.withValues(alpha: 0.3),
                        size: 22,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: colorScheme.onSurface,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                ),
              ),
            ),
            const SizedBox(width: 8),
            BlocBuilder<NlpInputBloc, NlpInputState>(
              builder: (context, state) {
                final isProcessing = state is NlpProcessing;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: isProcessing
                        ? null
                        : LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.tertiary,
                            ],
                          ),
                    color: isProcessing
                        ? colorScheme.surfaceContainerHighest
                        : null,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: isProcessing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                    onPressed: isProcessing
                        ? null
                        : () => _sendMessage(_textController.text),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 슬라이드 업 + 페이드 인 애니메이션으로 카드를 자연스럽게 등장시킨다.
class _SlideUpFadeIn extends StatefulWidget {
  const _SlideUpFadeIn({required this.child});

  final Widget child;

  @override
  State<_SlideUpFadeIn> createState() => _SlideUpFadeInState();
}

class _SlideUpFadeInState extends State<_SlideUpFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
