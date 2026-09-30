import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

@module
abstract class RegisterModule {
  // SupabaseClient is registered manually in main.dart after
  // Supabase.initialize() completes successfully.
  // Do NOT add a SupabaseClient getter here — it would crash
  // because configureDependencies() runs before Supabase.initialize().

  @lazySingleton
  SupabaseClient get supabase => Supabase.instance.client;

  @lazySingleton
  FlutterSecureStorage get secureStorage => FlutterSecureStorage();
}
