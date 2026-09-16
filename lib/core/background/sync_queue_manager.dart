import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'package:flow_sync/core/config/env.dart';
import 'package:flow_sync/core/database/calendar_event_adapter.dart';
import 'package:flow_sync/features/schedule/domain/entities/calendar_event.dart';

const String periodicSyncTaskName = 'com.martincodes.flowsync.periodicSync';
const String oneOffSyncTaskName = 'com.martincodes.flowsync.oneOffSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 1. Isolate initialization
      // Note: Background isolates are separate from the main UI isolate.
      // We must re-initialize essential services here.
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Hive
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(EventVisibilityAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(CalendarEventAdapter());
      }

      final box = await Hive.openBox<CalendarEvent>('calendar_events');

      // Initialize Supabase
      // The session should be automatically restored by Supabase.
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
      final supabase = Supabase.instance.client;

      var allSuccess = true;

      if (task == periodicSyncTaskName) {
        debugPrint('Executing periodic background sync...');
        final pendingEvents = box.values
            .where((e) => e.isOfflineCreated)
            .toList();

        for (final event in pendingEvents) {
          try {
            final currentUser = supabase.auth.currentUser;
            final eventToSync = (currentUser != null &&
                    (event.creatorId.isEmpty || event.creatorId == 'user_1'))
                ? event.copyWith(creatorId: currentUser.id)
                : event;

            await supabase
                .from('calendar_events')
                .upsert(eventToSync.toSupabaseJson());
            // Update local state to prevent re-sync and mark as synced
            await box.put(event.id, eventToSync.copyWith(isOfflineCreated: false));
          } catch (e) {
            debugPrint('Failed to sync event ${event.id}: $e');
            allSuccess = false;
          }
        }
      } else if (task == oneOffSyncTaskName) {
        final eventId = inputData?['eventId'] as String?;
        debugPrint('Executing one-off background sync for event: $eventId');

        if (eventId != null) {
          final event = box.get(eventId);
          if (event != null && event.isOfflineCreated) {
            try {
              final currentUser = supabase.auth.currentUser;
              final eventToSync = (currentUser != null &&
                      (event.creatorId.isEmpty || event.creatorId == 'user_1'))
                  ? event.copyWith(creatorId: currentUser.id)
                  : event;

              await supabase
                  .from('calendar_events')
                  .upsert(eventToSync.toSupabaseJson());
              await box.put(event.id, eventToSync.copyWith(isOfflineCreated: false));
            } catch (e) {
              debugPrint('Failed to sync event $eventId: $e');
              allSuccess = false;
            }
          }
        }
      }

      return Future.value(allSuccess);
    } catch (e) {
      debugPrint('Background task failed: $e');
      // Returning false triggers the backoff policy (exponentially retrying).
      return Future.value(false);
    }
  });
}

@lazySingleton
class OfflineSyncQueueManager {
  Future<void> initialize() async {
    // NOTE: The `isInDebugMode` parameter was removed because it is deprecated
    // and has no effect in workmanager 0.9.x.
    await Workmanager().initialize(callbackDispatcher);

    // Register periodic task with exponential backoff.
    await Workmanager().registerPeriodicTask(
      'periodic_sync_1',
      periodicSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Attempts immediate in-app sync first to clear the pending badge instantly.
  /// Falls back to background Workmanager if offline or if network fails.
  Future<void> enqueueSyncTask(String eventId) async {
    final synced = await syncEventImmediately(eventId);
    if (synced) return;

    try {
      await Workmanager().registerOneOffTask(
        'sync_$eventId',
        oneOffSyncTaskName,
        inputData: {'eventId': eventId},
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e) {
      debugPrint('Failed to register Workmanager task: $e');
    }
  }

  /// Pushes [eventId] to Supabase immediately using the active foreground session.
  /// Updates local Hive state with `isOfflineCreated: false` upon success.
  Future<bool> syncEventImmediately(String eventId) async {
    try {
      if (!Hive.isBoxOpen('calendar_events')) return false;
      final box = Hive.box<CalendarEvent>('calendar_events');
      final event = box.get(eventId);
      if (event == null || !event.isOfflineCreated) {
        return true;
      }

      final client = Supabase.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        debugPrint('[SyncQueue] No active auth session; deferring event $eventId');
        return false;
      }

      // Ensure creatorId matches auth.uid() for Supabase RLS policy compliance
      final eventToSync = (event.creatorId.isEmpty || event.creatorId == 'user_1')
          ? event.copyWith(creatorId: currentUser.id)
          : event;

      await client
          .from('calendar_events')
          .upsert(eventToSync.toSupabaseJson());

      // Mark offline sync completed in local storage — triggers watchEvents()
      await box.put(event.id, eventToSync.copyWith(isOfflineCreated: false));
      debugPrint('⚡ [Immediate Sync] Event $eventId synced to Supabase. Pending badge cleared.');
      return true;
    } catch (e) {
      debugPrint('Immediate sync failed for $eventId (will use background worker): $e');
      return false;
    }
  }

  /// Synchronizes all pending offline events immediately in foreground.
  Future<void> syncAllPending() async {
    try {
      if (!Hive.isBoxOpen('calendar_events')) return;
      final box = Hive.box<CalendarEvent>('calendar_events');
      final pendingEvents = box.values
          .where((e) => e.isOfflineCreated)
          .toList();

      for (final event in pendingEvents) {
        await enqueueSyncTask(event.id);
      }
    } catch (e) {
      debugPrint('syncAllPending failed: $e');
    }
  }
}
