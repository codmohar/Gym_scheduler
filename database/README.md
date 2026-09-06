# Gym Scheduler Database (PostgreSQL)

This directory contains the PostgreSQL database schema and seed data for all exercises.

## Files
- [`schema.sql`](file:///c:/Users/466mo/OneDrive/Desktop/New%20folder/gym_scheduler/database/schema.sql): Table definition and indexes.
- [`seed.sql`](file:///c:/Users/466mo/OneDrive/Desktop/New%20folder/gym_scheduler/database/seed.sql): All 168 exercises with proper PostgreSQL types (`TEXT[]` for `secondary_muscles`).
- [`init.sql`](file:///c:/Users/466mo/OneDrive/Desktop/New%20folder/gym_scheduler/database/init.sql): Combined schema and seed script (used by Docker Compose).
- [`exercises.json`](file:///c:/Users/466mo/OneDrive/Desktop/New%20folder/gym_scheduler/database/exercises.json): Raw JSON exercise dataset.

## Running with Docker Compose
To start the PostgreSQL container with automatic table creation and data seeding:
```bash
docker compose up -d
```

## Database Connection
- **Host**: `localhost`
- **Port**: `5432`
- **Database**: `gym_scheduler`
- **User**: `gym_user`
- **Password**: `gym_password`

## Common SQL Query Examples

### 1. Filter by Muscle Group & Modality
```sql
SELECT id, name, tier, equipment
FROM exercises
WHERE muscle_group = 'Chest' AND modality = 'Calisthenics';
```

### 2. Search by Secondary Muscle (PostgreSQL Array Search)
```sql
SELECT id, name, muscle_group, secondary_muscles
FROM exercises
WHERE 'Triceps' = ANY(secondary_muscles);
```

### 3. Array Overlap (Contains Any of Multiple Muscles)
```sql
SELECT id, name, secondary_muscles
FROM exercises
WHERE secondary_muscles && ARRAY['Core', 'Obliques']::TEXT[];
```
