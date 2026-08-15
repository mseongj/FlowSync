import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flow_sync/features/family/domain/entities/family.dart';
import 'package:flow_sync/features/family/domain/repositories/i_family_repository.dart';

// ── Events ────────────────────────────────────────────────────

abstract class FamilyEvent {}

/// Load the current user's family on startup.
class FamilyStarted extends FamilyEvent {}

/// Create a new family with the given name.
class FamilyCreateRequested extends FamilyEvent {
  final String name;
  FamilyCreateRequested(this.name);
}

/// Generate an invite link for the current family.
class FamilyInviteLinkRequested extends FamilyEvent {
  final String familyId;
  FamilyInviteLinkRequested(this.familyId);
}

/// Accept an incoming invite.
class FamilyInviteAccepted extends FamilyEvent {
  final String inviteId;
  FamilyInviteAccepted(this.inviteId);
}

/// Change a member's role (admin/parent only).
class MemberRoleChangeRequested extends FamilyEvent {
  final String familyId;
  final String userId;
  final String newRole;
  MemberRoleChangeRequested(this.familyId, this.userId, this.newRole);
}

// ── States ────────────────────────────────────────────────────

abstract class FamilyState {}

class FamilyInitial extends FamilyState {}

class FamilyLoading extends FamilyState {}

class FamilyLoaded extends FamilyState {
  final Family family;
  FamilyLoaded(this.family);
}

class FamilyNotFound extends FamilyState {}

/// Emitted when the invite link is ready to share.
class FamilyInviteReady extends FamilyState {
  final Family family;
  final FamilyInvite invite;
  FamilyInviteReady(this.family, this.invite);
}

class FamilyJoined extends FamilyState {
  final Family family;
  FamilyJoined(this.family);
}

class FamilyError extends FamilyState {
  final String message;
  FamilyError(this.message);
}

// ── Bloc ──────────────────────────────────────────────────────

@injectable
class FamilyBloc extends Bloc<FamilyEvent, FamilyState> {
  final IFamilyRepository _repo;

  FamilyBloc(this._repo) : super(FamilyInitial()) {
    on<FamilyStarted>(_onStarted);
    on<FamilyCreateRequested>(_onCreateRequested);
    on<FamilyInviteLinkRequested>(_onInviteLinkRequested);
    on<FamilyInviteAccepted>(_onInviteAccepted);
    on<MemberRoleChangeRequested>(_onRoleChangeRequested);
  }

  Future<void> _onStarted(
    FamilyStarted event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    try {
      final family = await _repo.getMyFamily();
      if (family == null) {
        emit(FamilyNotFound());
      } else {
        emit(FamilyLoaded(family));
      }
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onCreateRequested(
    FamilyCreateRequested event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    try {
      final family = await _repo.createFamily(event.name);
      // Reload with members
      final loaded = await _repo.getMyFamily();
      emit(FamilyLoaded(loaded ?? family));
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onInviteLinkRequested(
    FamilyInviteLinkRequested event,
    Emitter<FamilyState> emit,
  ) async {
    final currentFamily = state is FamilyLoaded
        ? (state as FamilyLoaded).family
        : null;
    if (currentFamily == null) return;

    try {
      final invite = await _repo.createInviteLink(event.familyId);
      emit(FamilyInviteReady(currentFamily, invite));
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onInviteAccepted(
    FamilyInviteAccepted event,
    Emitter<FamilyState> emit,
  ) async {
    emit(FamilyLoading());
    try {
      await _repo.acceptInvite(event.inviteId);
      final family = await _repo.getMyFamily();
      if (family != null) {
        emit(FamilyJoined(family));
      } else {
        emit(FamilyError('가족 그룹을 불러오는 데 실패했습니다.'));
      }
    } catch (e) {
      emit(FamilyError(e.toString()));
    }
  }

  Future<void> _onRoleChangeRequested(
    MemberRoleChangeRequested event,
    Emitter<FamilyState> emit,
  ) async {
    try {
      await _repo.updateMemberRole(
        familyId: event.familyId,
        userId: event.userId,
        newRole: event.newRole,
      );
      // Reload to reflect the change
      final family = await _repo.getMyFamily();
      if (family != null) {
        emit(FamilyLoaded(family));
      }
    } catch (e) {
      emit(FamilyError('역할 변경 실패: ${e.toString()}'));
    }
  }
}
