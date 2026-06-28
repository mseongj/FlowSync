import 'package:injectable/injectable.dart';

@lazySingleton
class LocalDatabaseService {
  Future<void> initialize() async {
    // Hive or SQLite init logic here
  }
}
