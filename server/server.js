const http = require('http');
const crypto = require('crypto');
const { Server } = require('socket.io');

function envBool(n){ const v=(process.env[n]||'').toLowerCase(); return v==='1'||v==='true'||v==='yes'||v==='on'; }
function envNum(n,d){ const v=Number(process.env[n]); return Number.isFinite(v)&&v>0?v:d; }

const NORMAL_RANGE=envNum('HIT_RANGE_M',80), NORMAL_ANGLE=envNum('HIT_ANGLE_DEG',12);
const TEST_RANGE=envNum('TEST_RANGE_M',300),  TEST_ANGLE=envNum('TEST_ANGLE_DEG',45);
const INITIAL_MODE=envBool('IGNORE_AIM')||envBool('THROUGH_WALLS')?'walls':envBool('TEST_MODE')?'test':'normal';
const MAX_HP=100, HIT_DAMAGE=25, COUNTDOWN_SECONDS=3, RESPAWN_MS=4000;

function presetFor(m){
  if(m==='walls') return {mode:'walls',ignoreAim:true, rangeM:TEST_RANGE, angleDeg:TEST_ANGLE};
  if(m==='test')  return {mode:'test', ignoreAim:false,rangeM:TEST_RANGE, angleDeg:TEST_ANGLE};
  return               {mode:'normal',ignoreAim:false,rangeM:NORMAL_RANGE,angleDeg:NORMAL_ANGLE};
}

const httpServer=http.createServer((_,res)=>{ res.writeHead(200,{'Content-Type':'text/plain'}); res.end('ARGEYM VPS ONLINE'); });
const io=new Server(httpServer,{cors:{origin:'*',methods:['GET','POST']}});
const rooms={};

function genId(){ return crypto.randomBytes(3).toString('hex').toUpperCase(); }
function angDist(a,b){ let d=Math.abs(a-b)%360; return d>180?360-d:d; }
function toRad(d){ return d*Math.PI/180; }
function toDeg(r){ return r*180/Math.PI; }
function bearing(la1,lo1,la2,lo2){
  const dL=toRad(lo2-lo1), y=Math.sin(dL)*Math.cos(toRad(la2));
  const x=Math.cos(toRad(la1))*Math.sin(toRad(la2))-Math.sin(toRad(la1))*Math.cos(toRad(la2))*Math.cos(dL);
  return(toDeg(Math.atan2(y,x))+360)%360;
}
function haversine(la1,lo1,la2,lo2){
  const R=6371000,dLa=toRad(la2-la1),dLo=toRad(lo2-lo1);
  const a=Math.sin(dLa/2)**2+Math.cos(toRad(la1))*Math.cos(toRad(la2))*Math.sin(dLo/2)**2;
  return R*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}
function newP(id,name){ return {id,name,hp:MAX_HP,ready:false,alive:true,kills:0,deaths:0,lat:null,lng:null,heading:0,hasGps:false}; }
function opp(room,id){ return room.players.find(p=>p.id!==id)||null; }
function fp(room,id){  return room.players.find(p=>p.id===id)||null; }
function pub(room){ return room.players.map(p=>({id:p.id,name:p.name,ready:p.ready,kills:p.kills,deaths:p.deaths})); }
function emitLobby(rid){ const r=rooms[rid]; if(r) io.to(rid).emit('lobby_update',{roomId:rid,players:pub(r)}); }
function emitMode(rid){  const r=rooms[rid]; if(r) io.to(rid).emit('room_mode',r.config); }

function runCountdown(rid){
  io.to(rid).emit('start_countdown',{});
  let c=COUNTDOWN_SECONDS;
  const tick=()=>{ if(!rooms[rid]) return;
    if(c>0){ io.to(rid).emit('countdown',{count:c}); c--; setTimeout(tick,1000); }
    else{ io.to(rid).emit('countdown',{count:0}); setTimeout(()=>{ if(rooms[rid]) io.to(rid).emit('game_start',{}); },1000); }
  }; tick();
}

function endGame(socket,reason){
  const room=rooms[socket.data.roomId]; if(!room) return;
  socket.to(room.id).emit('game_ended',{reason});
  room.players=room.players.filter(p=>p.id!==socket.id);
  if(room.players.length===0) delete rooms[room.id];
  else{ room.started=false; room.players.forEach(p=>p.ready=false); emitLobby(room.id); }
}

io.on('connection',socket=>{
  socket.on('host_room',payload=>{
    let rid=genId(); while(rooms[rid]) rid=genId();
    const name=payload?.name?String(payload.name).slice(0,16):'HOST';
    rooms[rid]={id:rid,started:false,players:[newP(socket.id,name)],config:presetFor(INITIAL_MODE)};
    socket.join(rid); socket.data.roomId=rid;
    socket.emit('room_created',{roomId:rid}); emitLobby(rid); emitMode(rid);
  });
  socket.on('join_room',payload=>{
    const rid=payload?.roomId?String(payload.roomId).toUpperCase():'';
    const name=payload?.name?String(payload.name).slice(0,16):'PLAYER';
    const room=rooms[rid];
    if(!room){ socket.emit('join_error',{message:'INVALID ROOM'}); return; }
    if(room.players.length>=2){ socket.emit('join_error',{message:'ROOM FULL'}); return; }
    room.players.push(newP(socket.id,name));
    socket.join(rid); socket.data.roomId=rid;
    socket.emit('room_joined',{roomId:rid}); socket.to(rid).emit('opponent_joined',{id:socket.id,name});
    emitLobby(rid); emitMode(rid);
  });
  socket.on('set_room_mode',payload=>{
    const room=rooms[socket.data.roomId]; if(!room) return;
    const m=payload?.mode||''; if(!['normal','test','walls'].includes(m)) return;
    room.config=presetFor(m); emitMode(room.id);
  });
  socket.on('player_ready',payload=>{
    const room=rooms[socket.data.roomId]; if(!room) return;
    const player=fp(room,socket.id); if(!player) return;
    player.ready=!!(payload?.ready===true); emitLobby(room.id);
    if(room.players.length===2&&room.players.every(p=>p.ready)&&!room.started){ room.started=true; runCountdown(room.id); }
  });
  socket.on('telemetry',payload=>{
    const room=rooms[socket.data.roomId]; if(!room) return;
    const player=fp(room,socket.id); if(!player) return;
    if(typeof payload?.heading==='number') player.heading=payload.heading;
    if(typeof payload?.lat==='number'&&typeof payload?.lng==='number'){ player.lat=payload.lat; player.lng=payload.lng; player.hasGps=true; }
    const o=opp(room,socket.id);
    if(o) io.to(o.id).emit('opponent_telemetry',{id:player.id,name:player.name,heading:player.heading,lat:player.lat,lng:player.lng,hasGps:player.hasGps,hp:player.hp,alive:player.alive});
  });
  socket.on('shoot',payload=>{
    const room=rooms[socket.data.roomId]; if(!room||!room.started) return;
    const shooter=fp(room,socket.id),victim=opp(room,socket.id);
    if(!shooter||!victim||!shooter.alive||!victim.alive) return;
    const cfg=room.config||presetFor(INITIAL_MODE);
    const sh=typeof payload?.heading==='number'?payload.heading:shooter.heading;
    if(typeof payload?.lat==='number') shooter.lat=payload.lat;
    if(typeof payload?.lng==='number') shooter.lng=payload.lng;
    let hit=false,info={};
    if(cfg.ignoreAim){ hit=true; info={mode:'walls'}; }
    else if(shooter.hasGps&&victim.hasGps&&shooter.lat!==null&&victim.lat!==null){
      const b=bearing(shooter.lat,shooter.lng,victim.lat,victim.lng);
      const d=haversine(shooter.lat,shooter.lng,victim.lat,victim.lng);
      const delta=angDist(sh,b); hit=d<=cfg.rangeM&&delta<=cfg.angleDeg; info={mode:cfg.mode,delta,distance:d};
    } else { const f=angDist(angDist(sh,victim.heading),180); hit=f<=cfg.angleDeg; info={mode:'compass',delta:f}; }
    if(!hit){ socket.emit('shot_missed',info); return; }
    socket.emit('hit_confirmed',info);
    victim.hp=Math.max(0,victim.hp-HIT_DAMAGE);
    io.to(victim.id).emit('hit_taken',{hp:victim.hp});
    if(victim.hp<=0){
      victim.alive=false; shooter.kills++; victim.deaths++;
      io.to(room.id).emit('fragged',{killer:shooter.id,killerName:shooter.name,victim:victim.id,victimName:victim.name,kills:shooter.kills,respawnMs:RESPAWN_MS});
      io.to(room.id).emit('score',{players:pub(room)});
      const vid=victim.id,rid=room.id;
      setTimeout(()=>{ const r=rooms[rid]; if(!r) return; const v=fp(r,vid); if(!v) return;
        v.hp=MAX_HP; v.alive=true; io.to(vid).emit('respawn',{hp:MAX_HP}); },RESPAWN_MS);
    }
  });
  socket.on('leave_game',()=>endGame(socket,'OPPONENT LEFT'));
  socket.on('disconnect',()=>endGame(socket,'OPPONENT DISCONNECTED'));
});

const PORT=process.env.PORT||3001;
httpServer.listen(PORT,()=>console.log('ARGEYM VPS on port '+PORT));
