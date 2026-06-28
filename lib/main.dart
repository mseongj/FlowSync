import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/schedule_provider.dart';
import 'services/gemini_service.dart';

void main() {
  // TODO: Replace with actual API Key or use environment variables
  const String geminiApiKey = 'YOUR_GEMINI_API_KEY';
  
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => GeminiService(geminiApiKey)),
        ChangeNotifierProxyProvider<GeminiService, ScheduleProvider>(
          create: (context) => ScheduleProvider(context.read<GeminiService>()),
          update: (context, geminiService, previous) =>
              previous ?? ScheduleProvider(geminiService),
        ),
      ],
      child: FlowSyncApp(),
    ),
  );
}

class FlowSyncApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowSync',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
