import 'package:injectable/injectable.dart';

@module
abstract class RegisterModule {
  // SupabaseClient is registered manually in main.dart after
  // Supabase.initialize() completes successfully.
  // Do NOT add a SupabaseClient getter here — it would crash
  // because configureDependencies() runs before Supabase.initialize().
}
