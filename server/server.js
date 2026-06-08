const http = require('http');
const crypto = require('crypto');
const { Server } = require('socket.io');

// --- SERVER BOOTSTRAP ---
const httpServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('ARGEYM VPS ONLINE');
});

const io = new Server(httpServer, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

// --- ROOM STATE ---
const rooms = {};
const HIT_THRESHOLD_DEG = 15;
const MAX_HP = 100;
const HIT_DAMAGE = 20;
const COUNTDOWN_SECONDS = 3;

// --- GEOMETRY HELPERS ---
function generateRoomId() {
  return crypto.randomBytes(3).toString('hex').toUpperCase();
}

function angularDistance(a, b) {
  let diff = Math.abs(a - b) % 360;
  if (diff > 180) diff = 360 - diff;
  return diff;
}

function getOpponent(room, socketId) {
  return room.players.find((p) => p.id !== socketId) || null;
}

// --- COUNTDOWN ENGINE ---
function runCountdown(roomId) {
  io.to(roomId).emit('start_countdown', {});
  let count = COUNTDOWN_SECONDS;
  const tick = () => {
    if (!rooms[roomId]) return;
    if (count > 0) {
      io.to(roomId).emit('countdown', { count });
      count -= 1;
      setTimeout(tick, 1000);
    } else {
      io.to(roomId).emit('countdown', { count: 0 });
      setTimeout(() => {
        if (rooms[roomId]) io.to(roomId).emit('game_start', {});
      }, 1000);
    }
  };
  tick();
}

// --- CONNECTION LIFECYCLE ---
io.on('connection', (socket) => {
  // --- ROOM HOSTING ---
  socket.on('host_room', () => {
    let roomId = generateRoomId();
    while (rooms[roomId]) roomId = generateRoomId();
    rooms[roomId] = {
      id: roomId,
      started: false,
      players: [{ id: socket.id, hp: MAX_HP, ready: false, baseline: null }],
    };
    socket.join(roomId);
    socket.data.roomId = roomId;
    socket.emit('room_created', { roomId });
  });

  // --- ROOM JOINING ---
  socket.on('join_room', (payload) => {
    const roomId = payload && payload.roomId ? String(payload.roomId).toUpperCase() : '';
    const room = rooms[roomId];
    if (!room) {
      socket.emit('join_error', { message: 'INVALID ROOM' });
      return;
    }
    if (room.players.length >= 2) {
      socket.emit('join_error', { message: 'ROOM FULL' });
      return;
    }
    room.players.push({ id: socket.id, hp: MAX_HP, ready: false, baseline: null });
    socket.join(roomId);
    socket.data.roomId = roomId;
    socket.emit('room_joined', { roomId });
    socket.to(roomId).emit('opponent_joined', { id: socket.id });
  });

  // --- READY SYNC ---
  socket.on('player_ready', (payload) => {
    const room = rooms[socket.data.roomId];
    if (!room) return;
    const player = room.players.find((p) => p.id === socket.id);
    if (!player) return;
    player.ready = !!(payload && payload.ready === true);
    const allReady = room.players.length === 2 && room.players.every((p) => p.ready);
    if (allReady && !room.started) {
      room.started = true;
      runCountdown(room.id);
    }
  });

  // --- CALIBRATION ---
  socket.on('calibrate', (payload) => {
    const room = rooms[socket.data.roomId];
    if (!room) return;
    const player = room.players.find((p) => p.id === socket.id);
    if (!player) return;
    player.baseline = payload && typeof payload.heading === 'number' ? payload.heading : 0;
  });

  // --- HIT SCAN VALIDATION ---
  socket.on('shoot', (payload) => {
    const room = rooms[socket.data.roomId];
    if (!room || !room.started) return;
    const shooter = room.players.find((p) => p.id === socket.id);
    const victim = getOpponent(room, socket.id);
    if (!shooter || !victim) return;
    const baseline = shooter.baseline === null ? 0 : shooter.baseline;
    const current = payload && typeof payload.heading === 'number' ? payload.heading : baseline;
    const delta = angularDistance(current, baseline);
    if (delta <= HIT_THRESHOLD_DEG) {
      socket.emit('hit_confirmed', { delta });
      victim.hp = Math.max(0, victim.hp - HIT_DAMAGE);
      io.to(victim.id).emit('hit_taken', { hp: victim.hp });
      if (victim.hp <= 0) {
        io.to(room.id).emit('game_over', { winner: shooter.id });
        delete rooms[room.id];
      }
    }
  });

  // --- DISCONNECT HANDLING ---
  socket.on('disconnect', () => {
    const room = rooms[socket.data.roomId];
    if (!room) return;
    socket.to(room.id).emit('opponent_disconnected', { id: socket.id });
    room.players = room.players.filter((p) => p.id !== socket.id);
    if (room.players.length === 0) delete rooms[room.id];
  });
});

// --- LISTENER ---
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log('ARGEYM VPS listening on port ' + PORT);
});
