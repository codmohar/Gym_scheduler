-- PostgreSQL Schema for Gym Scheduler Exercises

CREATE TABLE IF NOT EXISTS exercises (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    muscle_group VARCHAR(100) NOT NULL,
    secondary_muscles TEXT[] NOT NULL DEFAULT '{}',
    modality VARCHAR(100) NOT NULL,
    tier VARCHAR(50) NOT NULL,
    mechanic VARCHAR(100) NOT NULL,
    equipment VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for efficient querying and filtering
CREATE INDEX IF NOT EXISTS idx_exercises_muscle_group ON exercises(muscle_group);
CREATE INDEX IF NOT EXISTS idx_exercises_modality ON exercises(modality);
CREATE INDEX IF NOT EXISTS idx_exercises_tier ON exercises(tier);
CREATE INDEX IF NOT EXISTS idx_exercises_equipment ON exercises(equipment);
CREATE INDEX IF NOT EXISTS idx_exercises_secondary_muscles ON exercises USING GIN(secondary_muscles);
