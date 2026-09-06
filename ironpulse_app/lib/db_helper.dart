import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  // In-memory / SharedPreferences state for Web
  List<Exercise>? _webExercises;
  final List<WorkoutSession> _webSessions = [];
  final List<Map<String, dynamic>> _webSets = [];
  final Map<String, Map<String, dynamic>> _webHistory = {};

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ironpulse.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        muscle_group TEXT NOT NULL,
        secondary_muscles TEXT,
        modality TEXT NOT NULL,
        tier TEXT,
        mechanic TEXT,
        equipment TEXT,
        is_custom INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        duration_seconds INTEGER DEFAULT 0,
        total_volume REAL DEFAULT 0,
        unit TEXT DEFAULT 'kg',
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        exercise_id TEXT NOT NULL,
        set_number INTEGER NOT NULL,
        weight REAL NOT NULL,
        reps INTEGER NOT NULL,
        unit TEXT DEFAULT 'kg',
        completed INTEGER DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE exercise_history (
        exercise_id TEXT PRIMARY KEY,
        last_weight REAL NOT NULL,
        last_reps INTEGER NOT NULL,
        last_sets_count INTEGER DEFAULT 3,
        best_weight REAL DEFAULT 0,
        best_reps INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Seed 168 catalog movements
    await _seedExercises(db);
  }

  Future<void> _seedExercises(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/exercises.json');
      final List<dynamic> list = json.decode(jsonString);
      final batch = db.batch();
      for (final item in list) {
        final ex = Exercise.fromJson(item);
        batch.insert('exercises', ex.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // Asset loading error fallback
    }
  }

  Future<List<Exercise>> getAllExercises() async {
    if (kIsWeb) {
      if (_webExercises == null) {
        try {
          final jsonString = await rootBundle.loadString('assets/data/exercises.json');
          final List<dynamic> list = json.decode(jsonString);
          _webExercises = list.map((item) => Exercise.fromJson(item)).toList();
        } catch (e) {
          _webExercises = [];
        }
      }
      return List<Exercise>.from(_webExercises!);
    }

    final db = await database;
    final result = await db.query('exercises', orderBy: 'name ASC');
    return result.map((e) => Exercise.fromMap(e)).toList();
  }

  Future<Exercise> addCustomExercise(String name, String muscleGroup, String modality) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final ex = Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      modality: modality,
      tier: 'Intermediate',
      mechanic: 'Compound',
      equipment: 'Custom',
      isCustom: true,
    );

    if (kIsWeb) {
      _webExercises ??= [];
      _webExercises!.insert(0, ex);
      return ex;
    }

    final db = await database;
    await db.insert('exercises', ex.toMap());
    return ex;
  }

  Future<Map<String, dynamic>> getPreviousPerformance(String exerciseId) async {
    if (kIsWeb) {
      if (_webHistory.containsKey(exerciseId)) {
        return _webHistory[exerciseId]!;
      }
      return {
        'hasHistory': false,
        'last_weight': 0.0,
        'last_reps': 0,
        'best_weight': 0.0,
        'best_reps': 0,
      };
    }

    final db = await database;
    final history = await db.query(
      'exercise_history',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
    );

    if (history.isNotEmpty) {
      final row = history.first;
      return {
        'hasHistory': true,
        'last_weight': (row['last_weight'] as num).toDouble(),
        'last_reps': row['last_reps'] as int,
        'best_weight': (row['best_weight'] as num?)?.toDouble() ?? 0.0,
        'best_reps': (row['best_reps'] as int?) ?? 0,
      };
    }

    return {
      'hasHistory': false,
      'last_weight': 0.0,
      'last_reps': 0,
      'best_weight': 0.0,
      'best_reps': 0,
    };
  }

  Future<void> updateExercisePerformance(String exerciseId, double weight, int reps, [int setsCount = 3]) async {
    if (kIsWeb) {
      final prev = _webHistory[exerciseId];
      double bestW = weight;
      int bestR = reps;
      if (prev != null) {
        final prevBestW = (prev['best_weight'] as num?)?.toDouble() ?? 0.0;
        final prevBestR = (prev['best_reps'] as int?) ?? 0;
        if (weight > prevBestW) {
          bestW = weight;
        } else {
          bestW = prevBestW;
        }
        if (weight == prevBestW && reps > prevBestR) {
          bestR = reps;
        } else {
          bestR = prevBestR;
        }
      }
      _webHistory[exerciseId] = {
        'hasHistory': true,
        'last_weight': weight,
        'last_reps': reps,
        'last_sets_count': setsCount,
        'best_weight': bestW,
        'best_reps': bestR,
      };
      return;
    }

    final db = await database;
    final existing = await db.query(
      'exercise_history',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
    );

    double bestW = weight;
    int bestR = reps;

    if (existing.isNotEmpty) {
      final prevBestW = (existing.first['best_weight'] as num?)?.toDouble() ?? 0.0;
      final prevBestR = (existing.first['best_reps'] as int?) ?? 0;
      if (weight > prevBestW) {
        bestW = weight;
      } else {
        bestW = prevBestW;
      }
      if (weight == prevBestW && reps > prevBestR) {
        bestR = reps;
      } else {
        bestR = prevBestR;
      }
    }

    await db.insert(
      'exercise_history',
      {
        'exercise_id': exerciseId,
        'last_weight': weight,
        'last_reps': reps,
        'last_sets_count': setsCount,
        'best_weight': bestW,
        'best_reps': bestR,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> finishWorkout(WorkoutSession session, List<Map<String, dynamic>> setsData) async {
    if (kIsWeb) {
      final sessionId = _webSessions.length + 1;
      _webSessions.insert(0, session);
      for (final s in setsData) {
        final sCopy = Map<String, dynamic>.from(s);
        sCopy['session_id'] = sessionId;
        _webSets.add(sCopy);
        final exId = sCopy['exercise_id'] as String;
        final w = (sCopy['weight'] as num).toDouble();
        final r = sCopy['reps'] as int;
        if (w > 0 || r > 0) {
          await updateExercisePerformance(exId, w, r);
        }
      }
      return sessionId;
    }

    final db = await database;
    final sessionId = await db.insert('sessions', session.toMap());

    final batch = db.batch();
    for (final s in setsData) {
      s['session_id'] = sessionId;
      batch.insert('sets', s);
    }
    await batch.commit(noResult: true);

    // Update history per exercise
    for (final s in setsData) {
      final exId = s['exercise_id'] as String;
      final w = (s['weight'] as num).toDouble();
      final r = s['reps'] as int;
      if (w > 0 || r > 0) {
        await updateExercisePerformance(exId, w, r);
      }
    }

    return sessionId;
  }

  Future<List<WorkoutSession>> getWorkoutHistory() async {
    if (kIsWeb) {
      return List<WorkoutSession>.from(_webSessions);
    }

    final db = await database;
    final result = await db.query('sessions', orderBy: 'id DESC');
    return result.map((e) => WorkoutSession.fromMap(e)).toList();
  }

  Future<void> deleteSession(int id) async {
    if (kIsWeb) {
      _webSessions.removeWhere((s) => s.id == id);
      _webSets.removeWhere((s) => s['session_id'] == id);
      return;
    }

    final db = await database;
    await db.delete('sets', where: 'session_id = ?', whereArgs: [id]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>> getTelemetryStats() async {
    if (kIsWeb) {
      double totalVolume = 0;
      for (final s in _webSessions) {
        totalVolume += s.totalVolume;
      }
      return {
        'total_sessions': _webSessions.length,
        'total_volume': totalVolume,
        'total_sets': _webSets.length,
      };
    }

    final db = await database;
    final sessions = await db.query('sessions');
    final sets = await db.query('sets');

    double totalVolume = 0;
    for (final s in sessions) {
      totalVolume += (s['total_volume'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'total_sessions': sessions.length,
      'total_volume': totalVolume,
      'total_sets': sets.length,
    };
  }
}
