const http = require('http');
const crypto = require('crypto');
const { Server } = require('socket.io');

function envBool(name) {
  const v = (process.env[name] || '').toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}
function envNum(name, def) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : def;
}

const NORMAL_RANGE = envNum('HIT_RANGE_M', 80);
const NORMAL_ANGLE = envNum('HIT_ANGLE_DEG', 12);
const TEST_RANGE   = envNum('TEST_RANGE_M', 300);
const TEST_ANGLE   = envNum('TEST_ANGLE_DEG', 45);

const TEST_MODE  = envBool('TEST_MODE');
const IGNORE_AIM = envBool('IGNORE_AIM') || envBool('THROUGH_WALLS');
const INITIAL_MODE = IGNORE_AIM ? 'walls' : (TEST_MODE ? 'test' : 'normal');

const MAX_HP           = 100;
const HIT_DAMAGE       = 25;
const COUNTDOWN_SECONDS = 3;
const RESPAWN_MS       = 4000;

function presetFor(mode) {
  if (mode === 'walls') return { mode: 'walls', ignoreAim: true,  rangeM: TEST_RANGE, angleDeg: TEST_ANGLE };
  if (mode === 'test')  return { mode: 'test',  ignoreAim: false, rangeM: TEST_RANGE, angleDeg: TEST_ANGLE };
  return                       { mode: 'normal',ignoreAim: false, rangeM: NORMAL_RANGE, angleDeg: NORMAL_ANGLE };
}

const CONFIG_LINE = 'default_mode=' + INITIAL_MODE +
  ' normal=' + NORMAL_RANGE + 'm/' + NORMAL_ANGLE + 'deg' +
  ' test=' + TEST_RANGE + 'm/' + TEST_ANGLE + 'deg';

const httpServer = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('ARGEYM VPS ONLINE | ' + CONFIG_LINE);
});

const io = new Server(httpServer, { cors: { origin: '*', methods: ['GET', 'POST'] } });
const rooms = {};

function generateRoomId() { return crypto.randomBytes(3).toString('hex').toUpperCase(); }
function angularDistance(a, b) { let d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; }
function toRad(d) { return d * Math.PI / 180; }
function toDeg(r) { return r * 180 / Math.PI; }
function bearing(lat1, lon1, lat2, lon2) {
  const dLon = toRad(lon2 - lon1);
  const y = Math.sin(dLon) * Math.cos(toRad(lat2));
  const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
            Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}
function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2)**2 + Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*Math.sin(dLon/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
function newPlayer(id, name) {
  return { id, name, hp: MAX_HP, ready: false, alive: true, kills: 0, deaths: 0, lat: null, lng: null, heading: 0, hasGps: false };
}
function getOpponent(room, id)  { return room.players.find(p => p.id !== id) || null; }
function findPlayer(room, id)   { return room.players.find(p => p.id === id) || null; }
function publicPlayers(room) {
  return room.players.map(p => ({ id: p.id, name: p.name, ready: p.ready, kills: p.kills, deaths: p.deaths }));
}
function emitLobby(roomId) { const r = rooms[roomId]; if (r) io.to(roomId).emit('lobby_update', { roomId, players: publicPlayers(r) }); }
function emitMode(roomId)  { const r = rooms[roomId]; if (r) io.to(roomId).emit('room_mode', r.config); }

function runCountdown(roomId) {
  io.to(roomId).emit('start_countdown', {});
  let count = COUNTDOWN_SECONDS;
  const tick = () => {
    if (!rooms[roomId]) return;
    if (count > 0) { io.to(roomId).emit('countdown', { count }); count--; setTimeout(tick, 1000); }
    else { io.to(roomId).emit('countdown', { count: 0 }); setTimeout(() => { if (rooms[roomId]) io.to(roomId).emit('game_start', {}); }, 1000); }
  };
  tick();
}

function endGame(socket, reason) {
  const room = rooms[socket.data.roomId];
  if (!room) return;
  socket.to(room.id).emit('game_ended', { reason });
  room.players = room.players.filter(p => p.id !== socket.id);
  if (room.players.length === 0) { delete rooms[room.id]; }
  else { room.started = false; room.players.forEach(p => { p.ready = false; }); emitLobby(room.id); }
}

io.on('connection', (socket) => {
  socket.on('host_room', (payload) => {
    let roomId = generateRoomId();
    while (rooms[roomId]) roomId = generateRoomId();
    const name = payload && payload.name ? String(payload.name).slice(0, 16) : 'HOST';
    rooms[roomId] = { id: roomId, started: false, players: [newPlayer(socket.id, name)], config: presetFor(INITIAL_MODE) };
    socket.join(roomId); socket.data.roomId = roomId;
    socket.emit('room_created', { roomId }); emitLobby(roomId); emitMode(roomId);
  });

  socket.on('join_room', (payload) => {
    const roomId = payload && payload.roomId ? String(payload.roomId).toUpperCase() : '';
    const name   = payload && payload.name   ? String(payload.name).slice(0, 16) : 'PLAYER';
    const room   = rooms[roomId];
    if (!room) { socket.emit('join_error', { message: 'INVALID ROOM' }); return; }
    if (room.players.length >= 2) { socket.emit('join_error', { message: 'ROOM FULL' }); return; }
    room.players.push(newPlayer(socket.id, name));
    socket.join(roomId); socket.data.roomId = roomId;
    socket.emit('room_joined', { roomId }); socket.to(roomId).emit('opponent_joined', { id: socket.id, name });
    emitLobby(roomId); emitMode(roomId);
  });

  socket.on('set_room_mode', (payload) => {
    const room = rooms[socket.data.roomId]; if (!room) return;
    const mode = payload && typeof payload.mode === 'string' ? payload.mode : '';
    if (!['normal','test','walls'].includes(mode)) return;
    room.config = presetFor(mode); emitMode(room.id);
  });

  socket.on('player_ready', (payload) => {
    const room = rooms[socket.data.roomId]; if (!room) return;
    const player = findPlayer(room, socket.id); if (!player) return;
    player.ready = !!(payload && payload.ready === true); emitLobby(room.id);
    const allReady = room.players.length === 2 && room.players.every(p => p.ready);
    if (allReady && !room.started) { room.started = true; runCountdown(room.id); }
  });

  socket.on('telemetry', (payload) => {
    const room = rooms[socket.data.roomId]; if (!room) return;
    const player = findPlayer(room, socket.id); if (!player) return;
    if (payload && typeof payload.heading === 'number') player.heading = payload.heading;
    if (payload && typeof payload.lat === 'number' && typeof payload.lng === 'number') {
      player.lat = payload.lat; player.lng = payload.lng; player.hasGps = true;
    }
    const opp = getOpponent(room, socket.id);
    if (opp) io.to(opp.id).emit('opponent_telemetry', { id: player.id, name: player.name, heading: player.heading, lat: player.lat, lng: player.lng, hasGps: player.hasGps, hp: player.hp, alive: player.alive });
  });

  socket.on('shoot', (payload) => {
    const room = rooms[socket.data.roomId]; if (!room || !room.started) return;
    const shooter = findPlayer(room, socket.id); const victim = getOpponent(room, socket.id);
    if (!shooter || !victim || !shooter.alive || !victim.alive) return;
    const cfg = room.config || presetFor(INITIAL_MODE);
    const sh = payload && typeof payload.heading === 'number' ? payload.heading : shooter.heading;
    if (payload && typeof payload.lat === 'number') shooter.lat = payload.lat;
    if (payload && typeof payload.lng === 'number') shooter.lng = payload.lng;

    let hit = false, info = {};
    if (cfg.ignoreAim) {
      hit = true; info = { mode: 'walls' };
    } else if (shooter.hasGps && victim.hasGps && shooter.lat !== null && victim.lat !== null) {
      const b = bearing(shooter.lat, shooter.lng, victim.lat, victim.lng);
      const d = haversine(shooter.lat, shooter.lng, victim.lat, victim.lng);
      const delta = angularDistance(sh, b);
      hit = d <= cfg.rangeM && delta <= cfg.angleDeg; info = { mode: cfg.mode, delta, distance: d };
    } else {
      const facing = angularDistance(angularDistance(sh, victim.heading), 180);
      hit = facing <= cfg.angleDeg; info = { mode: 'compass', delta: facing };
    }

    if (!hit) { socket.emit('shot_missed', info); return; }
    socket.emit('hit_confirmed', info);
    victim.hp = Math.max(0, victim.hp - HIT_DAMAGE);
    io.to(victim.id).emit('hit_taken', { hp: victim.hp });

    if (victim.hp <= 0) {
      victim.alive = false; shooter.kills++; victim.deaths++;
      io.to(room.id).emit('fragged', { killer: shooter.id, killerName: shooter.name, victim: victim.id, victimName: victim.name, kills: shooter.kills, respawnMs: RESPAWN_MS });
      io.to(room.id).emit('score', { players: publicPlayers(room) });
      const vid = victim.id, rid = room.id;
      setTimeout(() => {
        const r = rooms[rid]; if (!r) return;
        const v = findPlayer(r, vid); if (!v) return;
        v.hp = MAX_HP; v.alive = true; io.to(vid).emit('respawn', { hp: MAX_HP });
      }, RESPAWN_MS);
    }
  });

  socket.on('leave_game',  () => endGame(socket, 'OPPONENT LEFT'));
  socket.on('disconnect',  () => endGame(socket, 'OPPONENT DISCONNECTED'));
});

const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => { console.log('ARGEYM VPS listening on port ' + PORT + ' | ' + CONFIG_LINE); });
