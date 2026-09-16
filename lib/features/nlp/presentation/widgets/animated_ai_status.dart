import 'package:flutter/material.dart';

/// AI 상태를 헤더에 표시하는 위젯.
/// [isProcessing]이 true이면 "AI가 생각 중..." (점멸 효과),
/// false이면 "AI 일정 비서" 타이틀을 표시한다.
class AnimatedAiStatus extends StatefulWidget {
  const AnimatedAiStatus({required this.isProcessing, super.key});

  final bool isProcessing;

  @override
  State<AnimatedAiStatus> createState() => _AnimatedAiStatusState();
}

class _AnimatedAiStatusState extends State<AnimatedAiStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: widget.isProcessing
          ? FadeTransition(
              key: const ValueKey('processing'),
              opacity: _pulseAnim,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AI가 생각 중',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  _AnimatedEllipsis(color: colorScheme.primary),
                ],
              ),
            )
          : Text(
              'AI 일정 비서',
              key: const ValueKey('idle'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
    );
  }
}

/// 말 줄임표(...)가 순차적으로 나타나는 미니 애니메이션 위젯
class _AnimatedEllipsis extends StatefulWidget {
  const _AnimatedEllipsis({required this.color});

  final Color color;

  @override
  State<_AnimatedEllipsis> createState() => _AnimatedEllipsisState();
}

class _AnimatedEllipsisState extends State<_AnimatedEllipsis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _dotCount = (_dotCount % 3) + 1;
            });
            _ctrl.forward(from: 0);
          }
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '.' * _dotCount,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: widget.color,
        letterSpacing: 1.5,
      ),
    );
  }
}
