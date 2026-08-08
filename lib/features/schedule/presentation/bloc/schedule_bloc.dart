import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flow_sync/core/background/sync_queue_manager.dart';
import 'package:flow_sync/core/database/local_database_service.dart';
import 'package:flow_sync/features/schedule/data/datasources/event_remote_data_source.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';

part 'schedule_event.dart';
part 'schedule_state.dart';

@injectable
class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  final LocalDatabaseService _localDb;
  final OfflineSyncQueueManager _syncManager;
  final EventRemoteDataSource _remoteSource;
  StreamSubscription<BoxEvent>? _dbSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _realtimeChannel;

  ScheduleBloc(this._localDb, this._syncManager, this._remoteSource)
      : super(ScheduleLoading()) {
    on<ScheduleStarted>(_onStarted);
    on<ScheduleDateSelected>(_onDateSelected);
    on<ScheduleEventsUpdated>(_onEventsUpdated);
    on<ScheduleEventSaved>(_onEventSaved);
    on<ScheduleEventDeleted>(_onEventDeleted);
    on<ScheduleConnectivityChanged>(_onConnectivityChanged);
    on<FamilyGroupSet>(_onFamilyGroupSet);

    // Watch Hive for local DB changes
    _dbSubscription = _localDb.watchEvents().listen((_) {
      add(ScheduleEventsUpdated());
    });

    // Watch connectivity — trigger sync when reconnected
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      add(ScheduleConnectivityChanged(isOnline: isOnline));
    });
  }

  Future<void> _onStarted(ScheduleStarted event, Emitter<ScheduleState> emit) async {
    final now = DateTime.now();
    emit(ScheduleLoading());

    final allEvents = await _localDb.getAllEvents();
    final todayEvents = await _localDb.getEventsForDay(now);

    emit(ScheduleLoaded(
      selectedDate: now,
      selectedDateEvents: todayEvents,
      allEvents: allEvents,
    ));
  }

  Future<void> _onDateSelected(
    ScheduleDateSelected event,
    Emitter<ScheduleState> emit,
  ) async {
    if (state is! ScheduleLoaded) return;
    final currentState = state as ScheduleLoaded;

    final eventsForDate = await _localDb.getEventsForDay(event.date);
    emit(currentState.copyWith(
      selectedDate: event.date,
      selectedDateEvents: eventsForDate,
    ));
  }

  Future<void> _onEventsUpdated(
    ScheduleEventsUpdated event,
    Emitter<ScheduleState> emit,
  ) async {
    if (state is! ScheduleLoaded) return;
    final currentState = state as ScheduleLoaded;
    final allEvents = await _localDb.getAllEvents();
    final eventsForDate =
        await _localDb.getEventsForDay(currentState.selectedDate);

    emit(currentState.copyWith(
      allEvents: allEvents,
      selectedDateEvents: eventsForDate,
    ));
  }

  Future<void> _onEventSaved(
    ScheduleEventSaved event,
    Emitter<ScheduleState> emit,
  ) async {
    await _localDb.saveEvent(event.event);

    // If created offline, enqueue a one-off background sync task.
    if (event.event.isOfflineCreated) {
      await _syncManager.enqueueSyncTask(event.event.id);
    }

    add(ScheduleEventsUpdated());
  }

  Future<void> _onEventDeleted(
    ScheduleEventDeleted event,
    Emitter<ScheduleState> emit,
  ) async {
    await _localDb.deleteEvent(event.eventId);
    add(ScheduleEventsUpdated());
  }

  Future<void> _onConnectivityChanged(
    ScheduleConnectivityChanged event,
    Emitter<ScheduleState> emit,
  ) async {
    if (!event.isOnline) return;

    // Back online — queue sync for every pending offline event
    final pendingEvents = (await _localDb.getAllEvents())
        .where((e) => e.isOfflineCreated)
        .toList();

    for (final e in pendingEvents) {
      await _syncManager.enqueueSyncTask(e.id);
    }
  }

  /// Called when FamilyBloc determines the user belongs to a family.
  /// Fetches the last 30 days + next 60 days of family events from Supabase,
  /// merges them into the local Hive cache, and starts a Realtime subscription.
  Future<void> _onFamilyGroupSet(
    FamilyGroupSet event,
    Emitter<ScheduleState> emit,
  ) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final to = now.add(const Duration(days: 60));

      final remoteEvents = await _remoteSource.fetchFamilyEvents(
        familyId: event.familyId,
        from: from,
        to: to,
      );

      // Merge remote events into local Hive — only non-own events
      for (final e in remoteEvents) {
        if (e.creatorId != event.currentUserId) {
          await _localDb.saveEvent(e);
        }
      }

      // Start Realtime subscription for live updates
      _realtimeChannel?.unsubscribe();
      _realtimeChannel = _remoteSource.subscribeToFamilyEvents(
        familyId: event.familyId,
        onEvent: (change) => _handleRealtimeChange(change, event.currentUserId),
      );

      // Update state to reflect family mode
      if (state is ScheduleLoaded) {
        final current = state as ScheduleLoaded;
        final allEvents = await _localDb.getAllEvents();
        final eventsForDate =
            await _localDb.getEventsForDay(current.selectedDate);

        emit(current.copyWith(
          allEvents: allEvents,
          selectedDateEvents: eventsForDate,
          familyId: event.familyId,
        ));
      }
    } catch (_) {
      // Silently ignore network errors — local events still show
    }
  }

  /// Handles a real-time INSERT/UPDATE/DELETE from Supabase.
  void _handleRealtimeChange(RealtimeEventChange change, String currentUserId) {
    switch (change.type) {
      case 'INSERT':
      case 'UPDATE':
        final evt = change.event;
        if (evt != null && evt.creatorId != currentUserId) {
          _localDb.saveEvent(evt).then((_) {
            add(ScheduleEventsUpdated());
          });
        }
        break;
      case 'DELETE':
        final id = change.deletedId;
        if (id != null) {
          _localDb.deleteEvent(id).then((_) {
            add(ScheduleEventsUpdated());
          });
        }
        break;
    }
  }

  @override
  Future<void> close() {
    _dbSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _realtimeChannel?.unsubscribe();
    return super.close();
  }
}
