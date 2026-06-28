import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

part 'theme_state.dart';

@injectable
class ThemeCubit extends Cubit<ThemeState> {
  // Always use system theme as per NFR requirements
  ThemeCubit() : super(ThemeState(ThemeMode.system));
}
