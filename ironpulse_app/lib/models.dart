class Exercise {
  final String id;
  final String name;
  final String muscleGroup;
  final List<String> secondaryMuscles;
  final String modality;
  final String tier;
  final String mechanic;
  final String equipment;
  final bool isCustom;
  final bool isFavorite;

  Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    this.secondaryMuscles = const [],
    required this.modality,
    required this.tier,
    required this.mechanic,
    required this.equipment,
    this.isCustom = false,
    this.isFavorite = false,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      muscleGroup: json['muscle_group']?.toString() ?? 'Full Body',
      secondaryMuscles: (json['secondary_muscles'] is List)
          ? List<String>.from(json['secondary_muscles'].map((e) => e.toString()))
          : [],
      modality: json['modality']?.toString() ?? 'Free Weights',
      tier: json['tier']?.toString() ?? 'Intermediate',
      mechanic: json['mechanic']?.toString() ?? 'Compound',
      equipment: json['equipment']?.toString() ?? 'Barbell',
      isCustom: json['is_custom'] == 1 || json['is_custom'] == true,
      isFavorite: json['is_favorite'] == 1 || json['is_favorite'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'muscle_group': muscleGroup,
      'secondary_muscles': secondaryMuscles.join(','),
      'modality': modality,
      'tier': tier,
      'mechanic': mechanic,
      'equipment': equipment,
      'is_custom': isCustom ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      muscleGroup: map['muscle_group']?.toString() ?? 'Full Body',
      secondaryMuscles: (map['secondary_muscles'] != null && map['secondary_muscles'].toString().isNotEmpty)
          ? map['secondary_muscles'].toString().split(',')
          : [],
      modality: map['modality']?.toString() ?? 'Free Weights',
      tier: map['tier']?.toString() ?? 'Intermediate',
      mechanic: map['mechanic']?.toString() ?? 'Compound',
      equipment: map['equipment']?.toString() ?? 'Barbell',
      isCustom: map['is_custom'] == 1,
      isFavorite: map['is_favorite'] == 1,
    );
  }
}

class WorkoutSet {
  int setNumber;
  double weight;
  int reps;
  bool completed;
  double? prevWeight;
  int? prevReps;

  WorkoutSet({
    required this.setNumber,
    this.weight = 0.0,
    this.reps = 0,
    this.completed = false,
    this.prevWeight,
    this.prevReps,
  });

  Map<String, dynamic> toMap(int? sessionId, String exerciseId, String unit) {
    return {
      'session_id': sessionId,
      'exercise_id': exerciseId,
      'set_number': setNumber,
      'weight': weight,
      'reps': reps,
      'unit': unit,
      'completed': completed ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> toDraftMap() {
    return {
      'set_number': setNumber,
      'weight': weight,
      'reps': reps,
      'completed': completed,
      'prev_weight': prevWeight,
      'prev_reps': prevReps,
    };
  }

  factory WorkoutSet.fromDraftMap(Map<String, dynamic> map) {
    return WorkoutSet(
      setNumber: (map['set_number'] as num?)?.toInt() ?? 1,
      weight: (map['weight'] as num?)?.toDouble() ?? 0.0,
      reps: (map['reps'] as num?)?.toInt() ?? 0,
      completed: map['completed'] == true || map['completed'] == 1,
      prevWeight: (map['prev_weight'] as num?)?.toDouble(),
      prevReps: (map['prev_reps'] as num?)?.toInt(),
    );
  }
}

class ScheduledExercise {
  final String exerciseId;
  final String name;
  final String muscleGroup;
  final String modality;
  String targetReps;
  String targetRpe;
  int restSeconds;
  String notes;
  bool hasHistory;
  double prevWeight;
  int prevReps;
  List<WorkoutSet> sets;

  ScheduledExercise({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.modality,
    this.targetReps = '3 Sets × 8-10 Reps',
    this.targetRpe = '8.0',
    this.restSeconds = 90,
    this.notes = '',
    this.hasHistory = false,
    this.prevWeight = 0.0,
    this.prevReps = 0,
    required this.sets,
  });

  Map<String, dynamic> toConfigMap() {
    return {
      'target_reps': targetReps,
      'target_rpe': targetRpe,
      'rest_seconds': restSeconds,
      'notes': notes,
      'sets': sets.map((s) => s.toDraftMap()).toList(),
    };
  }

  void applyConfig(Map<String, dynamic> config) {
    if (config.containsKey('target_reps')) {
      targetReps = config['target_reps'] as String? ?? targetReps;
    }
    if (config.containsKey('target_rpe')) {
      targetRpe = config['target_rpe'] as String? ?? targetRpe;
    }
    if (config.containsKey('rest_seconds')) {
      restSeconds = (config['rest_seconds'] as num?)?.toInt() ?? restSeconds;
    }
    if (config.containsKey('notes')) {
      notes = config['notes'] as String? ?? notes;
    }
    if (config.containsKey('sets') && config['sets'] is List) {
      final List setsList = config['sets'];
      if (setsList.isNotEmpty) {
        sets = setsList.map((s) => WorkoutSet.fromDraftMap(Map<String, dynamic>.from(s as Map))).toList();
      }
    }
  }
}

class RoutineDay {
  String day; // MON, TUE...
  String name;
  bool isRest;
  String focus;
  List<String> exerciseIds;
  Map<String, Map<String, dynamic>> exerciseConfigs;

  RoutineDay({
    required this.day,
    required this.name,
    required this.isRest,
    required this.focus,
    required this.exerciseIds,
    Map<String, Map<String, dynamic>>? exerciseConfigs,
  }) : exerciseConfigs = exerciseConfigs ?? {};

  factory RoutineDay.fromMap(Map<String, dynamic> map) {
    final rawConfigs = map['exerciseConfigs'] ?? map['exercise_configs'];
    Map<String, Map<String, dynamic>> configs = {};
    if (rawConfigs is Map) {
      rawConfigs.forEach((k, v) {
        if (v is Map) {
          configs[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }

    List<String> exIds = [];
    final rawIds = map['exerciseIds'] ?? map['exercise_ids'];
    if (rawIds is List) {
      exIds = rawIds.map((e) => e.toString()).toList();
    } else if (rawIds != null) {
      exIds = rawIds.toString().split(',').where((s) => s.isNotEmpty).toList();
    }

    return RoutineDay(
      day: map['day'] ?? 'MON',
      name: map['name'] ?? 'Workout',
      isRest: map['isRest'] == true || map['is_rest'] == true || map['is_rest'] == 1,
      focus: map['focus'] ?? '',
      exerciseIds: exIds,
      exerciseConfigs: configs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      'name': name,
      'isRest': isRest,
      'focus': focus,
      'exerciseIds': exerciseIds,
      'exerciseConfigs': exerciseConfigs,
    };
  }
}

class RoutineSplit {
  final String id;
  String name;
  String type;
  List<RoutineDay> days;

  RoutineSplit({
    required this.id,
    required this.name,
    required this.type,
    required this.days,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'days': days.map((d) => d.toMap()).toList(),
    };
  }

  factory RoutineSplit.fromMap(Map<String, dynamic> map) {
    final daysList = (map['days'] as List? ?? [])
        .map((d) => RoutineDay.fromMap(Map<String, dynamic>.from(d as Map)))
        .toList();

    return RoutineSplit(
      id: map['id'] ?? 'custom',
      name: map['name'] ?? 'Custom Routine',
      type: map['type'] ?? 'CUSTOM',
      days: daysList,
    );
  }
}

class PresetRoutines {
  static List<RoutineSplit> getAllPresets() {
    return [
      RoutineSplit(
        id: 'ppl',
        name: 'Push / Pull / Legs',
        type: 'PPL',
        days: [
          RoutineDay(
            day: 'MON',
            name: 'Push Power & Chest',
            isRest: false,
            focus: 'Chest, Delts, Triceps',
            exerciseIds: [
              'chest_flat_bb_bench_press',
              'chest_incline_db_bench_press',
              'sh_standing_bb_ohp',
              'arm_cable_rope_pushdown',
              'sh_db_lateral_raise'
            ],
          ),
          RoutineDay(
            day: 'TUE',
            name: 'Pull & Posterior Chain',
            isRest: false,
            focus: 'Back, Biceps, Rear Delts',
            exerciseIds: [
              'back_standard_pull_up',
              'back_bb_bent_over_row',
              'back_seated_cable_row',
              'sh_face_pulls',
              'arm_bb_curl'
            ],
          ),
          RoutineDay(
            day: 'WED',
            name: 'Scheduled Rest & Recovery',
            isRest: true,
            focus: 'Full Rest & Mobility',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'THU',
            name: 'Legs & Core Agility',
            isRest: false,
            focus: 'Quads, Hamstrings, Calves',
            exerciseIds: [
              'leg_bb_back_squat',
              'leg_rdl_bb_db_kb',
              'leg_bulgarian_split_squat',
              'leg_curl_machine',
              'leg_calf_raises',
              'core_hanging_knee_raise'
            ],
          ),
          RoutineDay(
            day: 'FRI',
            name: 'Upper Hypertrophy',
            isRest: false,
            focus: 'Chest, Back, Arms',
            exerciseIds: [
              'chest_incline_bb_bench_press',
              'chest_dips',
              'back_lat_pulldown',
              'sh_seated_arnold_press',
              'arm_diamond_push_up'
            ],
          ),
          RoutineDay(
            day: 'SAT',
            name: 'Mobility & Active Recovery',
            isRest: true,
            focus: 'Light Cardio & Stretching',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'SUN',
            name: 'Rest & Recovery',
            isRest: true,
            focus: 'Full Recovery',
            exerciseIds: [],
          ),
        ],
      ),
      RoutineSplit(
        id: 'upper_lower',
        name: 'Upper / Lower (4-Day)',
        type: 'UPPER_LOWER',
        days: [
          RoutineDay(
            day: 'MON',
            name: 'Upper Power',
            isRest: false,
            focus: 'Chest, Back, Arms',
            exerciseIds: [
              'chest_flat_bb_bench_press',
              'back_bb_bent_over_row',
              'sh_standing_bb_ohp',
              'arm_bb_curl'
            ],
          ),
          RoutineDay(
            day: 'TUE',
            name: 'Lower Power',
            isRest: false,
            focus: 'Quads, Hamstrings, Core',
            exerciseIds: [
              'leg_bb_back_squat',
              'leg_rdl_bb_db_kb',
              'leg_calf_raises',
              'core_forearm_plank'
            ],
          ),
          RoutineDay(
            day: 'WED',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest & Recovery',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'THU',
            name: 'Upper Hypertrophy',
            isRest: false,
            focus: 'Chest, Lats, Delts',
            exerciseIds: [
              'chest_incline_db_bench_press',
              'back_lat_pulldown',
              'sh_db_lateral_raise',
              'arm_cable_rope_pushdown'
            ],
          ),
          RoutineDay(
            day: 'FRI',
            name: 'Lower Hypertrophy',
            isRest: false,
            focus: 'Legs & Core',
            exerciseIds: [
              'leg_bulgarian_split_squat',
              'leg_glute_bridge_hip_thrust',
              'leg_extension_machine',
              'core_hanging_knee_raise'
            ],
          ),
          RoutineDay(
            day: 'SAT',
            name: 'Active Recovery',
            isRest: true,
            focus: 'Mobility & Walking',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'SUN',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest & Recovery',
            exerciseIds: [],
          ),
        ],
      ),
      RoutineSplit(
        id: 'full_body',
        name: 'Full Body (3-Day)',
        type: 'FULL_BODY',
        days: [
          RoutineDay(
            day: 'MON',
            name: 'Full Body A',
            isRest: false,
            focus: 'Compound Strength',
            exerciseIds: [
              'chest_flat_bb_bench_press',
              'leg_bb_back_squat',
              'back_bb_bent_over_row',
              'sh_standing_bb_ohp'
            ],
          ),
          RoutineDay(
            day: 'TUE',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'WED',
            name: 'Full Body B',
            isRest: false,
            focus: 'Hypertrophy Focus',
            exerciseIds: [
              'chest_incline_db_bench_press',
              'leg_rdl_bb_db_kb',
              'back_standard_pull_up',
              'arm_bb_curl'
            ],
          ),
          RoutineDay(
            day: 'THU',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'FRI',
            name: 'Full Body C',
            isRest: false,
            focus: 'Volume & Core',
            exerciseIds: [
              'leg_goblet_squat',
              'chest_dips',
              'back_lat_pulldown',
              'core_hanging_knee_raise'
            ],
          ),
          RoutineDay(
            day: 'SAT',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'SUN',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
        ],
      ),
      RoutineSplit(
        id: 'bro_split',
        name: 'Bro Split (5-Day)',
        type: 'BRO_SPLIT',
        days: [
          RoutineDay(
            day: 'MON',
            name: 'Chest Day',
            isRest: false,
            focus: 'Chest Focus',
            exerciseIds: [
              'chest_flat_bb_bench_press',
              'chest_incline_db_bench_press',
              'chest_dips',
              'chest_cable_pec_fly_high_low'
            ],
          ),
          RoutineDay(
            day: 'TUE',
            name: 'Back Day',
            isRest: false,
            focus: 'Back & Lats',
            exerciseIds: [
              'back_standard_pull_up',
              'back_bb_bent_over_row',
              'back_lat_pulldown',
              'back_seated_cable_row'
            ],
          ),
          RoutineDay(
            day: 'WED',
            name: 'Shoulders Day',
            isRest: false,
            focus: 'Delts & Traps',
            exerciseIds: [
              'sh_standing_bb_ohp',
              'sh_db_lateral_raise',
              'sh_seated_arnold_press',
              'sh_face_pulls'
            ],
          ),
          RoutineDay(
            day: 'THU',
            name: 'Legs Day',
            isRest: false,
            focus: 'Quads & Calves',
            exerciseIds: [
              'leg_bb_back_squat',
              'leg_rdl_bb_db_kb',
              'leg_extension_machine',
              'leg_calf_raises'
            ],
          ),
          RoutineDay(
            day: 'FRI',
            name: 'Arms & Core',
            isRest: false,
            focus: 'Biceps, Triceps, Abs',
            exerciseIds: [
              'arm_bb_curl',
              'arm_cable_rope_pushdown',
              'arm_hammer_curl',
              'core_ab_wheel_rollout'
            ],
          ),
          RoutineDay(
            day: 'SAT',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
          RoutineDay(
            day: 'SUN',
            name: 'Rest Day',
            isRest: true,
            focus: 'Rest',
            exerciseIds: [],
          ),
        ],
      ),
    ];
  }
}

class WorkoutSession {
  final int? id;
  final String title;
  final String date;
  final int durationSeconds;
  final double totalVolume;
  final String unit;
  final String notes;

  WorkoutSession({
    this.id,
    required this.title,
    required this.date,
    required this.durationSeconds,
    required this.totalVolume,
    required this.unit,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'date': date,
      'duration_seconds': durationSeconds,
      'total_volume': totalVolume,
      'unit': unit,
      'notes': notes,
    };
  }

  factory WorkoutSession.fromMap(Map<String, dynamic> map) {
    return WorkoutSession(
      id: map['id'],
      title: map['title'] ?? 'Session',
      date: map['date'] ?? DateTime.now().toIso8601String(),
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      totalVolume: (map['total_volume'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? 'kg',
      notes: map['notes'] ?? '',
    );
  }
}
