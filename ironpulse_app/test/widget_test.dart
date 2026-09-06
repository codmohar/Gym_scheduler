import 'package:flutter_test/flutter_test.dart';
import 'package:ironpulse_app/models.dart';
import 'dart:convert';

void main() {
  group('Routine and Persistence Tests', () {
    test('Preset routines load correctly with default values', () {
      final presets = PresetRoutines.getAllPresets();
      expect(presets.isNotEmpty, true);
      expect(presets.first.days.length, 7);
      expect(presets.first.days.first.day, 'MON');
    });

    test('RoutineSplit serializes and deserializes with user edits', () {
      final presets = PresetRoutines.getAllPresets();
      final split = presets.first;

      // Simulate user editing: toggle rest, add exercise, add custom config
      final monday = split.days[0];
      monday.isRest = true;
      monday.exerciseIds.add('custom_ex_123');
      monday.exerciseConfigs['custom_ex_123'] = {
        'target_reps': '4 Sets × 12 Reps',
        'target_rpe': '9.0',
        'rest_seconds': 120,
        'notes': 'Heavy progressive overload',
        'sets': [
          {'set_number': 1, 'weight': 80.0, 'reps': 12, 'completed': true},
          {'set_number': 2, 'weight': 85.0, 'reps': 10, 'completed': false},
        ],
      };

      // Serialize to JSON (simulating SharedPreferences storage)
      final jsonString = json.encode(split.toMap());

      // Deserialize from JSON (simulating app reopen)
      final decodedMap = json.decode(jsonString);
      final restoredSplit = RoutineSplit.fromMap(Map<String, dynamic>.from(decodedMap));

      expect(restoredSplit.id, split.id);
      expect(restoredSplit.days.length, 7);

      final restoredMonday = restoredSplit.days[0];
      expect(restoredMonday.isRest, true);
      expect(restoredMonday.exerciseIds.contains('custom_ex_123'), true);
      expect(restoredMonday.exerciseConfigs.containsKey('custom_ex_123'), true);

      final config = restoredMonday.exerciseConfigs['custom_ex_123']!;
      expect(config['target_reps'], '4 Sets × 12 Reps');
      expect(config['target_rpe'], '9.0');
      expect(config['rest_seconds'], 120);
      expect(config['notes'], 'Heavy progressive overload');

      final setsList = config['sets'] as List;
      expect(setsList.length, 2);
      expect(setsList[0]['weight'], 80.0);
      expect(setsList[0]['completed'], true);
    });

    test('ScheduledExercise applies and exports configs correctly', () {
      final scheduled = ScheduledExercise(
        exerciseId: 'test_ex',
        name: 'Test Exercise',
        muscleGroup: 'Chest',
        modality: 'Free Weights',
        sets: [
          WorkoutSet(setNumber: 1, weight: 60.0, reps: 10),
          WorkoutSet(setNumber: 2, weight: 65.0, reps: 8),
        ],
      );

      final config = scheduled.toConfigMap();
      expect(config['target_reps'], '3 Sets × 8-10 Reps');

      scheduled.applyConfig({
        'target_reps': '5 Sets × 5 Reps',
        'target_rpe': '9.5',
        'rest_seconds': 180,
        'notes': 'Strength block',
        'sets': [
          {'set_number': 1, 'weight': 100.0, 'reps': 5, 'completed': true},
        ],
      });

      expect(scheduled.targetReps, '5 Sets × 5 Reps');
      expect(scheduled.targetRpe, '9.5');
      expect(scheduled.restSeconds, 180);
      expect(scheduled.notes, 'Strength block');
      expect(scheduled.sets.length, 1);
      expect(scheduled.sets.first.weight, 100.0);
      expect(scheduled.sets.first.reps, 5);
      expect(scheduled.sets.first.completed, true);
    });
  });
}
