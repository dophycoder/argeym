# AR Shooter (ARGEYM)

Cross-platform AR Shooter game built with Flutter + Node.js/Socket.io.

## Architecture

```
├── server/          # Node.js game server (Socket.io)
│   ├── server.js    # Game logic, hit validation, room management
│   └── package.json
├── client/          # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart           # Menu, Lobby, QR screens
│   │   ├── socket_service.dart # Network layer
│   │   └── ar_game.dart        # Camera, Sensors, HUD, Gameplay
│   └── pubspec.yaml
└── .github/workflows/build.yml # CI/CD
```

## Server Setup (VPS)

```bash
cd /opt/argeym
npm install
pm2 start server.js --name argeym
```

## Game Mechanics
- **Matchmaking**: Host creates room → share QR/code → opponent joins
- **AR Combat**: Camera + compass + GPS for real-world targeting
- **Hit Validation**: Server-side Haversine distance + bearing angle check
- **Spawn Shield**: 3s invulnerability after respawn
