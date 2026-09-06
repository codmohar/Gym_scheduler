/**
 * IronPulse REST API Server (Node.js)
 * Zero-dependency robust HTTP server with full REST endpoints
 */

const http = require('http');
const url = require('url');
const db = require('./db');

const PORT = process.env.PORT || 5000;

function sendJSON(res, statusCode, data) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  });
  res.end(JSON.stringify(data, null, 2));
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (err) {
        resolve({});
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    });
    res.end();
    return;
  }

  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;
  const query = parsedUrl.query;
  const method = req.method;

  try {
    // Health Check
    if (method === 'GET' && pathname === '/api/health') {
      return sendJSON(res, 200, {
        status: 'online',
        app: 'IronPulse Backend',
        postgres_connected: db.isPostgresConnected,
        total_exercises: db.localExercises.length,
        timestamp: new Date().toISOString()
      });
    }

    // Get Exercises Grouped by Body Part
    if (method === 'GET' && pathname === '/api/exercises/by-body-part') {
      const grouped = await db.getExercisesByBodyPart();
      return sendJSON(res, 200, { success: true, data: grouped });
    }

    // List Exercises (with filter queries)
    if (method === 'GET' && pathname === '/api/exercises') {
      const exercises = await db.getExercises(query);
      return sendJSON(res, 200, {
        success: true,
        count: exercises.length,
        data: exercises
      });
    }

    // Get Single Exercise by ID
    if (method === 'GET' && pathname.startsWith('/api/exercises/')) {
      const id = pathname.replace('/api/exercises/', '');
      const ex = await db.getExerciseById(id);
      if (!ex) return sendJSON(res, 404, { success: false, error: 'Exercise not found' });
      return sendJSON(res, 200, { success: true, data: ex });
    }

    // Create Custom Exercise
    if (method === 'POST' && pathname === '/api/exercises') {
      const body = await parseBody(req);
      if (!body.name) {
        return sendJSON(res, 400, { success: false, error: 'Exercise name is required' });
      }
      const created = await db.createExercise(body);
      return sendJSON(res, 201, { success: true, data: created });
    }

    // Get Sessions
    if (method === 'GET' && pathname === '/api/sessions') {
      const sessions = await db.getSessions();
      return sendJSON(res, 200, { success: true, count: sessions.length, data: sessions });
    }

    // Log Session
    if (method === 'POST' && pathname === '/api/sessions') {
      const body = await parseBody(req);
      const saved = await db.saveSession(body, body.sets || []);
      return sendJSON(res, 201, { success: true, data: saved });
    }

    // Get Split Routine Templates
    if (method === 'GET' && pathname === '/api/routines') {
      const routines = [
        {
          id: 'ppl',
          name: 'Push / Pull / Legs (6-Day Split)',
          description: 'High hypertrophy frequency targeting major muscle groups twice weekly.'
        },
        {
          id: 'upper_lower',
          name: 'Upper / Lower (4-Day Split)',
          description: 'Classic strength and mass split with balanced recovery intervals.'
        }
      ];
      return sendJSON(res, 200, { success: true, data: routines });
    }

    // 404 Route Not Found
    return sendJSON(res, 404, { success: false, error: 'API route not found' });

  } catch (error) {
    console.error('[Backend API Error]:', error);
    return sendJSON(res, 500, { success: false, error: 'Internal Server Error' });
  }
});

server.listen(PORT, () => {
  console.log(`\n🚀 [IronPulse Backend] API Server listening at http://localhost:${PORT}`);
  console.log(`📡 Endpoints:`);
  console.log(`   - GET  /api/health`);
  console.log(`   - GET  /api/exercises (filters: ?muscle_group=Chest&modality=Free+Weights)`);
  console.log(`   - GET  /api/exercises/by-body-part`);
  console.log(`   - POST /api/exercises`);
  console.log(`   - GET  /api/sessions\n`);
});
