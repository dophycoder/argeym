const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingTimeout: 10000,
  pingInterval: 5000
});

const PORT = 3001;
const rooms = {};

function generateRoomId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let id = '';
  for (let i = 0; i < 6; i++) id += chars[Math.floor(Math.random() * chars.length)];
  return id;
}

function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function calculateBearing(lat1, lon1, lat2, lon2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const toDeg = (r) => (r * 180) / Math.PI;
  const dLon = toRad(lon2 - lon1);
  const y = Math.sin(dLon) * Math.cos(toRad(lat2));
  const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
    Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function shortestAngleDelta(bearing, heading) {
  return ((bearing - heading + 540) % 360) - 180;
}

function deleteRoom(roomId, reason) {
  const room = rooms[roomId];
  if (!room) return;
  console.log(`[Room ${roomId}] Deleted: ${reason}`);
  for (const pid of Object.keys(room.players)) {
    const s = io.sockets.sockets.get(pid);
    if (s) {
      s.emit('room_deleted', { reason });
      s.leave(roomId);
    }
  }
  delete rooms[roomId];
}

io.on('connection', (socket) => {
  console.log(`[Connect] ${socket.id}`);
  let currentRoom = null;

  socket.on('create_room', (data, cb) => {
    const roomId = generateRoomId();
    const nickname = data.nickname || 'unknown';
    rooms[roomId] = {
      state: 'LOBBY',
      host: socket.id,
      players: {
        [socket.id]: {
          nickname,
          lat: 0, lon: 0, heading: 0,
          hp: 100,
          spawnShieldUntil: 0,
          kills: 0, deaths: 0
        }
      },
      maxRange: 200,
      fovDeg: 15,
      countdownTimer: null
    };
    currentRoom = roomId;
    socket.join(roomId);
    console.log(`[Room ${roomId}] Created by ${nickname}`);
    if (cb) cb({ success: true, roomId });
  });

  socket.on('join_room', (data, cb) => {
    const roomId = (data.roomId || '').toUpperCase().trim();
    const nickname = data.nickname || 'unknown';
    const room = rooms[roomId];
    if (!room) {
      if (cb) cb({ success: false, error: 'Room not found' });
      return;
    }
    if (Object.keys(room.players).length >= 2) {
      if (cb) cb({ success: false, error: 'Room is full' });
      return;
    }
    if (room.state !== 'LOBBY') {
      if (cb) cb({ success: false, error: 'Game already in progress' });
      return;
    }
    room.players[socket.id] = {
      nickname,
      lat: 0, lon: 0, heading: 0,
      hp: 100,
      spawnShieldUntil: 0,
      kills: 0, deaths: 0
    };
    currentRoom = roomId;
    socket.join(roomId);
    console.log(`[Room ${roomId}] ${nickname} joined`);
    if (cb) cb({ success: true, roomId });

    const playerList = Object.entries(room.players).map(([id, p]) => ({
      id, nickname: p.nickname
    }));
    io.to(roomId).emit('lobby_update', { players: playerList, state: room.state });

    if (Object.keys(room.players).length === 2) {
      startCountdown(roomId);
    }
  });

  function startCountdown(roomId) {
    const room = rooms[roomId];
    if (!room) return;
    room.state = 'COUNTDOWN';
    let count = 3;
    io.to(roomId).emit('state_change', { state: 'COUNTDOWN', countdown: count });
    console.log(`[Room ${roomId}] COUNTDOWN started`);
    room.countdownTimer = setInterval(() => {
      count--;
      if (count <= 0) {
        clearInterval(room.countdownTimer);
        room.countdownTimer = null;
        room.state = 'PLAYING';
        const now = Date.now();
        for (const pid of Object.keys(room.players)) {
          room.players[pid].hp = 100;
          room.players[pid].spawnShieldUntil = now + 3000;
        }
        io.to(roomId).emit('state_change', { state: 'PLAYING' });
        console.log(`[Room ${roomId}] PLAYING`);
      } else {
        io.to(roomId).emit('state_change', { state: 'COUNTDOWN', countdown: count });
      }
    }, 1000);
  }

  socket.on('update_position', (data) => {
    if (!currentRoom || !rooms[currentRoom]) return;
    const player = rooms[currentRoom].players[socket.id];
    if (!player) return;
    player.lat = data.lat || 0;
    player.lon = data.lon || 0;
    player.heading = data.heading || 0;

    const opponents = {};
    for (const [pid, p] of Object.entries(rooms[currentRoom].players)) {
      if (pid !== socket.id) {
        opponents[pid] = {
          nickname: p.nickname,
          lat: p.lat,
          lon: p.lon,
          hp: p.hp,
          hasShield: Date.now() < p.spawnShieldUntil
        };
      }
    }
    socket.emit('opponents_update', opponents);
  });

  socket.on('fire', (data) => {
    if (!currentRoom || !rooms[currentRoom]) return;
    const room = rooms[currentRoom];
    if (room.state !== 'PLAYING') return;

    const shooter = room.players[socket.id];
    if (!shooter) return;

    const shooterHeading = data.heading || shooter.heading;

    io.to(currentRoom).emit('player_fired', {
      shooterId: socket.id,
      nickname: shooter.nickname
    });

    for (const [pid, target] of Object.entries(room.players)) {
      if (pid === socket.id) continue;

      const now = Date.now();
      if (now < target.spawnShieldUntil) {
        console.log(`[Room ${currentRoom}] Shot blocked by spawn shield`);
        continue;
      }

      const dist = haversineDistance(shooter.lat, shooter.lon, target.lat, target.lon);
      if (dist > room.maxRange) {
        console.log(`[Room ${currentRoom}] Shot missed: distance ${dist.toFixed(1)}m > ${room.maxRange}m`);
        continue;
      }

      const bearing = calculateBearing(shooter.lat, shooter.lon, target.lat, target.lon);
      const angleDelta = shortestAngleDelta(bearing, shooterHeading);

      if (Math.abs(angleDelta) > room.fovDeg) {
        console.log(`[Room ${currentRoom}] Shot missed: angle ${angleDelta.toFixed(1)}° > ±${room.fovDeg}°`);
        continue;
      }

      target.hp = Math.max(0, target.hp - 20);
      console.log(`[Room ${currentRoom}] HIT! ${shooter.nickname} -> ${target.nickname} (HP: ${target.hp})`);

      io.to(currentRoom).emit('player_hit', {
        shooterId: socket.id,
        targetId: pid,
        damage: 20,
        targetHp: target.hp,
        shooterNickname: shooter.nickname,
        targetNickname: target.nickname
      });

      if (target.hp <= 0) {
        shooter.kills++;
        target.deaths++;
        console.log(`[Room ${currentRoom}] KILL! ${shooter.nickname} killed ${target.nickname}`);
        io.to(currentRoom).emit('player_killed', {
          killerId: socket.id,
          victimId: pid,
          killerNickname: shooter.nickname,
          victimNickname: target.nickname,
          killerKills: shooter.kills,
          victimDeaths: target.deaths
        });
      }
    }
  });

  socket.on('respawn', () => {
    if (!currentRoom || !rooms[currentRoom]) return;
    const room = rooms[currentRoom];
    const player = room.players[socket.id];
    if (!player || player.hp > 0) return;
    player.hp = 100;
    player.spawnShieldUntil = Date.now() + 3000;
    console.log(`[Room ${currentRoom}] ${player.nickname} respawned with shield`);
    io.to(currentRoom).emit('player_respawned', {
      playerId: socket.id,
      nickname: player.nickname,
      hp: 100,
      shieldDuration: 3000
    });
  });

  socket.on('leave_room', () => {
    if (currentRoom && rooms[currentRoom]) {
      deleteRoom(currentRoom, 'Player left');
      currentRoom = null;
    }
  });

  socket.on('disconnect', (reason) => {
    console.log(`[Disconnect] ${socket.id}: ${reason}`);
    if (currentRoom && rooms[currentRoom]) {
      deleteRoom(currentRoom, 'Player disconnected');
      currentRoom = null;
    }
  });
});

app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    rooms: Object.keys(rooms).length,
    uptime: process.uptime()
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: Date.now() });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`AR Shooter Server running on port ${PORT}`);
});
