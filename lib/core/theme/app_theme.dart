import 'package:flutter/material.dart';
import 'privacy_theme_extension.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        PrivacyThemeExtension(
          publicEventColor: Colors.blue,
          privateEventColor: Colors.orange,
          secretEventColor: Colors.red,
        ),
      ],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        PrivacyThemeExtension(
          publicEventColor: Colors.lightBlue,
          privateEventColor: Colors.orangeAccent,
          secretEventColor: Colors.redAccent,
        ),
      ],
    );
  }
}
