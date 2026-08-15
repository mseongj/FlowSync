import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/features/family/domain/entities/family.dart';
import 'package:flow_sync/features/family/presentation/bloc/family_bloc.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
    context.read<FamilyBloc>().add(FamilyStarted());
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: BlocConsumer<FamilyBloc, FamilyState>(
        listener: (context, state) {
          if (state is FamilyJoined) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${state.family.name} 가족에 합류했습니다! 🎉'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          } else if (state is FamilyError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                behavior: SnackBarBehavior.floating,
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          return FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              slivers: [
                _buildAppBar(colorScheme),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildBody(context, state, colorScheme),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────

  SliverAppBar _buildAppBar(ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        title: const Text(
          '가족 그룹',
          style: TextStyle(
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
                colorScheme.secondary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.family_restroom_rounded,
              size: 60,
              color: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    FamilyState state,
    ColorScheme colorScheme,
  ) {
    if (state is FamilyLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 60),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (state is FamilyLoaded || state is FamilyInviteReady || state is FamilyJoined) {
      final family = state is FamilyLoaded
          ? state.family
          : state is FamilyInviteReady
              ? state.family
              : (state as FamilyJoined).family;

      return _buildFamilyView(context, family, state, colorScheme);
    }

    // FamilyNotFound or FamilyInitial
    return _buildNoFamilyView(context, colorScheme);
  }

  // ── No Family ─────────────────────────────────────────────────

  Widget _buildNoFamilyView(BuildContext context, ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                colorScheme.primary.withValues(alpha: 0.15),
                colorScheme.secondary.withValues(alpha: 0.15),
              ],
            ),
          ),
          child: Icon(
            Icons.group_add_rounded,
            size: 50,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '아직 가족 그룹이 없어요',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '가족 그룹을 만들거나\n초대 링크로 참여해 보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.55),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 40),
        // Create family button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: () => _showCreateFamilyDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              '가족 그룹 만들기',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Join via link button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: () => _showJoinDialog(context),
            icon: const Icon(Icons.link_rounded),
            label: const Text(
              '초대 링크로 참여',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Family Loaded ─────────────────────────────────────────────

  Widget _buildFamilyView(
    BuildContext context,
    Family family,
    FamilyState state,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Family name card
        _FamilyHeaderCard(family: family, colorScheme: colorScheme),

        const SizedBox(height: 24),

        // Invite card (shows when invite is ready)
        if (state is FamilyInviteReady)
          _InviteLinkCard(
            invite: state.invite,
            colorScheme: colorScheme,
          ),

        if (state is FamilyInviteReady) const SizedBox(height: 16),

        // Members section
        Text(
          '멤버 (${family.members.length}명)',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),

        if (family.members.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '멤버 정보를 불러오는 중...',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        else
          ...family.members.map(
            (m) => _MemberTile(member: m, colorScheme: colorScheme),
          ),

        const SizedBox(height: 24),

        // Share invite button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: () => context
                .read<FamilyBloc>()
                .add(FamilyInviteLinkRequested(family.id)),
            icon: const Icon(Icons.share_rounded),
            label: const Text(
              '초대 링크 생성',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────

  void _showCreateFamilyDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('가족 그룹 이름'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '예: 김씨 가족',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context
                    .read<FamilyBloc>()
                    .add(FamilyCreateRequested(name));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('만들기'),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('초대 코드 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '초대 링크에서 복사한 ID를 붙여넣으세요',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final inviteId = controller.text.trim();
              if (inviteId.isNotEmpty) {
                context
                    .read<FamilyBloc>()
                    .add(FamilyInviteAccepted(inviteId));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('참여'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-Widgets ────────────────────────────────────────────────

class _FamilyHeaderCard extends StatelessWidget {
  final Family family;
  final ColorScheme colorScheme;

  const _FamilyHeaderCard({
    required this.family,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.12),
            colorScheme.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
              ),
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '멤버 ${family.members.length}명',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
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

class _InviteLinkCard extends StatelessWidget {
  final FamilyInvite invite;
  final ColorScheme colorScheme;

  const _InviteLinkCard({
    required this.invite,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 18,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                '초대 링크 생성 완료',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.secondary,
                ),
              ),
              const Spacer(),
              Text(
                '24시간 유효',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              invite.deepLinkUri,
              style: TextStyle(
                fontFamily: Platform.isIOS ? 'Courier' : 'monospace',
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: invite.deepLinkUri),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('링크가 클립보드에 복사되었습니다 📋'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('링크 복사'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final FamilyMember member;
  final ColorScheme colorScheme;

  const _MemberTile({
    required this.member,
    required this.colorScheme,
  });

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.deepPurple;
      case 'parent':
        return Colors.blue;
      case 'teenager':
        return Colors.orange;
      case 'grandparent':
        return Colors.teal;
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(member.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: roleColor.withValues(alpha: 0.15),
            child: Icon(
              member.roleIcon,
              size: 20,
              color: roleColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.email.isNotEmpty ? member.email : member.userId,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.joinedAt.toLocal().toString().substring(0, 10),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showRoleChangeSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: roleColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    member.roleLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: roleColor,
                    ),
                  ),
                  if (member.isReadOnly) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: roleColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRoleChangeSheet(BuildContext context) {
    // Get current user's membership to check if they can manage
    final bloc = context.read<FamilyBloc>();
    final currentState = bloc.state;
    Family? family;
    if (currentState is FamilyLoaded) {
      family = currentState.family;
    } else if (currentState is FamilyInviteReady) {
      family = currentState.family;
    }
    if (family == null) return;

    // Check if current user is admin or parent
    final supabase = Supabase.instance.client;
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final currentMember = family.members.cast<FamilyMember?>().firstWhere(
          (m) => m!.userId == currentUserId,
          orElse: () => null,
        );
    if (currentMember == null || !currentMember.canManageRoles) {
      return; // Not authorized
    }

    // Can't change own role
    if (member.userId == currentUserId) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '역할 변경',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              member.email.isNotEmpty ? member.email : member.userId,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...FamilyRole.assignableRoles.map((role) {
              final isSelected = member.role == role;
              final color = _roleColor(role);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(
                      FamilyRole.icon(role),
                      color: color,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    FamilyRole.label(role),
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: color)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? color.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  tileColor: isSelected
                      ? color.withValues(alpha: 0.06)
                      : null,
                  onTap: isSelected
                      ? null
                      : () {
                          Navigator.pop(context);
                          context.read<FamilyBloc>().add(
                                MemberRoleChangeRequested(
                                  member.familyId,
                                  member.userId,
                                  role,
                                ),
                              );
                        },
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
