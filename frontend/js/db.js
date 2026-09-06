/**
 * IronPulse Database Layer (Dexie.js / IndexedDB)
 * Clean, Zero-Latency Client-Side Storage Engine
 */

class IronPulseDatabase {
  constructor() {
    this.db = new Dexie('IronPulseDB');
    this.initSchema();
  }

  initSchema() {
    this.db.version(2).stores({
      exercises: 'id, name, muscle_group, modality, tier, equipment, is_custom, is_favorite',
      sessions: '++id, date, title, start_time, end_time, duration_seconds, total_volume, unit, status, notes',
      sets: '++id, session_id, exercise_id, set_number, weight, reps, unit, completed, created_at',
      exercise_history: 'exercise_id, last_weight, last_reps, last_sets_count, best_weight, best_reps, updated_at',
      active_workout: 'key',
      routines: 'id, name, type',
      settings: 'key'
    });
  }

  async init() {
    await this.db.open();
    await this.seedExercisesIfEmpty();
    await this.seedDefaultRoutinesIfEmpty();
  }

  /**
   * Seed and sync pre-verified exercises catalog on run
   */
  async seedExercisesIfEmpty() {
    if (window.INITIAL_EXERCISES && window.INITIAL_EXERCISES.length > 0) {
      const existing = await this.db.exercises.toArray();
      const existingMap = new Map(existing.map(e => [e.id, e]));
      const toPut = [];
      for (const e of window.INITIAL_EXERCISES) {
        if (!existingMap.has(e.id)) {
          toPut.push({
            ...e,
            is_custom: false,
            is_favorite: false
          });
        }
      }
      if (toPut.length > 0) {
        await this.db.exercises.bulkPut(toPut);
      }
    }
  }

  /**
   * Seed standard weekly routine splits with clean default structure
   */
  async seedDefaultRoutinesIfEmpty() {
    const count = await this.db.routines.count();
    if (count === 0) {
      const defaultRoutines = [
        {
          id: 'ppl',
          name: 'Push / Pull / Legs',
          type: 'PPL',
          days: [
            { day: 'MON', name: 'Push Power & Chest', is_rest: false, focus: 'Chest, Delts, Triceps', exercise_ids: ['chest_flat_bb_bench_press', 'chest_incline_db_bench_press', 'sh_standing_bb_ohp', 'arm_cable_rope_pushdown', 'sh_db_lateral_raise'] },
            { day: 'TUE', name: 'Pull & Posterior Chain', is_rest: false, focus: 'Back, Biceps, Rear Delts', exercise_ids: ['back_standard_pull_up', 'back_bb_bent_over_row', 'back_seated_cable_row', 'sh_face_pulls', 'arm_bb_curl'] },
            { day: 'WED', name: 'Scheduled Rest & Recovery', is_rest: true, focus: 'Full Rest & Mobility', exercise_ids: [] },
            { day: 'THU', name: 'Legs & Core Agility', is_rest: false, focus: 'Quads, Hamstrings, Calves', exercise_ids: ['leg_bb_back_squat', 'leg_rdl_bb_db_kb', 'leg_bulgarian_split_squat', 'leg_curl_machine', 'leg_calf_raises', 'core_hanging_knee_raise'] },
            { day: 'FRI', name: 'Upper Hypertrophy', is_rest: false, focus: 'Chest, Back, Arms', exercise_ids: ['chest_incline_bb_bench_press', 'chest_dips', 'back_lat_pulldown', 'sh_seated_arnold_press', 'arm_diamond_push_up'] },
            { day: 'SAT', name: 'Mobility & Active Recovery', is_rest: true, focus: 'Light Cardio & Stretching', exercise_ids: [] },
            { day: 'SUN', name: 'Rest & Recovery', is_rest: true, focus: 'Full Recovery', exercise_ids: [] }
          ]
        },
        {
          id: 'upper_lower',
          name: 'Upper / Lower (4-Day)',
          type: 'UPPER_LOWER',
          days: [
            { day: 'MON', name: 'Upper Power', is_rest: false, focus: 'Chest, Back, Arms', exercise_ids: ['chest_flat_bb_bench_press', 'back_bb_bent_over_row', 'sh_standing_bb_ohp', 'arm_bb_curl'] },
            { day: 'TUE', name: 'Lower Power', is_rest: false, focus: 'Quads, Hamstrings, Core', exercise_ids: ['leg_bb_back_squat', 'leg_rdl_bb_db_kb', 'leg_calf_raises', 'core_forearm_plank'] },
            { day: 'WED', name: 'Rest Day', is_rest: true, focus: 'Rest & Recovery', exercise_ids: [] },
            { day: 'THU', name: 'Upper Hypertrophy', is_rest: false, focus: 'Chest, Lats, Delts', exercise_ids: ['chest_incline_db_bench_press', 'back_lat_pulldown', 'sh_db_lateral_raise', 'arm_cable_rope_pushdown'] },
            { day: 'FRI', name: 'Lower Hypertrophy', is_rest: false, focus: 'Legs & Core', exercise_ids: ['leg_bulgarian_split_squat', 'leg_glute_bridge_hip_thrust', 'leg_extension_machine', 'core_hanging_knee_raise'] },
            { day: 'SAT', name: 'Active Recovery', is_rest: true, focus: 'Mobility & Walking', exercise_ids: [] },
            { day: 'SUN', name: 'Rest Day', is_rest: true, focus: 'Rest & Recovery', exercise_ids: [] }
          ]
        },
        {
          id: 'full_body',
          name: 'Full Body (3-Day)',
          type: 'FULL_BODY',
          days: [
            { day: 'MON', name: 'Full Body A', is_rest: false, focus: 'Compound Strength', exercise_ids: ['chest_flat_bb_bench_press', 'leg_bb_back_squat', 'back_bb_bent_over_row', 'sh_standing_bb_ohp'] },
            { day: 'TUE', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] },
            { day: 'WED', name: 'Full Body B', is_rest: false, focus: 'Hypertrophy Focus', exercise_ids: ['chest_incline_db_bench_press', 'leg_rdl_bb_db_kb', 'back_standard_pull_up', 'arm_bb_curl'] },
            { day: 'THU', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] },
            { day: 'FRI', name: 'Full Body C', is_rest: false, focus: 'Volume & Core', exercise_ids: ['leg_goblet_squat', 'chest_dips', 'back_lat_pulldown', 'core_hanging_knee_raise'] },
            { day: 'SAT', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] },
            { day: 'SUN', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] }
          ]
        },
        {
          id: 'bro_split',
          name: 'Bro Split (5-Day)',
          type: 'BRO_SPLIT',
          days: [
            { day: 'MON', name: 'Chest Day', is_rest: false, focus: 'Chest Focus', exercise_ids: ['chest_flat_bb_bench_press', 'chest_incline_db_bench_press', 'chest_dips', 'chest_cable_pec_fly_high_low'] },
            { day: 'TUE', name: 'Back Day', is_rest: false, focus: 'Back & Lats', exercise_ids: ['back_standard_pull_up', 'back_bb_bent_over_row', 'back_lat_pulldown', 'back_seated_cable_row'] },
            { day: 'WED', name: 'Shoulders Day', is_rest: false, focus: 'Delts & Traps', exercise_ids: ['sh_standing_bb_ohp', 'sh_db_lateral_raise', 'sh_seated_arnold_press', 'sh_face_pulls'] },
            { day: 'THU', name: 'Legs Day', is_rest: false, focus: 'Quads & Calves', exercise_ids: ['leg_bb_back_squat', 'leg_rdl_bb_db_kb', 'leg_extension_machine', 'leg_calf_raises'] },
            { day: 'FRI', name: 'Arms & Core', is_rest: false, focus: 'Biceps, Triceps, Abs', exercise_ids: ['arm_bb_curl', 'arm_cable_rope_pushdown', 'arm_hammer_curl', 'core_ab_wheel_rollout'] },
            { day: 'SAT', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] },
            { day: 'SUN', name: 'Rest Day', is_rest: true, focus: 'Rest', exercise_ids: [] }
          ]
        }
      ];
      await this.db.routines.bulkAdd(defaultRoutines);
    }
  }

  // --- Exercises API ---

  async getAllExercises() {
    return await this.db.exercises.toArray();
  }

  async getExerciseById(id) {
    return await this.db.exercises.get(id);
  }

  async addCustomExercise(exercise) {
    const id = 'custom_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7);
    const newEx = {
      id,
      name: exercise.name,
      muscle_group: exercise.muscle_group || 'Full Body',
      secondary_muscles: exercise.secondary_muscles || [],
      modality: exercise.modality || 'Free Weights',
      tier: exercise.tier || 'Intermediate',
      mechanic: exercise.mechanic || 'Compound',
      equipment: exercise.equipment || 'Custom',
      is_custom: true,
      is_favorite: false
    };
    await this.db.exercises.add(newEx);
    return newEx;
  }

  async toggleFavoriteExercise(id) {
    const ex = await this.db.exercises.get(id);
    if (ex) {
      await this.db.exercises.update(id, { is_favorite: !ex.is_favorite });
      return !ex.is_favorite;
    }
    return false;
  }

  /**
   * Surface historical weights and reps for an exercise
   * Returns saved weight/reps from exercise_history or past sets
   */
  async getPreviousPerformance(exerciseId) {
    // 1. Check direct exercise_history store (persisted across deletions/re-additions)
    const historyRecord = await this.db.exercise_history.get(exerciseId);
    if (historyRecord) {
      return {
        last_weight: historyRecord.last_weight,
        last_reps: historyRecord.last_reps,
        best_weight: historyRecord.best_weight,
        best_reps: historyRecord.best_reps,
        hasHistory: true
      };
    }

    // 2. Check sets table fallback
    const sets = await this.db.sets
      .where('exercise_id')
      .equals(exerciseId)
      .and(s => s.completed)
      .reverse()
      .sortBy('id');

    if (!sets || sets.length === 0) {
      return {
        last_weight: 0,
        last_reps: 0,
        best_weight: 0,
        best_reps: 0,
        hasHistory: false
      };
    }

    let bestSet = sets[0];
    for (const s of sets) {
      if (s.weight > bestSet.weight || (s.weight === bestSet.weight && s.reps > bestSet.reps)) {
        bestSet = s;
      }
    }

    return {
      last_weight: sets[0].weight,
      last_reps: sets[0].reps,
      best_weight: bestSet.weight,
      best_reps: bestSet.reps,
      hasHistory: true
    };
  }

  /**
   * Update saved weight and reps for an exercise so it is remembered if deleted and re-added later
   */
  async updateExercisePerformance(exerciseId, weight, reps, setsCount = 3) {
    const w = Number(weight) || 0;
    const r = Number(reps) || 0;

    const existing = await this.db.exercise_history.get(exerciseId);
    const bestW = existing ? Math.max(existing.best_weight || 0, w) : w;
    const bestR = existing && w === existing.best_weight ? Math.max(existing.best_reps || 0, r) : r;

    await this.db.exercise_history.put({
      exercise_id: exerciseId,
      last_weight: w,
      last_reps: r,
      last_sets_count: setsCount,
      best_weight: bestW,
      best_reps: bestR,
      updated_at: Date.now()
    });
  }

  // --- Active Workout Persistence ---

  async saveActiveWorkout(state) {
    await this.db.active_workout.put({
      key: 'current_active_session',
      state,
      updated_at: Date.now()
    });
  }

  async getActiveWorkout() {
    const record = await this.db.active_workout.get('current_active_session');
    return record ? record.state : null;
  }

  async clearActiveWorkout() {
    await this.db.active_workout.delete('current_active_session');
  }

  // --- Session & Sets Persistence ---

  async finishWorkout(sessionData, setsData) {
    let totalVolume = 0;
    const completedSets = setsData.filter(s => s.completed);
    completedSets.forEach(s => {
      totalVolume += (Number(s.weight) || 0) * (Number(s.reps) || 0);
    });

    const sessionRecord = {
      title: sessionData.title || 'Workout Session',
      date: sessionData.date || new Date().toISOString(),
      start_time: sessionData.start_time || Date.now(),
      end_time: Date.now(),
      duration_seconds: sessionData.duration_seconds || 0,
      total_volume: Math.round(totalVolume),
      unit: sessionData.unit || 'kg',
      status: 'completed',
      notes: sessionData.notes || ''
    };

    const sessionId = await this.db.sessions.add(sessionRecord);

    const formattedSets = completedSets.map((s, idx) => ({
      session_id: sessionId,
      exercise_id: s.exercise_id,
      set_number: s.set_number || (idx + 1),
      weight: Number(s.weight) || 0,
      reps: Number(s.reps) || 0,
      unit: sessionData.unit || 'kg',
      completed: true,
      created_at: new Date().toISOString()
    }));

    if (formattedSets.length > 0) {
      await this.db.sets.bulkAdd(formattedSets);
    }

    // Update historical performance per exercise
    for (const s of completedSets) {
      if (s.exercise_id && (s.weight > 0 || s.reps > 0)) {
        await this.updateExercisePerformance(s.exercise_id, s.weight, s.reps);
      }
    }

    await this.clearActiveWorkout();
    return sessionId;
  }

  async getWorkoutHistory() {
    const sessions = await this.db.sessions.orderBy('id').reverse().toArray();
    const history = [];

    for (const session of sessions) {
      const sets = await this.db.sets.where('session_id').equals(session.id).toArray();
      const exerciseGroups = {};
      for (const set of sets) {
        if (!exerciseGroups[set.exercise_id]) {
          const exInfo = await this.getExerciseById(set.exercise_id);
          exerciseGroups[set.exercise_id] = {
            exercise_id: set.exercise_id,
            exercise_name: exInfo ? exInfo.name : 'Movement',
            muscle_group: exInfo ? exInfo.muscle_group : 'Full Body',
            sets: []
          };
        }
        exerciseGroups[set.exercise_id].sets.push(set);
      }

      history.push({
        ...session,
        exercises: Object.values(exerciseGroups),
        total_sets: sets.length
      });
    }

    return history;
  }

  async deleteWorkoutSession(sessionId) {
    await this.db.sets.where('session_id').equals(sessionId).delete();
    await this.db.sessions.delete(sessionId);
  }

  // --- Routine Planner API ---

  async getRoutines() {
    return await this.db.routines.toArray();
  }

  async saveRoutine(routine) {
    await this.db.routines.put(routine);
  }

  // --- Settings API ---

  async getSetting(key, defaultValue = null) {
    const rec = await this.db.settings.get(key);
    return rec ? rec.value : defaultValue;
  }

  async setSetting(key, value) {
    await this.db.settings.put({ key, value });
  }

  // --- Telemetry & Analytics ---

  async getTelemetryStats() {
    const sessions = await this.db.sessions.toArray();
    const sets = await this.db.sets.toArray();

    let totalVolume = 0;
    sessions.forEach(s => totalVolume += (s.total_volume || 0));

    const past7Days = [0, 0, 0, 0, 0, 0, 0];
    const now = new Date();
    const currentDay = (now.getDay() + 6) % 7;

    sessions.forEach(s => {
      const sDate = new Date(s.date);
      const diffDays = Math.floor((now.getTime() - sDate.getTime()) / (1000 * 3600 * 24));
      if (diffDays >= 0 && diffDays < 7) {
        const dayIdx = (sDate.getDay() + 6) % 7;
        past7Days[dayIdx] += (s.total_volume || 0);
      }
    });

    return {
      total_sessions: sessions.length,
      total_volume: totalVolume,
      total_sets: sets.length,
      daily_distribution: past7Days,
      current_day_index: currentDay
    };
  }

  // --- Backup & Restore ---

  async exportBackup() {
    const exercises = await this.db.exercises.toArray();
    const sessions = await this.db.sessions.toArray();
    const sets = await this.db.sets.toArray();
    const routines = await this.db.routines.toArray();
    const history = await this.db.exercise_history.toArray();

    return {
      version: 2,
      app: 'IronPulse',
      timestamp: new Date().toISOString(),
      data: {
        exercises,
        sessions,
        sets,
        routines,
        history
      }
    };
  }

  async importBackup(backup) {
    if (!backup || !backup.data) throw new Error('Invalid IronPulse backup format');
    if (backup.data.exercises) {
      await this.db.exercises.clear();
      await this.db.exercises.bulkAdd(backup.data.exercises);
    }
    if (backup.data.sessions) {
      await this.db.sessions.clear();
      await this.db.sessions.bulkAdd(backup.data.sessions);
    }
    if (backup.data.sets) {
      await this.db.sets.clear();
      await this.db.sets.bulkAdd(backup.data.sets);
    }
    if (backup.data.routines) {
      await this.db.routines.clear();
      await this.db.routines.bulkAdd(backup.data.routines);
    }
    if (backup.data.history) {
      await this.db.exercise_history.clear();
      await this.db.exercise_history.bulkAdd(backup.data.history);
    }
  }

  async resetCatalog() {
    if (window.INITIAL_EXERCISES) {
      const customOnes = await this.db.exercises.where('is_custom').equals(true).toArray();
      await this.db.exercises.clear();
      const systemOnes = window.INITIAL_EXERCISES.map(e => ({ ...e, is_custom: false, is_favorite: false }));
      await this.db.exercises.bulkAdd([...systemOnes, ...customOnes]);
    }
  }
}

window.ironPulseDB = new IronPulseDatabase();
