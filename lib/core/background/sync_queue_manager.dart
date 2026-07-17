import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

const String syncTaskName = "com.martincodes.flowsync.offlineSync";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == syncTaskName) {
      try {
        debugPrint("Executing background sync...");
        // 1. Check network connectivity
        // 2. Fetch pending mutations from local DB
        // 3. Attempt push to Supabase
        
        // Simulating success
        return Future.value(true);
      } catch (e) {
        debugPrint("Sync failed, triggering backoff...");
        // The exponential backoff is handled natively by Workmanager (BackoffPolicy.exponential)
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

class OfflineSyncQueueManager {
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    // Register periodic task with exponential backoff
    await Workmanager().registerPeriodicTask(
      "1",
      syncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5), // Base delay for exponential backoff
    );
  }

  Future<void> enqueueSyncTask(String eventId) async {
    await Workmanager().registerOneOffTask(
      "sync_$eventId",
      syncTaskName,
      inputData: {'eventId': eventId},
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }
}
