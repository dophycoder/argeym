import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'socket_service.dart';
import 'ar_game.dart';

const String serverUrl = 'http://185.216.71.84:3001';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ArShooterApp());
}

class ArShooterApp extends StatelessWidget {
  const ArShooterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Shooter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        colorSchemeSeed: Colors.cyanAccent,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const MainMenuScreen(),
    );
  }
}

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> with SingleTickerProviderStateMixin {
  final SocketService _socket = SocketService();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  bool _isConnecting = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadNickname();
    _requestPermissions();
    _connectSocket();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString('nickname');
    if (saved == null || saved.isEmpty) {
      saved = 'brenton_${Random().nextInt(9999)}';
      await prefs.setString('nickname', saved);
    }
    _nicknameController.text = saved;
  }

  Future<void> _saveNickname() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', _nicknameController.text.trim());
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.location,
      Permission.microphone,
    ].request();
  }

  void _connectSocket() {
    _socket.connect(serverUrl);
    _socket.errorStream.listen((error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _isConnecting = false);
    });
  }

  void _createRoom() async {
    if (_isConnecting) return;
    await _saveNickname();
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    setState(() => _isConnecting = true);
    _socket.createRoom(nickname, (response) {
      setState(() => _isConnecting = false);
      if (response['success'] == true) {
        final roomId = response['roomId'];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LobbyScreen(
              roomId: roomId,
              nickname: nickname,
              isHost: true,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${response['error'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });
  }

  void _joinRoom(String roomId) async {
    if (_isConnecting) return;
    await _saveNickname();
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty || roomId.isEmpty) return;

    setState(() => _isConnecting = true);
    _socket.joinRoom(roomId, nickname, (response) {
      setState(() => _isConnecting = false);
      if (response['success'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LobbyScreen(
              roomId: response['roomId'],
              nickname: nickname,
              isHost: false,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${response['error'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    });
  }

  void _joinViaManualInput() {
    final roomId = _roomIdController.text.trim().toUpperCase();
    if (roomId.isEmpty) return;
    _joinRoom(roomId);
  }

  void _joinViaQrScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrScanScreen(onScanned: (code) {
          Navigator.pop(context);
          _joinRoom(code);
        }),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _nicknameController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 1),
                      ScaleTransition(
                        scale: _pulseAnimation,
                        child: const Icon(
                          Icons.gps_fixed,
                          size: 80,
                          color: Colors.cyanAccent,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.cyanAccent, Colors.purpleAccent],
                        ).createShader(bounds),
                        child: const Text(
                          'AR SHOOTER',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AUGMENTED REALITY COMBAT',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          letterSpacing: 3,
                        ),
                      ),
                      const Spacer(flex: 1),
                      _buildTextField(
                        controller: _nicknameController,
                        label: 'NICKNAME',
                        icon: Icons.person,
                      ),
                      const SizedBox(height: 20),
                      _buildPrimaryButton(
                        label: 'HOST GAME',
                        icon: Icons.add_circle_outline,
                        onTap: _createRoom,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _roomIdController,
                              label: 'ROOM CODE',
                              icon: Icons.tag,
                              capitalization: TextCapitalization.characters,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildIconButton(
                            icon: Icons.arrow_forward,
                            onTap: _joinViaManualInput,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildSecondaryButton(
                        label: 'SCAN QR TO JOIN',
                        icon: Icons.qr_code_scanner,
                        onTap: _joinViaQrScan,
                      ),
                      const Spacer(flex: 2),
                      if (_isConnecting)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: CircularProgressIndicator(color: Colors.cyanAccent),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _socket.isConnected ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _socket.isConnected ? 'Connected to Server' : 'Connecting...',
                              style: TextStyle(
                                color: _socket.isConnected ? Colors.white38 : Colors.redAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: capitalization,
        style: const TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 2),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [Colors.cyanAccent.shade700, Colors.cyan.shade900],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1.5),
            color: Colors.cyanAccent.withOpacity(0.05),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [Colors.cyanAccent.shade700, Colors.cyan.shade900],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class LobbyScreen extends StatefulWidget {
  final String roomId;
  final String nickname;
  final bool isHost;

  const LobbyScreen({
    super.key,
    required this.roomId,
    required this.nickname,
    required this.isHost,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final SocketService _socket = SocketService();
  List<Map<String, dynamic>> _players = [];

  @override
  void initState() {
    super.initState();
    _socket.lobbyStream.listen((data) {
      if (!mounted) return;
      final players = data['players'];
      if (players is List) {
        setState(() {
          _players = players.map((p) => Map<String, dynamic>.from(p)).toList();
        });
      }
    });
    _socket.stateStream.listen((data) {
      if (!mounted) return;
      final state = data['state'];
      if (state == 'COUNTDOWN' || state == 'PLAYING') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ArGameScreen(
              roomId: widget.roomId,
              nickname: widget.nickname,
            ),
          ),
        );
      }
    });
    _socket.roomDeletedStream.listen((reason) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'GAME LOBBY',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'ROOM CODE',
                          style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.roomId,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: constraints.maxWidth * 0.5,
                          height: constraints.maxWidth * 0.5,
                          child: QrImageView(
                            data: widget.roomId,
                            version: QrVersions.auto,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Share this code or QR with your opponent',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PLAYERS',
                      style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _players.length,
                      itemBuilder: (context, index) {
                        final p = _players[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person, color: Colors.cyanAccent, size: 22),
                              const SizedBox(width: 12),
                              Text(
                                p['nickname'] ?? '???',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (index == 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.cyanAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'HOST',
                                    style: TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        Text(
                          _players.length < 2
                              ? 'Waiting for opponent to join...'
                              : 'Starting game...',
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        if (_players.length < 2)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                              strokeWidth: 2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _socket.leaveRoom();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white54, size: 18),
                    label: const Text(
                      'LEAVE LOBBY',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class QrScanScreen extends StatefulWidget {
  final Function(String) onScanned;

  const QrScanScreen({super.key, required this.onScanned});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scanController = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Room QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scanController,
            onDetect: (capture) {
              if (_scanned) return;
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final code = barcode.rawValue;
                if (code != null && code.isNotEmpty) {
                  _scanned = true;
                  widget.onScanned(code.trim().toUpperCase());
                  break;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.cyanAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              'Point at the QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
