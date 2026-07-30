import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'theme_state.dart';

@injectable
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState(ThemeMode.system));

  /// Cycle through: system → light → dark → system
  void toggleTheme() {
    final next = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light  => ThemeMode.dark,
      ThemeMode.dark   => ThemeMode.system,
    };
    emit(ThemeState(next));
  }

  /// Set a specific theme mode.
  void setThemeMode(ThemeMode mode) => emit(ThemeState(mode));
}
