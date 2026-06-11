import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'socket_service.dart';

class ArGameScreen extends StatefulWidget {
  final String roomId;
  final String nickname;

  const ArGameScreen({
    super.key,
    required this.roomId,
    required this.nickname,
  });

  @override
  State<ArGameScreen> createState() => _ArGameScreenState();
}

class _ArGameScreenState extends State<ArGameScreen> with TickerProviderStateMixin {
  final SocketService _socket = SocketService();

  CameraController? _cameraController;
  bool _cameraReady = false;

  double _myLat = 0, _myLon = 0;
  double _rawHeading = 0;
  double _smoothHeading = 0;
  static const double _alpha = 0.15;

  int _myHp = 100;
  bool _isDead = false;
  bool _hasSpawnShield = false;
  Timer? _shieldTimer;

  String _gameState = 'LOBBY';
  int _countdown = 3;

  Map<String, dynamic> _opponents = {};

  bool _showShotFlash = false;
  bool _showHitFlash = false;
  Color _flashColor = Colors.transparent;

  int _myKills = 0;
  int _myDeaths = 0;

  final AudioPlayer _shotPlayer = AudioPlayer();
  final AudioPlayer _enemyShotPlayer = AudioPlayer();
  bool _audioLoaded = false;

  StreamSubscription? _compassSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _opponentsSub;
  StreamSubscription? _firedSub;
  StreamSubscription? _hitSub;
  StreamSubscription? _killedSub;
  StreamSubscription? _respawnedSub;
  StreamSubscription? _roomDeletedSub;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    await _initAudio();
    await _initCamera();
    _initCompass();
    _initGeolocator();
    _initSocketListeners();
  }

  Future<void> _initAudio() async {
    try {
      await _shotPlayer.setSource(AssetSource('sounds/gunshot.mp3'));
      await _shotPlayer.setVolume(1.0);
      await _enemyShotPlayer.setSource(AssetSource('sounds/gunshot.mp3'));
      await _enemyShotPlayer.setVolume(0.5);
      _audioLoaded = true;
    } catch (e) {
      debugPrint('[Audio] Failed to load: $e');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('[Camera] Init failed: $e');
    }
  }

  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        final raw = event.heading!;
        _rawHeading = raw;
        double delta = ((raw - _smoothHeading + 540) % 360) - 180;
        _smoothHeading = (_smoothHeading + _alpha * delta + 360) % 360;
        _sendPosition();
      }
    });
  }

  void _initGeolocator() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) return;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen((pos) {
      _myLat = pos.latitude;
      _myLon = pos.longitude;
      _sendPosition();
    });
  }

  void _sendPosition() {
    if (_gameState == 'PLAYING' || _gameState == 'COUNTDOWN') {
      _socket.updatePosition(_myLat, _myLon, _smoothHeading);
    }
  }

  void _initSocketListeners() {
    _stateSub = _socket.stateStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _gameState = data['state'] ?? 'LOBBY';
        if (data.containsKey('countdown')) {
          _countdown = data['countdown'];
        }
      });
    });

    _opponentsSub = _socket.opponentsStream.listen((data) {
      if (!mounted) return;
      setState(() => _opponents = data);
    });

    _firedSub = _socket.firedStream.listen((data) {
      if (!mounted) return;
      final shooterId = data['shooterId'];
      if (shooterId != _socket.socketId) {
        _playEnemyShot();
      }
    });

    _hitSub = _socket.hitStream.listen((data) {
      if (!mounted) return;
      final targetId = data['targetId'];
      final shooterId = data['shooterId'];
      if (targetId == _socket.socketId) {
        setState(() {
          _myHp = data['targetHp'] ?? _myHp;
        });
        _showHitEffect();
      } else if (shooterId == _socket.socketId) {
        _showShotEffect();
      }
    });

    _killedSub = _socket.killedStream.listen((data) {
      if (!mounted) return;
      final victimId = data['victimId'];
      final killerId = data['killerId'];
      if (victimId == _socket.socketId) {
        setState(() {
          _isDead = true;
          _myHp = 0;
          _myDeaths = data['victimDeaths'] ?? _myDeaths;
        });
      }
      if (killerId == _socket.socketId) {
        setState(() {
          _myKills = data['killerKills'] ?? _myKills;
        });
      }
    });

    _respawnedSub = _socket.respawnedStream.listen((data) {
      if (!mounted) return;
      final playerId = data['playerId'];
      if (playerId == _socket.socketId) {
        setState(() {
          _isDead = false;
          _myHp = 100;
          _hasSpawnShield = true;
        });
        _shieldTimer?.cancel();
        _shieldTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _hasSpawnShield = false);
        });
      }
    });

    _roomDeletedSub = _socket.roomDeletedStream.listen((reason) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room closed: $reason'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  void _playShot() async {
    if (!_audioLoaded) return;
    try {
      await _shotPlayer.stop();
      await _shotPlayer.seek(Duration.zero);
      await _shotPlayer.resume();
    } catch (e) {
      debugPrint('[Audio] Shot play error: $e');
    }
  }

  void _playEnemyShot() async {
    if (!_audioLoaded) return;
    try {
      await _enemyShotPlayer.stop();
      await _enemyShotPlayer.seek(Duration.zero);
      await _enemyShotPlayer.resume();
    } catch (e) {
      debugPrint('[Audio] Enemy shot play error: $e');
    }
  }

  void _showShotEffect() {
    setState(() {
      _showShotFlash = true;
      _flashColor = Colors.orange.withOpacity(0.3);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showShotFlash = false);
    });
  }

  void _showHitEffect() {
    setState(() {
      _showHitFlash = true;
      _flashColor = Colors.red.withOpacity(0.5);
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showHitFlash = false);
    });
  }

  void _onFire() {
    if (_gameState != 'PLAYING' || _isDead) return;
    _socket.fire(_smoothHeading);
    _playShot();
    _showShotEffect();
  }

  void _onRespawn() {
    _socket.respawn();
  }

  void _onQuitToMenu() {
    _socket.leaveRoom();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final toRad = (double d) => d * pi / 180;
    final toDeg = (double r) => r * 180 / pi;
    final dLon = toRad(lon2 - lon1);
    final y = sin(dLon) * cos(toRad(lat2));
    final x = cos(toRad(lat1)) * sin(toRad(lat2)) -
        sin(toRad(lat1)) * cos(toRad(lat2)) * cos(dLon);
    return (toDeg(atan2(y, x)) + 360) % 360;
  }

  double _shortestAngleDelta(double bearing, double heading) {
    return ((bearing - heading + 540) % 360) - 180;
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _opponentsSub?.cancel();
    _firedSub?.cancel();
    _hitSub?.cancel();
    _killedSub?.cancel();
    _respawnedSub?.cancel();
    _roomDeletedSub?.cancel();
    _shieldTimer?.cancel();
    _cameraController?.dispose();
    _shotPlayer.dispose();
    _enemyShotPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            _buildCameraPreview(),
            if (_gameState == 'PLAYING') ..._buildOpponentNameplates(),
            _buildHUD(),
            if (_showShotFlash || _showHitFlash) _buildFlashOverlay(),
            if (_gameState == 'COUNTDOWN') _buildCountdownOverlay(),
            if (_isDead) _buildDeathOverlay(),
            if (_hasSpawnShield && !_isDead) _buildShieldIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_cameraReady || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspect = _cameraController!.value.aspectRatio;
        final screenAspect = constraints.maxWidth / constraints.maxHeight;
        final scale = previewAspect > screenAspect
            ? constraints.maxHeight * previewAspect / constraints.maxWidth
            : constraints.maxWidth / (constraints.maxHeight * previewAspect);
        return Center(
          child: Transform.scale(
            scale: scale,
            child: CameraPreview(_cameraController!),
          ),
        );
      },
    );
  }

  List<Widget> _buildOpponentNameplates() {
    final List<Widget> widgets = [];
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    const fovDeg = 30.0;

    for (final entry in _opponents.entries) {
      final opp = entry.value;
      if (opp is! Map) continue;
      final oppLat = (opp['lat'] ?? 0).toDouble();
      final oppLon = (opp['lon'] ?? 0).toDouble();
      final oppNickname = opp['nickname'] ?? '???';
      final oppHp = (opp['hp'] ?? 100).toInt();
      final oppShield = opp['hasShield'] == true;

      if (oppLat == 0 && oppLon == 0) continue;

      final bearing = _calculateBearing(_myLat, _myLon, oppLat, oppLon);
      final delta = _shortestAngleDelta(bearing, _smoothHeading);

      if (delta.abs() > fovDeg) continue;

      final xNorm = (delta / fovDeg + 1) / 2;
      final xPos = xNorm * screenWidth - 70;
      final yPos = screenHeight * 0.35;

      widgets.add(
        Positioned(
          left: xPos.clamp(0, screenWidth - 140),
          top: yPos,
          child: Container(
            width: 140,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: oppShield ? Colors.cyanAccent : Colors.redAccent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (oppShield)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.shield, color: Colors.cyanAccent, size: 14),
                      ),
                    Flexible(
                      child: Text(
                        oppNickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: oppHp / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade800,
                      valueColor: AlwaysStoppedAnimation(
                        oppHp > 50
                            ? Colors.greenAccent
                            : oppHp > 25
                                ? Colors.orangeAccent
                                : Colors.redAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$oppHp HP',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildHUD() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nickname,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                          ),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 14,
                            width: constraints.maxWidth * 0.4,
                            child: LinearProgressIndicator(
                              value: _myHp / 100,
                              backgroundColor: Colors.grey.shade900,
                              valueColor: AlwaysStoppedAnimation(
                                _myHp > 50
                                    ? Colors.greenAccent
                                    : _myHp > 25
                                        ? Colors.orangeAccent
                                        : Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_myHp HP',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'K: $_myKills  D: $_myDeaths',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Room: ${widget.roomId}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_smoothHeading.toStringAsFixed(0)}°',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (_gameState == 'PLAYING' && !_isDead)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildFireButton(constraints),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.white70, size: 28),
                onPressed: _onQuitToMenu,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _buildCrosshair(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFireButton(BoxConstraints constraints) {
    final size = constraints.maxWidth * 0.2;
    return GestureDetector(
      onTap: _onFire,
      child: Container(
        width: size.clamp(60.0, 100.0),
        height: size.clamp(60.0, 100.0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.red.shade400,
              Colors.red.shade800,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.5),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: Colors.white30, width: 3),
        ),
        child: const Center(
          child: Icon(Icons.gps_fixed, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  Widget _buildCrosshair() {
    return IgnorePointer(
      child: SizedBox(
        width: 60,
        height: 60,
        child: CustomPaint(painter: _CrosshairPainter()),
      ),
    );
  }

  Widget _buildFlashOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _flashColor,
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_countdown',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'GET READY!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeathOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dangerous, color: Colors.redAccent, size: 80),
              const SizedBox(height: 16),
              const Text(
                'YOU DIED',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _onRespawn,
                icon: const Icon(Icons.refresh),
                label: const Text('RESPAWN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.shade700,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _onQuitToMenu,
                child: const Text(
                  'QUIT TO MENU',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShieldIndicator() {
    return Positioned(
      top: 70,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.cyanAccent, width: 1.5),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, color: Colors.cyanAccent, size: 20),
              SizedBox(width: 6),
              Text(
                'SPAWN SHIELD',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3;

    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(
      Offset(center.dx - radius - 6, center.dy),
      Offset(center.dx - radius + 6, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + radius - 6, center.dy),
      Offset(center.dx + radius + 6, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius - 6),
      Offset(center.dx, center.dy - radius + 6),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + radius - 6),
      Offset(center.dx, center.dy + radius + 6),
      paint,
    );

    final dotPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
