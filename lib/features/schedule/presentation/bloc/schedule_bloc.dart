import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/database/local_database_service.dart';
import '../../domain/entities/calendar_event.dart';

part 'schedule_event.dart';
part 'schedule_state.dart';

@injectable
class ScheduleBloc extends Bloc<ScheduleEvent, ScheduleState> {
  final LocalDatabaseService _localDb;
  StreamSubscription<BoxEvent>? _dbSubscription;

  ScheduleBloc(this._localDb) : super(ScheduleLoading()) {
    on<ScheduleStarted>(_onStarted);
    on<ScheduleDateSelected>(_onDateSelected);
    on<ScheduleEventsUpdated>(_onEventsUpdated);

    // Watch for DB changes
    _dbSubscription = _localDb.watchEvents().listen((_) {
      add(ScheduleEventsUpdated());
    });
  }

  void _onStarted(ScheduleStarted event, Emitter<ScheduleState> emit) {
    final now = DateTime.now();
    final allEvents = _localDb.getAllEvents();
    final todayEvents = _localDb.getEventsForDay(now);

    emit(ScheduleLoaded(
      selectedDate: now,
      selectedDateEvents: todayEvents,
      allEvents: allEvents,
    ));
  }

  void _onDateSelected(ScheduleDateSelected event, Emitter<ScheduleState> emit) {
    if (state is ScheduleLoaded) {
      final currentState = state as ScheduleLoaded;
      final eventsForDate = _localDb.getEventsForDay(event.date);

      emit(currentState.copyWith(
        selectedDate: event.date,
        selectedDateEvents: eventsForDate,
      ));
    }
  }

  void _onEventsUpdated(ScheduleEventsUpdated event, Emitter<ScheduleState> emit) {
    if (state is ScheduleLoaded) {
      final currentState = state as ScheduleLoaded;
      final allEvents = _localDb.getAllEvents();
      final eventsForDate = _localDb.getEventsForDay(currentState.selectedDate);

      emit(currentState.copyWith(
        allEvents: allEvents,
        selectedDateEvents: eventsForDate,
      ));
    }
  }

  @override
  Future<void> close() {
    _dbSubscription?.cancel();
    return super.close();
  }
}
