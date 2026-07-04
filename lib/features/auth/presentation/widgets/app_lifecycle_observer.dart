import 'package:flutter/widgets.dart';
import 'package:flow_sync/features/auth/data/crypto/crypto_worker.dart';
import 'package:get_it/get_it.dart';

class AppLifecycleObserver extends StatefulWidget {
  final Widget child;

  const AppLifecycleObserver({super.key, required this.child});

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Aggressively wipe in-memory keys
      try {
        GetIt.I<CryptoWorkerManager>().wipeMemory();
        debugPrint('CryptoWorkerManager memory wiped successfully.');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
