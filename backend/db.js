/**
 * IronPulse Backend Database Connector
 * Integrates with PostgreSQL (database/schema.sql & database/seed.sql)
 * with automatic fallback to database/exercises.json.
 */

const fs = require('fs');
const path = require('path');

const EXERCISES_JSON_PATH = path.join(__dirname, '..', 'database', 'exercises.json');

class DatabaseService {
  constructor() {
    this.pgPool = null;
    this.isPostgresConnected = false;
    this.localExercises = [];
    this.localSessions = [];
    this.localSets = [];
    this.loadLocalExercises();
    this.initPostgres();
  }

  loadLocalExercises() {
    try {
      if (fs.existsSync(EXERCISES_JSON_PATH)) {
        const raw = fs.readFileSync(EXERCISES_JSON_PATH, 'utf-8');
        this.localExercises = JSON.parse(raw);
        console.log(`[Backend DB] Loaded ${this.localExercises.length} exercises from database/exercises.json`);
      }
    } catch (err) {
      console.error('[Backend DB] Error loading exercises.json:', err.message);
    }
  }

  async initPostgres() {
    try {
      const { Pool } = require('pg');
      const pool = new Pool({
        user: process.env.POSTGRES_USER || 'gym_user',
        host: process.env.POSTGRES_HOST || 'localhost',
        database: process.env.POSTGRES_DB || 'gym_scheduler',
        password: process.env.POSTGRES_PASSWORD || 'gym_password',
        port: parseInt(process.env.POSTGRES_PORT || '5432', 10),
        connectionTimeoutMillis: 2000
      });

      const client = await pool.connect();
      this.isPostgresConnected = true;
      this.pgPool = pool;
      client.release();
      console.log('[Backend DB] Successfully connected to PostgreSQL database!');
    } catch (err) {
      this.isPostgresConnected = false;
      console.log('[Backend DB] PostgreSQL connection note: using local file dataset (PostgreSQL container optional).');
    }
  }

  async getExercises(filters = {}) {
    const { muscle_group, body_part, modality, tier, search } = filters;
    const targetGroup = muscle_group || body_part;

    if (this.isPostgresConnected && this.pgPool) {
      try {
        let query = 'SELECT * FROM exercises WHERE 1=1';
        const params = [];

        if (targetGroup) {
          params.push(`%${targetGroup}%`);
          query += ` AND muscle_group ILIKE $${params.length}`;
        }
        if (modality) {
          params.push(modality);
          query += ` AND modality = $${params.length}`;
        }
        if (tier) {
          params.push(tier);
          query += ` AND tier = $${params.length}`;
        }
        if (search) {
          params.push(`%${search}%`);
          query += ` AND (name ILIKE $${params.length} OR equipment ILIKE $${params.length} OR $${params.length} = ANY(secondary_muscles))`;
        }

        query += ' ORDER BY name ASC';
        const result = await this.pgPool.query(query, params);
        return result.rows;
      } catch (e) {
        console.warn('[Backend DB] Postgres query failed, falling back to local:', e.message);
      }
    }

    // Fallback in-memory filter
    return this.localExercises.filter(ex => {
      if (targetGroup) {
        const mg = (ex.muscle_group || '').toLowerCase();
        const tg = targetGroup.toLowerCase();
        if (!mg.includes(tg)) return false;
      }
      if (modality && (ex.modality || '').toLowerCase() !== modality.toLowerCase()) {
        return false;
      }
      if (tier && (ex.tier || '').toLowerCase() !== tier.toLowerCase()) {
        return false;
      }
      if (search) {
        const s = search.toLowerCase();
        const nameMatch = (ex.name || '').toLowerCase().includes(s);
        const secMatch = (ex.secondary_muscles || []).some(m => m.toLowerCase().includes(s));
        const eqMatch = (ex.equipment || '').toLowerCase().includes(s);
        if (!nameMatch && !secMatch && !eqMatch) return false;
      }
      return true;
    });
  }

  async getExercisesByBodyPart() {
    const all = await this.getExercises();
    const grouped = {};

    all.forEach(ex => {
      const group = ex.muscle_group || 'Other';
      if (!grouped[group]) {
        grouped[group] = {
          body_part: group,
          count: 0,
          exercises: []
        };
      }
      grouped[group].count++;
      grouped[group].exercises.push(ex);
    });

    return grouped;
  }

  async getExerciseById(id) {
    if (this.isPostgresConnected && this.pgPool) {
      try {
        const res = await this.pgPool.query('SELECT * FROM exercises WHERE id = $1', [id]);
        if (res.rows.length > 0) return res.rows[0];
      } catch (e) {
        // fallback
      }
    }
    return this.localExercises.find(e => e.id === id) || null;
  }

  async createExercise(exercise) {
    const id = exercise.id || 'custom_' + Date.now();
    const newEx = {
      id,
      name: exercise.name,
      muscle_group: exercise.muscle_group || 'Full Body',
      secondary_muscles: exercise.secondary_muscles || [],
      modality: exercise.modality || 'Free Weights',
      tier: exercise.tier || 'Intermediate',
      mechanic: exercise.mechanic || 'Compound',
      equipment: exercise.equipment || 'Custom',
      is_custom: true
    };

    if (this.isPostgresConnected && this.pgPool) {
      try {
        await this.pgPool.query(
          `INSERT INTO exercises (id, name, muscle_group, secondary_muscles, modality, tier, mechanic, equipment)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name`,
          [newEx.id, newEx.name, newEx.muscle_group, newEx.secondary_muscles, newEx.modality, newEx.tier, newEx.mechanic, newEx.equipment]
        );
      } catch (e) {
        console.error('[Backend DB] Postgres insert failed:', e.message);
      }
    }

    this.localExercises.push(newEx);
    return newEx;
  }

  async getSessions() {
    return this.localSessions;
  }

  async saveSession(sessionData, setsData = []) {
    const session = {
      id: this.localSessions.length + 1,
      title: sessionData.title || 'Workout Session',
      date: sessionData.date || new Date().toISOString(),
      duration_seconds: sessionData.duration_seconds || 0,
      total_volume: sessionData.total_volume || 0,
      notes: sessionData.notes || '',
      sets: setsData
    };
    this.localSessions.unshift(session);
    return session;
  }
}

module.exports = new DatabaseService();
