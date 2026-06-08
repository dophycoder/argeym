import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// --- ENTRYPOINT ---
List<CameraDescription> gCameras = <CameraDescription>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    gCameras = await availableCameras();
  } catch (_) {
    gCameras = <CameraDescription>[];
  }
  runApp(const ARShooterApp());
}

// --- ROOT WIDGET ---
class ARShooterApp extends StatelessWidget {
  const ARShooterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARGEYM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const LobbyScreen(),
    );
  }
}

// --- NETWORK SERVICE ---
class NetworkService {
  NetworkService._internal();
  static final NetworkService instance = NetworkService._internal();
  static const String serverUrl = 'http://185.216.71.84:3001';
  IO.Socket? socket;

  IO.Socket connect() {
    final IO.Socket? existing = socket;
    if (existing != null) {
      if (!existing.connected) {
        existing.connect();
      }
      return existing;
    }
    final IO.Socket created = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(<String>['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(1000000)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .disableAutoConnect()
          .build(),
    );
    socket = created;
    created.connect();
    return created;
  }

  void dispose() {
    socket?.dispose();
    socket = null;
  }
}

// --- HEADING SERVICE ---
class HeadingService {
  StreamSubscription<MagnetometerEvent>? _magSub;
  double heading = 0.0;

  void start() {
    _magSub = magnetometerEventStream().listen((MagnetometerEvent e) {
      final double angle = atan2(e.y, e.x) * 180 / pi;
      heading = (angle + 360) % 360;
    });
  }

  void stop() {
    _magSub?.cancel();
    _magSub = null;
  }
}

// --- LOBBY SCREEN ---
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final NetworkService _net = NetworkService.instance;
  late final IO.Socket _socket;
  String? _roomId;
  bool _isHost = false;
  bool _selfReady = false;
  bool _opponentPresent = false;
  bool _scanning = false;
  String _status = 'IDLE';

  @override
  void initState() {
    super.initState();
    _socket = _net.connect();
    _bind();
  }

  void _bind() {
    _socket.onConnect((_) => _setStatus('CONNECTED'));
    _socket.onConnectError((_) => _setStatus('CONNECTION ERROR'));
    _socket.onReconnect((_) => _setStatus('RECONNECTED'));
    _socket.onDisconnect((_) => _setStatus('RECONNECTING'));

    _socket.on('room_created', (dynamic data) {
      if (!mounted) return;
      setState(() {
        _roomId = (data as Map)['roomId'].toString();
        _isHost = true;
        _status = 'WAITING FOR PLAYER';
      });
    });

    _socket.on('room_joined', (dynamic data) {
      if (!mounted) return;
      setState(() {
        _roomId = (data as Map)['roomId'].toString();
        _opponentPresent = true;
        _status = 'JOINED ROOM';
      });
    });

    _socket.on('opponent_joined', (_) {
      if (!mounted) return;
      setState(() {
        _opponentPresent = true;
        _status = 'PLAYER CONNECTED';
      });
    });

    _socket.on('join_error', (dynamic data) {
      if (!mounted) return;
      final String message =
          (data is Map && data['message'] != null) ? data['message'].toString() : 'INVALID ROOM';
      setState(() {
        _status = message;
        _scanning = false;
      });
    });

    _socket.on('start_countdown', (_) => _goToGame());
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  void _host() => _socket.emit('host_room');

  void _toggleReady() {
    if (_roomId == null) return;
    setState(() => _selfReady = !_selfReady);
    _socket.emit('player_ready', <String, dynamic>{
      'roomId': _roomId,
      'ready': _selfReady,
    });
  }

  void _onScan(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final String? code = capture.barcodes.first.rawValue;
    if (code == null || code.trim().isEmpty) {
      setState(() => _status = 'INVALID QR CODE');
      return;
    }
    setState(() => _scanning = false);
    _socket.emit('join_room', <String, dynamic>{'roomId': code.trim()});
  }

  void _goToGame() {
    final String? roomId = _roomId;
    if (roomId == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameplayScreen(socket: _socket, roomId: roomId, isHost: _isHost),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ARGEYM LOBBY')),
      body: _scanning ? _buildScanner() : _buildLobby(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: <Widget>[
        MobileScanner(onDetect: _onScan),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ElevatedButton(
              onPressed: () => setState(() => _scanning = false),
              child: const Text('CANCEL'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLobby() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('STATUS: $_status', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            if (_roomId == null) ...<Widget>[
              ElevatedButton(onPressed: _host, child: const Text('HOST ROOM')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _scanning = true),
                child: const Text('JOIN ROOM'),
              ),
            ] else ...<Widget>[
              if (_isHost)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(data: _roomId!, size: 220),
                ),
              const SizedBox(height: 12),
              SelectableText(
                'ROOM: $_roomId',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_opponentPresent ? 'OPPONENT READY TO SYNC' : 'AWAITING OPPONENT'),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selfReady ? Colors.green : Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                ),
                onPressed: _toggleReady,
                child: Text(_selfReady ? 'READY' : 'TAP TO READY'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- GAME PHASES ---
enum GamePhase { countdown, active, gameOver }

// --- GAMEPLAY SCREEN ---
class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, required this.socket, required this.roomId, required this.isHost});
  final IO.Socket socket;
  final String roomId;
  final bool isHost;
  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  CameraController? _camera;
  final HeadingService _heading = HeadingService();
  GamePhase _phase = GamePhase.countdown;
  String _countdownLabel = '3';
  static const int _maxAmmo = 30;
  int _ammo = _maxAmmo;
  int _hp = 100;
  bool _reloading = false;
  double _orangeFlash = 0.0;
  double _redFlash = 0.0;
  String _result = '';

  @override
  void initState() {
    super.initState();
    _heading.start();
    _bind();
    _initCamera();
    _calibrate();
  }

  Future<void> _initCamera() async {
    if (gCameras.isEmpty) return;
    final CameraDescription rear = gCameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => gCameras.first,
    );
    final CameraController controller =
        CameraController(rear, ResolutionPreset.high, enableAudio: false);
    try {
      await controller.initialize();
    } catch (_) {
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _camera = controller);
  }

  void _calibrate() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      widget.socket.emit('calibrate', <String, dynamic>{
        'roomId': widget.roomId,
        'heading': _heading.heading,
      });
    });
  }

  void _bind() {
    widget.socket.on('countdown', (dynamic data) {
      if (!mounted) return;
      final int c = (data is Map && data['count'] != null) ? (data['count'] as num).toInt() : 0;
      setState(() {
        _phase = GamePhase.countdown;
        _countdownLabel = c > 0 ? c.toString() : "LET'S GO!";
      });
    });
    widget.socket.on('game_start', (_) {
      if (!mounted) return;
      setState(() => _phase = GamePhase.active);
    });
    widget.socket.on('hit_confirmed', (_) => _flashOrange());
    widget.socket.on('hit_taken', (dynamic data) {
      if (!mounted) return;
      final int hp = (data is Map && data['hp'] != null) ? (data['hp'] as num).toInt() : _hp;
      setState(() => _hp = hp);
      _flashRed();
    });
    widget.socket.on('game_over', (dynamic data) {
      if (!mounted) return;
      final bool win = data is Map && data['winner'] == widget.socket.id;
      setState(() {
        _phase = GamePhase.gameOver;
        _result = win ? 'VICTORY' : 'DEFEAT';
      });
    });
    widget.socket.on('opponent_disconnected', (_) {
      if (!mounted || _phase == GamePhase.gameOver) return;
      setState(() {
        _phase = GamePhase.gameOver;
        _result = 'OPPONENT LEFT';
      });
    });
  }

  void _flashOrange() {
    if (!mounted) return;
    setState(() => _orangeFlash = 0.30);
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _orangeFlash = 0.0);
    });
  }

  void _flashRed() {
    if (!mounted) return;
    setState(() => _redFlash = 0.50);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _redFlash = 0.0);
    });
  }

  void _shoot() {
    if (_phase != GamePhase.active || _reloading || _ammo <= 0) return;
    setState(() => _ammo -= 1);
    widget.socket.emit('shoot', <String, dynamic>{
      'roomId': widget.roomId,
      'heading': _heading.heading,
    });
  }

  void _reload() {
    if (_phase != GamePhase.active || _reloading) return;
    setState(() => _reloading = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _ammo = _maxAmmo;
        _reloading = false;
      });
    });
  }

  @override
  void dispose() {
    _heading.stop();
    _camera?.dispose();
    widget.socket.off('countdown');
    widget.socket.off('game_start');
    widget.socket.off('hit_confirmed');
    widget.socket.off('hit_taken');
    widget.socket.off('game_over');
    widget.socket.off('opponent_disconnected');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? cam = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (cam != null && cam.value.isInitialized)
            CameraPreview(cam)
          else
            const ColoredBox(color: Colors.black),
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              color: Colors.orange.withOpacity(_orangeFlash),
            ),
          ),
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              color: Colors.red.withOpacity(_redFlash),
            ),
          ),
          if (_phase == GamePhase.active) _buildCrosshair(),
          if (_phase == GamePhase.active) _buildHud(),
          if (_phase == GamePhase.countdown) _buildCountdown(),
          if (_phase == GamePhase.gameOver) _buildGameOver(),
        ],
      ),
    );
  }

  Widget _buildCrosshair() {
    return const Center(child: Icon(Icons.add, color: Colors.greenAccent, size: 64));
  }

  Widget _buildHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: <Widget>[
            Align(alignment: Alignment.topLeft, child: _badge('HP  $_hp')),
            Align(alignment: Alignment.topRight, child: _badge('AMMO  $_ammo/$_maxAmmo')),
            Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _actionButton('SHOOT', Colors.redAccent, _shoot),
                  _actionButton(_reloading ? 'RELOADING' : 'RELOAD', Colors.blueAccent, _reload),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      ),
      child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCountdown() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Text(
          _countdownLabel,
          style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_result, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const LobbyScreen()),
                (Route<dynamic> route) => false,
              ),
              child: const Text('RETURN TO LOBBY'),
            ),
          ],
        ),
      ),
    );
  }
}
