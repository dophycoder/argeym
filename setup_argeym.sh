#!/usr/bin/env bash
set -e

# --- DIRECTORY SCAFFOLD ---
mkdir -p ios/Runner
mkdir -p lib
mkdir -p server
mkdir -p .github/workflows

# --- FLUTTER MANIFEST ---
cat << 'PUBSPEC_EOF' > pubspec.yaml
name: argeym
description: Cross-platform AR shooter built on Flutter and a Node.js VPS.
publish_to: 'none'
version: 1.3.0+4

environment:
sdk: '>=3.0.0 <4.0.0'

dependencies:
flutter:
sdk: flutter
socket_io_client: ^2.0.3+1
camera: ^0.10.5+9
qr_flutter: ^4.1.0
mobile_scanner: ^3.5.6
flutter_compass: ^0.8.0
geolocator: ^11.0.0
shared_preferences: ^2.2.2
cupertino_icons: ^1.0.6

dev_dependencies:
flutter_test:
sdk: flutter

flutter:
uses-material-design: true
PUBSPEC_EOF

# --- IOS INFO PLIST ---
cat << 'PLIST_EOF' > ios/Runner/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleDevelopmentRegion</key>
<string>$(DEVELOPMENT_LANGUAGE)</string>
<key>CFBundleDisplayName</key>
<string>Argeym</string>
<key>CFBundleExecutable</key>
<string>$(EXECUTABLE_NAME)</string>
<key>CFBundleIdentifier</key>
<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundleName</key>
<string>argeym</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleShortVersionString</key>
<string>$(FLUTTER_BUILD_NAME)</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>$(FLUTTER_BUILD_NUMBER)</string>
<key>LSRequiresIPhoneOS</key>
<true/>
<key>NSCameraUsageDescription</key>
<string>Argeym uses the rear camera to render the live augmented-reality battlefield and align targets in real time.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Argeym uses your location to measure the real-world distance and bearing to your opponent for hit detection.</string>
<key>UILaunchStoryboardName</key>
<string>LaunchScreen</string>
<key>UIMainStoryboardFile</key>
<string>Main</string>
<key>UISupportedInterfaceOrientations</key>
<array>
<string>UIInterfaceOrientationPortrait</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
<string>UIInterfaceOrientationPortrait</string>
</array>
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
<key>UIApplicationSupportsIndirectInputEvents</key>
<true/>
</dict>
</plist>
PLIST_EOF

# --- FLUTTER APPLICATION ---
cat << 'DART_EOF' > lib/main.dart
import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

// --- HIT MODES (kept in sync with server) ---
class HitMode {
static const String normal = 'normal';
static const String test = 'test';
static const String walls = 'walls';
}

String modeLabel(String m, double range, double angle) {
switch (m) {
case HitMode.walls:
return 'WALLS • hit anywhere';
case HitMode.test:
return 'TEST • ${range.toStringAsFixed(0)}m / ${angle.toStringAsFixed(0)}°';
default:
return 'NORMAL • ${range.toStringAsFixed(0)}m / ${angle.toStringAsFixed(0)}°';
}
}

IconData modeIcon(String m) {
switch (m) {
case HitMode.walls:
return Icons.layers_clear;
case HitMode.test:
return Icons.science;
default:
return Icons.verified;
}
}

Color modeColor(String m) {
switch (m) {
case HitMode.walls:
return const Color(0xFFFF4D5E);
case HitMode.test:
return const Color(0xFFFFC93C);
default:
return const Color(0xFF27E6A4);
}
}

// --- THEME ---
class C {
static const Color bg = Color(0xFF0B0F14);
static const Color panel = Color(0xFF161E29);
static const Color panel2 = Color(0xFF1F2A38);
static const Color accent = Color(0xFF27E6A4);
static const Color danger = Color(0xFFFF4D5E);
static const Color warn = Color(0xFFFFC93C);
static const Color muted = Color(0xFF8A97A6);
}

// --- ROOT WIDGET ---
class ARShooterApp extends StatelessWidget {
const ARShooterApp({super.key});
@override
Widget build(BuildContext context) {
final ThemeData base = ThemeData.dark(useMaterial3: true);
return MaterialApp(
title: 'ARGEYM',
debugShowCheckedModeBanner: false,
theme: base.copyWith(
scaffoldBackgroundColor: C.bg,
colorScheme: base.colorScheme.copyWith(
primary: C.accent,
secondary: C.accent,
surface: C.panel,
),
appBarTheme: const AppBarTheme(
backgroundColor: Colors.transparent,
elevation: 0,
centerTitle: true,
),
elevatedButtonTheme: ElevatedButtonThemeData(
style: ElevatedButton.styleFrom(
backgroundColor: C.accent,
foregroundColor: Colors.black,
padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.1),
),
),
),
home: const HomeScreen(),
);
}
}

// --- PERSISTENT PREFS ---
class Prefs {
static const String _kName = 'callsign';
static Future<String> loadName() async {
final SharedPreferences sp = await SharedPreferences.getInstance();
return sp.getString(_kName) ?? '';
}
static Future<void> saveName(String name) async {
final SharedPreferences sp = await SharedPreferences.getInstance();
await sp.setString(_kName, name);
}
}

// --- GEOMETRY HELPERS ---
double _deg2rad(double d) => d * pi / 180.0;
double _rad2deg(double r) => r * 180.0 / pi;

double bearingBetween(double lat1, double lon1, double lat2, double lon2) {
final double dLon = _deg2rad(lon2 - lon1);
final double y = sin(dLon) * cos(_deg2rad(lat2));
final double x = cos(_deg2rad(lat1)) * sin(_deg2rad(lat2)) -
sin(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * cos(dLon);
return (_rad2deg(atan2(y, x)) + 360) % 360;
}

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
const double r = 6371000.0;
final double dLat = _deg2rad(lat2 - lat1);
final double dLon = _deg2rad(lon2 - lon1);
final double a = sin(dLat / 2) * sin(dLat / 2) +
cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double normalizeSigned(double a) {
double d = (a + 180) % 360;
if (d < 0) d += 360;
return d - 180;
}

String prettyDistance(double m) {
if (m < 1000) return '${m.toStringAsFixed(m < 10 ? 1 : 0)} m';
return '${(m / 1000).toStringAsFixed(2)} km';
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

// --- SENSOR SERVICE (compass + GPS) ---
class SensorService {
StreamSubscription<CompassEvent>? _compassSub;
StreamSubscription<Position>? _posSub;
double heading = 0.0;
double? lat;
double? lng;
bool gpsReady = false;
bool gpsDenied = false;

Future<void> start() async {
final Stream<CompassEvent>? stream = FlutterCompass.events;
if (stream != null) {
_compassSub = stream.listen((CompassEvent event) {
final double? h = event.heading;
if (h != null) heading = (h + 360) % 360;
});
}
await _initGps();
}

Future<void> _initGps() async {
try {
LocationPermission perm = await Geolocator.checkPermission();
if (perm == LocationPermission.denied) {
perm = await Geolocator.requestPermission();
}
if (perm == LocationPermission.denied ||
perm == LocationPermission.deniedForever) {
gpsDenied = true;
return;
}
final bool enabled = await Geolocator.isLocationServiceEnabled();
if (!enabled) return;
posSub = Geolocator.getPositionStream(
locationSettings: const LocationSettings(
accuracy: LocationAccuracy.bestForNavigation,
distanceFilter: 0,
),
).listen((Position p) {
lat = p.latitude;
lng = p.longitude;
gpsReady = true;
});
} catch () {}
}

void stop() {
_compassSub?.cancel();
_posSub?.cancel();
_compassSub = null;
_posSub = null;
}
}

// --- HOME / MENU SCREEN ---
class HomeScreen extends StatefulWidget {
const HomeScreen({super.key});
@override
State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
final TextEditingController _ctrl = TextEditingController();
bool _saved = false;

@override
void initState() {
super.initState();
_load();
}

Future<void> _load() async {
final String n = await Prefs.loadName();
if (!mounted) return;
setState(() {
_ctrl.text = n;
_saved = n.isNotEmpty;
});
}

Future<void> _save() async {
final String n = _ctrl.text.trim();
if (n.isEmpty) return;
await Prefs.saveName(n);
FocusScope.of(context).unfocus();
setState(() => _saved = true);
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Callsign saved'), duration: Duration(seconds: 1)),
);
}

void _play() {
final String n = ctrl.text.trim();
if (n.isEmpty) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('Enter a callsign first')),
);
return;
}
Prefs.saveName(n);
Navigator.of(context).push(
MaterialPageRoute<void>(builder: () => LobbyScreen(callsign: n)),
);
}

@override
Widget build(BuildContext context) {
return Scaffold(
body: SafeArea(
child: Center(
child: SingleChildScrollView(
padding: const EdgeInsets.all(28),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: <Widget>[
Container(
width: 84,
height: 84,
decoration: BoxDecoration(
color: C.panel,
borderRadius: BorderRadius.circular(22),
border: Border.all(color: C.accent, width: 2),
),
child: const Icon(Icons.adjust, color: C.accent, size: 44),
),
const SizedBox(height: 18),
const Text('ARGEYM',
style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 6)),
const SizedBox(height: 4),
const Text('AUGMENTED REALITY DUEL',
style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 3)),
const SizedBox(height: 40),
Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
color: C.panel,
borderRadius: BorderRadius.circular(18),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
const Text('YOUR CALLSIGN',
style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 2)),
const SizedBox(height: 10),
TextField(
controller: _ctrl,
maxLength: 16,
textCapitalization: TextCapitalization.characters,
style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
decoration: InputDecoration(
counterText: '',
hintText: 'e.g. VIPER',
filled: true,
fillColor: C.panel2,
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(12),
borderSide: BorderSide.none,
),
suffixIcon: IconButton(
icon: const Icon(Icons.save_outlined, color: C.accent),
onPressed: save,
),
),
onChanged: () => setState(() => saved = false),
onSubmitted: () => _save(),
),
const SizedBox(height: 6),
Text(_saved ? 'Saved — you can change it anytime' : 'Tap save to store your callsign',
style: const TextStyle(fontSize: 12, color: C.muted)),
],
),
),
const SizedBox(height: 28),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: _play,
icon: const Icon(Icons.play_arrow_rounded),
label: const Text('ENTER LOBBY'),
),
),
],
),
),
),
),
);
}
}

// --- LOBBY SCREEN ---
class LobbyScreen extends StatefulWidget {
const LobbyScreen({super.key, required this.callsign});
final String callsign;
@override
State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
final NetworkService _net = NetworkService.instance;
final TextEditingController _codeCtrl = TextEditingController();
late final IO.Socket _socket;
String? _roomId;
bool _isHost = false;
bool _selfReady = false;
bool _scanning = false;
String _status = 'IDLE';
List<Map<String, dynamic>> _players = <Map<String, dynamic>>[];

// live hit-mode (server-authoritative, changeable in-app)
String _mode = HitMode.normal;
double _range = 80;
double _angle = 12;

@override
void initState() {
super.initState();
_socket = _net.connect();
_bind();
}

void _bind() {
socket.onConnect(() => _setStatus('CONNECTED'));
socket.onConnectError(() => _setStatus('CONNECTION ERROR'));
socket.onReconnect(() => _setStatus('RECONNECTED'));
socket.onDisconnect(() => _setStatus('RECONNECTING'));

_socket.on('room_mode', (dynamic data) {
if (!mounted || data is! Map) return;
setState(() {
_mode = (data['mode'] ?? _mode).toString();
_range = (data['rangeM'] is num) ? (data['rangeM'] as num).toDouble() : _range;
_angle = (data['angleDeg'] is num) ? (data['angleDeg'] as num).toDouble() : _angle;
});
});

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
_status = 'JOINED ROOM';
});
});

_socket.on('lobby_update', (dynamic data) {
if (!mounted) return;
final List<dynamic> list = (data is Map && data['players'] is List)
? data['players'] as List<dynamic>
: <dynamic>[];
setState(() {
_players = list.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
});
});

_socket.on('join_error', (dynamic data) {
if (!mounted) return;
final String message = (data is Map && data['message'] != null)
? data['message'].toString()
: 'INVALID ROOM';
setState(() {
_status = message;
_scanning = false;
});
});

socket.on('start_countdown', () => _goToGame());
}

void _unbind() {
_socket.off('room_mode');
_socket.off('room_created');
_socket.off('room_joined');
_socket.off('lobby_update');
_socket.off('join_error');
_socket.off('start_countdown');
}

void _setStatus(String value) {
if (!mounted) return;
setState(() => _status = value);
}

void _host() => _socket.emit('host_room', <String, dynamic>{'name': widget.callsign});

void _joinByCode() {
final String code = _codeCtrl.text.trim().toUpperCase();
if (code.isEmpty) {
setState(() => _status = 'ENTER A ROOM CODE');
return;
}
FocusScope.of(context).unfocus();
_socket.emit('join_room', <String, dynamic>{'roomId': code, 'name': widget.callsign});
}

void _setMode(String m) {
_socket.emit('set_room_mode', <String, dynamic>{'roomId': _roomId, 'mode': m});
}

void _toggleReady() {
if (_roomId == null) return;
setState(() => _selfReady = !_selfReady);
_socket.emit('player_ready', <String, dynamic>{'roomId': _roomId, 'ready': _selfReady});
}

void _onScan(BarcodeCapture capture) {
if (capture.barcodes.isEmpty) return;
final String? code = capture.barcodes.first.rawValue;
if (code == null || code.trim().isEmpty) {
setState(() => _status = 'INVALID QR CODE');
return;
}
setState(() => _scanning = false);
_socket.emit('join_room', <String, dynamic>{'roomId': code.trim(), 'name': widget.callsign});
}

void _goToGame() {
final String? roomId = _roomId;
if (roomId == null || !mounted) return;
unbind();
Navigator.of(context).pushReplacement(
MaterialPageRoute<void>(
builder: () => GameplayScreen(
socket: _socket,
roomId: roomId,
isHost: _isHost,
callsign: widget.callsign,
initialMode: _mode,
initialRange: _range,
initialAngle: _angle,
),
),
);
}

void _leaveLobby() {
_socket.emit('leave_game', <String, dynamic>{'roomId': _roomId});
_unbind();
Navigator.of(context).pop();
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
leading: IconButton(
icon: const Icon(Icons.arrow_back_ios_new, color: C.accent),
onPressed: _scanning ? () => setState(() => _scanning = false) : _leaveLobby,
),
title: const Text('LOBBY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w900)),
),
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
style: ElevatedButton.styleFrom(backgroundColor: C.danger, foregroundColor: Colors.white),
onPressed: () => setState(() => _scanning = false),
child: const Text('CANCEL'),
),
),
),
],
);
}

Widget _statusChip() {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(20)),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
const Icon(Icons.wifi_tethering, size: 16, color: C.accent),
const SizedBox(width: 8),
Text(_status, style: const TextStyle(fontSize: 13, color: C.muted, letterSpacing: 1)),
],
),
);
}

Widget _modeSelector() {
Widget chip(String m, String title, IconData icon) {
final bool sel = _mode == m;
return Expanded(
child: GestureDetector(
onTap: () => _setMode(m),
child: Container(
margin: const EdgeInsets.symmetric(horizontal: 4),
padding: const EdgeInsets.symmetric(vertical: 12),
decoration: BoxDecoration(
color: sel ? modeColor(m).withOpacity(0.15) : C.panel2,
borderRadius: BorderRadius.circular(12),
border: Border.all(color: sel ? modeColor(m) : Colors.transparent, width: 1.5),
),
child: Column(
children: <Widget>[
Icon(icon, color: sel ? modeColor(m) : C.muted, size: 20),
const SizedBox(height: 6),
Text(title,
style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? modeColor(m) : C.muted)),
],
),
),
),
);
}

return Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(16)),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: <Widget>[
const Text('HIT MODE (test) — applies to both players',
style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 1)),
const SizedBox(height: 10),
Row(
children: <Widget>[
chip(HitMode.normal, 'NORMAL', Icons.verified),
chip(HitMode.test, 'TEST', Icons.science),
chip(HitMode.walls, 'WALLS', Icons.layers_clear),
],
),
const SizedBox(height: 8),
Text(modeLabel(_mode, _range, _angle),
style: TextStyle(fontSize: 12, color: modeColor(_mode), fontWeight: FontWeight.bold)),
],
),
);
}

Widget _playerTile(Map<String, dynamic> p, bool isMe) {
final bool ready = p['ready'] == true;
return Container(
margin: const EdgeInsets.symmetric(vertical: 6),
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
decoration: BoxDecoration(
color: C.panel,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: ready ? C.accent : C.panel2, width: 1.5),
),
child: Row(
children: <Widget>[
Icon(isMe ? Icons.person : Icons.person_outline, color: ready ? C.accent : C.muted),
const SizedBox(width: 12),
Expanded(
child: Text(
'${p['name'] ?? 'PLAYER'}${isMe ? '  (you)' : ''}',
style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
),
),
Container(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
decoration: BoxDecoration(
color: ready ? C.accent.withOpacity(0.15) : C.panel2,
borderRadius: BorderRadius.circular(20),
),
child: Text(
ready ? 'READY' : 'NOT READY',
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.bold,
color: ready ? C.accent : C.muted,
),
),
),
],
),
);
}

Widget _buildLobby() {
final String? myId = _socket.id;
return SafeArea(
child: SingleChildScrollView(
padding: const EdgeInsets.all(20),
child: Column(
children: <Widget>[
_statusChip(),
const SizedBox(height: 24),
if (_roomId == null) ...<Widget>[
const SizedBox(height: 10),
const Icon(Icons.sports_esports, size: 56, color: C.muted),
const SizedBox(height: 22),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: _host,
icon: const Icon(Icons.add_circle_outline),
label: const Text('HOST ROOM'),
),
),
const SizedBox(height: 22),
const Row(
children: <Widget>[
Expanded(child: Divider(color: C.panel2)),
Padding(
padding: EdgeInsets.symmetric(horizontal: 10),
child: Text('OR JOIN', style: TextStyle(color: C.muted, letterSpacing: 2)),
),
Expanded(child: Divider(color: C.panel2)),
],
),
const SizedBox(height: 16),
// --- MANUAL ROOM CODE ENTRY ---
Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(16)),
child: Column(
children: <Widget>[
TextField(
controller: codeCtrl,
maxLength: 6,
textCapitalization: TextCapitalization.characters,
textAlign: TextAlign.center,
inputFormatters: <TextInputFormatter>[
FilteringTextInputFormatter.allow(RegExp('[a-fA-F0-9]')),
TextInputFormatter.withFunction((TextEditingValue oldV, TextEditingValue newV) =>
newV.copyWith(text: newV.text.toUpperCase())),
],
style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6),
decoration: InputDecoration(
counterText: '',
hintText: 'ABC123',
filled: true,
fillColor: C.panel2,
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(12),
borderSide: BorderSide.none,
),
),
onSubmitted: () => _joinByCode(),
),
const SizedBox(height: 12),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: _joinByCode,
icon: const Icon(Icons.login),
label: const Text('JOIN BY CODE'),
),
),
const SizedBox(height: 10),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
style: ElevatedButton.styleFrom(backgroundColor: C.panel2, foregroundColor: Colors.white),
onPressed: () => setState(() => _scanning = true),
icon: const Icon(Icons.qr_code_scanner),
label: const Text('SCAN QR'),
),
),
],
),
),
] else ...<Widget>[
if (_isHost)
Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
child: QrImageView(data: _roomId!, size: 200),
),
const SizedBox(height: 14),
SelectableText('ROOM  $_roomId',
style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
const SizedBox(height: 6),
const Text('Share this code with your opponent',
style: TextStyle(fontSize: 12, color: C.muted)),
const SizedBox(height: 18),
_modeSelector(),
const SizedBox(height: 18),
const Align(
alignment: Alignment.centerLeft,
child: Text('PLAYERS', style: TextStyle(fontSize: 12, color: C.muted, letterSpacing: 2)),
),
const SizedBox(height: 6),
..._players.map((Map<String, dynamic> p) => _playerTile(p, p['id'] == myId)),
if (_players.length < 2)
const Padding(
padding: EdgeInsets.symmetric(vertical: 10),
child: Text('Waiting for opponent…', style: TextStyle(color: C.muted)),
),
const SizedBox(height: 24),
SizedBox(
width: double.infinity,
child: ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor: _selfReady ? C.accent : C.panel2,
foregroundColor: _selfReady ? Colors.black : Colors.white,
padding: const EdgeInsets.symmetric(vertical: 20),
),
onPressed: _toggleReady,
child: Text(_selfReady ? 'READY ✓' : 'TAP TO READY'),
),
),
],
],
),
),
);
}
}

// --- GAME PHASES ---
enum GamePhase { countdown, active, ended }

// --- GAMEPLAY SCREEN ---
class GameplayScreen extends StatefulWidget {
const GameplayScreen({
super.key,
required this.socket,
required this.roomId,
required this.isHost,
required this.callsign,
this.initialMode = HitMode.normal,
this.initialRange = 80,
this.initialAngle = 12,
});
final IO.Socket socket;
final String roomId;
final bool isHost;
final String callsign;
final String initialMode;
final double initialRange;
final double initialAngle;
@override
State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
CameraController? _camera;
final SensorService _sensors = SensorService();
Timer? _telemetryTimer;
Timer? _renderTimer;

GamePhase _phase = GamePhase.countdown;
String _countdownLabel = '3';

static const int _maxAmmo = 30;
int _ammo = _maxAmmo;
int _hp = 100;
bool _alive = true;
bool _reloading = false;
int _myKills = 0;
int _myDeaths = 0;

double _orangeFlash = 0.0;
double _redFlash = 0.0;
String _endReason = '';
String _respawnText = '';

// live hit-mode
late String _mode;
late double _range;
late double _angle;

// opponent telemetry
String _oppName = 'OPPONENT';
double? _oppLat;
double? _oppLng;
bool _oppGps = false;

@override
void initState() {
super.initState();
_mode = widget.initialMode;
_range = widget.initialRange;
_angle = widget.initialAngle;
_startSensors();
_bind();
_initCamera();
renderTimer = Timer.periodic(const Duration(milliseconds: 120), () {
if (mounted) setState(() {});
});
}

Future<void> _startSensors() async {
await _sensors.start();
telemetryTimer = Timer.periodic(const Duration(milliseconds: 300), () {
widget.socket.emit('telemetry', <String, dynamic>{
'roomId': widget.roomId,
'heading': _sensors.heading,
'lat': _sensors.lat,
'lng': _sensors.lng,
});
});
}

Future<void> initCamera() async {
if (gCameras.isEmpty) return;
final CameraDescription rear = gCameras.firstWhere(
(CameraDescription c) => c.lensDirection == CameraLensDirection.back,
orElse: () => gCameras.first,
);
final CameraController controller =
CameraController(rear, ResolutionPreset.high, enableAudio: false);
try {
await controller.initialize();
} catch () {
return;
}
if (!mounted) {
await controller.dispose();
return;
}
setState(() => _camera = controller);
}

void _bind() {
widget.socket.on('room_mode', (dynamic data) {
if (!mounted || data is! Map) return;
setState(() {
_mode = (data['mode'] ?? _mode).toString();
_range = (data['rangeM'] is num) ? (data['rangeM'] as num).toDouble() : _range;
_angle = (data['angleDeg'] is num) ? (data['angleDeg'] as num).toDouble() : _angle;
});
});
widget.socket.on('countdown', (dynamic data) {
if (!mounted) return;
final int c = (data is Map && data['count'] != null) ? (data['count'] as num).toInt() : 0;
setState(() {
_phase = GamePhase.countdown;
countdownLabel = c > 0 ? c.toString() : "GO!";
});
});
widget.socket.on('game_start', () {
if (!mounted) return;
setState(() => phase = GamePhase.active);
});
widget.socket.on('hit_confirmed', () => flashOrange());
widget.socket.on('shot_missed', () {});
widget.socket.on('hit_taken', (dynamic data) {
if (!mounted) return;
final int hp = (data is Map && data['hp'] != null) ? (data['hp'] as num).toInt() : _hp;
setState(() => _hp = hp);
_flashRed();
});
widget.socket.on('opponent_telemetry', (dynamic data) {
if (!mounted || data is! Map) return;
setState(() {
_oppName = (data['name'] ?? _oppName).toString();
_oppLat = (data['lat'] is num) ? (data['lat'] as num).toDouble() : null;
_oppLng = (data['lng'] is num) ? (data['lng'] as num).toDouble() : null;
_oppGps = data['hasGps'] == true;
});
});
widget.socket.on('fragged', (dynamic data) {
if (!mounted || data is! Map) return;
final String myId = widget.socket.id ?? '';
if (data['killer'] == myId) {
setState(() => _myKills += 1);
}
if (data['victim'] == myId) {
setState(() {
_myDeaths += 1;
_alive = false;
_respawnText = 'ELIMINATED BY ${data['killerName'] ?? 'ENEMY'}';
});
}
});
widget.socket.on('respawn', (dynamic data) {
if (!mounted) return;
final int hp = (data is Map && data['hp'] != null) ? (data['hp'] as num).toInt() : 100;
setState(() {
_hp = hp;
_alive = true;
_ammo = _maxAmmo;
_reloading = false;
_respawnText = '';
});
});
widget.socket.on('game_ended', (dynamic data) {
if (!mounted) return;
final String reason = (data is Map && data['reason'] != null) ? data['reason'].toString() : 'GAME ENDED';
setState(() {
_phase = GamePhase.ended;
_endReason = reason;
});
});
}

void _flashOrange() {
if (!mounted) return;
setState(() => _orangeFlash = 0.30);
Future<void>.delayed(const Duration(milliseconds: 250), () {
if (mounted) setState(() => _orangeFlash = 0.0);
});
}

void _flashRed() {
if (!mounted) return;
setState(() => _redFlash = 0.50);
Future<void>.delayed(const Duration(milliseconds: 350), () {
if (mounted) setState(() => _redFlash = 0.0);
});
}

void _shoot() {
if (_phase != GamePhase.active || !_alive || _reloading || _ammo <= 0) return;
setState(() => _ammo -= 1);
widget.socket.emit('shoot', <String, dynamic>{
'roomId': widget.roomId,
'heading': _sensors.heading,
'lat': _sensors.lat,
'lng': _sensors.lng,
});
}

void _reload() {
if (_phase != GamePhase.active || _reloading || !_alive) return;
setState(() => _reloading = true);
Future<void>.delayed(const Duration(seconds: 2), () {
if (!mounted) return;
setState(() {
_ammo = _maxAmmo;
_reloading = false;
});
});
}

void _setMode(String m) {
widget.socket.emit('set_room_mode', <String, dynamic>{'roomId': widget.roomId, 'mode': m});
}

void _openModePicker() {
showModalBottomSheet<void>(
context: context,
backgroundColor: C.panel,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
),
builder: (BuildContext ctx) {
Widget tile(String m, String title, String sub, IconData icon) {
final bool sel = _mode == m;
return ListTile(
leading: Icon(icon, color: sel ? modeColor(m) : C.muted),
title: Text(title,
style: TextStyle(fontWeight: FontWeight.bold, color: sel ? modeColor(m) : Colors.white)),
subtitle: Text(sub, style: const TextStyle(color: C.muted)),
trailing: sel ? Icon(Icons.check, color: modeColor(m)) : null,
onTap: () {
_setMode(m);
Navigator.pop(ctx);
},
);
}

return SafeArea(
child: Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
const Padding(
padding: EdgeInsets.all(16),
child: Text('HIT MODE',
style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, fontSize: 16)),
),
tile(HitMode.normal, 'NORMAL', '80 m / 12° — real aiming', Icons.verified),
tile(HitMode.test, 'TEST', '300 m / 45° — long range, through windows', Icons.science),
tile(HitMode.walls, 'THROUGH WALLS', 'hit anywhere, no aiming', Icons.layers_clear),
const SizedBox(height: 12),
],
),
);
},
);
}

void _leaveToMenu() {
widget.socket.emit('leave_game', <String, dynamic>{'roomId': widget.roomId});
Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
}

@override
void dispose() {
_telemetryTimer?.cancel();
_renderTimer?.cancel();
_sensors.stop();
_camera?.dispose();
widget.socket.off('room_mode');
widget.socket.off('countdown');
widget.socket.off('game_start');
widget.socket.off('hit_confirmed');
widget.socket.off('shot_missed');
widget.socket.off('hit_taken');
widget.socket.off('opponent_telemetry');
widget.socket.off('fragged');
widget.socket.off('respawn');
widget.socket.off('game_ended');
super.dispose();
}

@override
Widget build(BuildContext context) {
final CameraController? cam = _camera;
final Size size = MediaQuery.of(context).size;
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
if (_phase == GamePhase.active) _buildOpponentLayer(size.width, size.height),
if (_phase == GamePhase.active && _alive) _buildCrosshair(),
if (_phase == GamePhase.active) _buildHud(),
if (_phase == GamePhase.active && !_alive) _buildRespawnOverlay(),
if (_phase == GamePhase.countdown) _buildCountdown(),
if (_phase == GamePhase.ended) _buildEnded(),
_buildModeTag(),
],
),
);
}

Widget _buildModeTag() {
return Positioned(
top: MediaQuery.of(context).padding.top + 6,
left: 0,
right: 0,
child: Center(
child: Text(modeLabel(_mode, _range, _angle).toUpperCase(),
style: TextStyle(fontSize: 11, color: modeColor(_mode), letterSpacing: 2, fontWeight: FontWeight.bold)),
),
);
}

String _gpsHint() {
if (_sensors.gpsDenied) return 'LOCATION DENIED — enable to see opponent';
if (!_sensors.gpsReady) return 'ACQUIRING GPS…';
if (!_oppGps) return 'WAITING FOR OPPONENT GPS…';
return 'SEARCHING…';
}

Widget _buildOpponentLayer(double w, double h) {
final bool haveBoth = _oppLat != null && _oppLng != null && _sensors.lat != null && _sensors.lng != null;
if (!haveBoth) {
return Positioned(
top: h * 0.16,
left: 0,
right: 0,
child: Center(child: _hintChip(_gpsHint())),
);
}
final double b = bearingBetween(_sensors.lat!, _sensors.lng!, _oppLat!, _oppLng!);
final double dist = distanceMeters(_sensors.lat!, _sensors.lng!, _oppLat!, _oppLng!);
final double rel = normalizeSigned(b - _sensors.heading);
const double fovHalf = 35.0;

if (rel.abs() <= fovHalf) {
double x = w / 2 + (rel / fovHalf) * (w / 2 - 70);
x = x.clamp(70.0, w - 70.0);
return Positioned(
left: x - 70,
top: h * 0.28,
child: _targetMarker(dist),
);
} else {
final bool left = rel < 0;
return Positioned(
left: left ? 14 : null,
right: left ? null : 14,
top: h * 0.42,
child: _edgeArrow(left, dist),
);
}
}

Widget _hintChip(String text) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
child: Text(text, style: const TextStyle(fontSize: 13, color: C.warn, letterSpacing: 1)),
);
}

Widget _targetMarker(double dist) {
return Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Container(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
decoration: BoxDecoration(
color: C.danger.withOpacity(0.85),
borderRadius: BorderRadius.circular(8),
),
child: Text(_oppName,
style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)),
),
const SizedBox(height: 4),
const Icon(Icons.crop_free, color: C.danger, size: 90),
const SizedBox(height: 4),
Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
child: Text(prettyDistance(dist),
style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: C.accent)),
),
],
);
}

Widget _edgeArrow(bool left, double dist) {
return Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(left ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios, color: C.warn, size: 40),
const SizedBox(height: 6),
Container(
padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
child: Column(
children: <Widget>[
Text(_oppName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
Text(prettyDistance(dist), style: const TextStyle(fontSize: 12, color: C.accent)),
],
),
),
],
);
}

Widget _buildCrosshair() {
return const Center(child: Icon(Icons.add, color: C.accent, size: 56));
}

Widget _buildHud() {
return SafeArea(
child: Padding(
padding: const EdgeInsets.all(14),
child: Stack(
children: <Widget>[
Align(
alignment: Alignment.topLeft,
child: Row(
children: <Widget>[
_badge(Icons.favorite, '$_hp', _hp > 30 ? C.accent : C.danger),
const SizedBox(width: 8),
_badge(Icons.military_tech, '$_myKills : $_myDeaths', C.warn),
],
),
),
Align(
alignment: Alignment.topRight,
child: Row(
children: <Widget>[
_badge(Icons.bolt, '$_ammo/$_maxAmmo', Colors.white),
const SizedBox(width: 8),
GestureDetector(
onTap: _openModePicker,
child: Container(
padding: const EdgeInsets.all(10),
decoration: BoxDecoration(
color: Colors.black54,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: modeColor(_mode), width: 1),
),
child: Icon(modeIcon(_mode), color: modeColor(_mode), size: 22),
),
),
const SizedBox(width: 8),
GestureDetector(
onTap: _leaveToMenu,
child: Container(
padding: const EdgeInsets.all(10),
decoration: BoxDecoration(
color: Colors.black54,
borderRadius: BorderRadius.circular(10),
),
child: const Icon(Icons.exit_to_app, color: C.danger, size: 22),
),
),
],
),
),
Align(
alignment: Alignment.bottomCenter,
child: Row(
mainAxisAlignment: MainAxisAlignment.spaceEvenly,
children: <Widget>[
_actionButton(_reloading ? 'RELOADING' : 'RELOAD', C.panel2, _reload, Icons.autorenew),
_actionButton('FIRE', C.danger, _shoot, Icons.gps_fixed),
],
),
),
],
),
),
);
}

Widget _badge(IconData icon, String text, Color color) {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
child: Row(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
Icon(icon, size: 18, color: color),
const SizedBox(width: 6),
Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
],
),
);
}

Widget _actionButton(String label, Color color, VoidCallback onTap, IconData icon) {
return ElevatedButton.icon(
onPressed: onTap,
style: ElevatedButton.styleFrom(
backgroundColor: color,
foregroundColor: Colors.white,
padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
),
icon: Icon(icon, size: 20),
label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
);
}

Widget _buildCountdown() {
return Container(
color: Colors.black54,
child: Center(
child: Text(
_countdownLabel,
style: const TextStyle(fontSize: 88, fontWeight: FontWeight.w900, color: Colors.white),
),
),
);
}

Widget _buildRespawnOverlay() {
return Container(
color: Colors.red.withOpacity(0.25),
child: Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
const Icon(Icons.dangerous, color: C.danger, size: 70),
const SizedBox(height: 12),
Text(_respawnText,
textAlign: TextAlign.center,
style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
const SizedBox(height: 8),
const Text('RESPAWNING…', style: TextStyle(fontSize: 16, color: C.warn, letterSpacing: 2)),
],
),
),
);
}

Widget _buildEnded() {
return Container(
color: Colors.black87,
child: Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: <Widget>[
const Text('GAME OVER',
style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 4)),
const SizedBox(height: 8),
Text(_endReason, style: const TextStyle(fontSize: 16, color: C.muted)),
const SizedBox(height: 16),
Text('FRAGS  $_myKills   DEATHS  $_myDeaths',
style: const TextStyle(fontSize: 18, color: C.accent, fontWeight: FontWeight.bold)),
const SizedBox(height: 28),
ElevatedButton(
onPressed: () => Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst),
child: const Text('RETURN TO MENU'),
),
],
),
),
);
}
}
DART_EOF

# --- VPS SERVER PACKAGE ---
cat << 'PKG_EOF' > server/package.json
{
"name": "argeym-server",
"version": "1.3.0",
"private": true,
"main": "server.js",
"scripts": {
"start": "node server.js"
},
"dependencies": {
"socket.io": "^4.7.5"
}
}
PKG_EOF

# --- VPS SERVER LOGIC ---
cat << 'SERVER_EOF' > server/server.js
const http = require('http');
const crypto = require('crypto');
const { Server } = require('socket.io');

// --- ENV CONFIG (only sets the DEFAULT mode; mode is changeable in-app at runtime) ---
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
const TEST_RANGE = envNum('TEST_RANGE_M', 300);
const TEST_ANGLE = envNum('TEST_ANGLE_DEG', 45);

const TEST_MODE = envBool('TEST_MODE');
const IGNORE_AIM = envBool('IGNORE_AIM') || envBool('THROUGH_WALLS');
const INITIAL_MODE = IGNORE_AIM ? 'walls' : (TEST_MODE ? 'test' : 'normal');

const MAX_HP = 100;
const HIT_DAMAGE = 25;
const COUNTDOWN_SECONDS = 3;
const RESPAWN_MS = 4000;

function presetFor(mode) {
if (mode === 'walls') return { mode: 'walls', ignoreAim: true, rangeM: TEST_RANGE, angleDeg: TEST_ANGLE };
if (mode === 'test') return { mode: 'test', ignoreAim: false, rangeM: TEST_RANGE, angleDeg: TEST_ANGLE };
return { mode: 'normal', ignoreAim: false, rangeM: NORMAL_RANGE, angleDeg: NORMAL_ANGLE };
}

const CONFIG_LINE = 'default_mode=' + INITIAL_MODE +
' normal=' + NORMAL_RANGE + 'm/' + NORMAL_ANGLE + 'deg' +
' test=' + TEST_RANGE + 'm/' + TEST_ANGLE + 'deg';

// --- SERVER BOOTSTRAP ---
const httpServer = http.createServer((req, res) => {
res.writeHead(200, { 'Content-Type': 'text/plain' });
res.end('ARGEYM VPS ONLINE | ' + CONFIG_LINE);
});

const io = new Server(httpServer, {
cors: { origin: '*', methods: ['GET', 'POST'] },
});

// --- ROOM STATE ---
const rooms = {};

// --- HELPERS ---
function generateRoomId() {
return crypto.randomBytes(3).toString('hex').toUpperCase();
}
function angularDistance(a, b) {
let diff = Math.abs(a - b) % 360;
if (diff > 180) diff = 360 - diff;
return diff;
}
function toRad(d) { return (d * Math.PI) / 180; }
function toDeg(r) { return (r * 180) / Math.PI; }
function bearing(lat1, lon1, lat2, lon2) {
const dLon = toRad(lon2 - lon1);
const y = Math.sin(dLon) * Math.cos(toRad(lat2));
const x = Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(dLon);
return (toDeg(Math.atan2(y, x)) + 360) % 360;
}
function haversine(lat1, lon1, lat2, lon2) {
const R = 6371000;
const dLat = toRad(lat2 - lat1);
const dLon = toRad(lon2 - lon1);
const a = Math.sin(dLat / 2) ** 2 +
Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
function newPlayer(id, name) {
return { id, name, hp: MAX_HP, ready: false, alive: true, kills: 0, deaths: 0, lat: null, lng: null, heading: 0, hasGps: false };
}
function getOpponent(room, id) { return room.players.find((p) => p.id !== id) || null; }
function findPlayer(room, id) { return room.players.find((p) => p.id === id) || null; }
function publicPlayers(room) {
return room.players.map((p) => ({ id: p.id, name: p.name, ready: p.ready, kills: p.kills, deaths: p.deaths }));
}
function emitLobby(roomId) {
const room = rooms[roomId];
if (!room) return;
io.to(roomId).emit('lobby_update', { roomId, players: publicPlayers(room) });
}
function emitMode(roomId) {
const room = rooms[roomId];
if (!room) return;
io.to(roomId).emit('room_mode', room.config);
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

function endGame(socket, reason) {
const room = rooms[socket.data.roomId];
if (!room) return;
socket.to(room.id).emit('game_ended', { reason });
room.players = room.players.filter((p) => p.id !== socket.id);
if (room.players.length === 0) {
delete rooms[room.id];
} else {
room.started = false;
room.players.forEach((p) => { p.ready = false; });
emitLobby(room.id);
}
}

// --- CONNECTION LIFECYCLE ---
io.on('connection', (socket) => {
// --- ROOM HOSTING ---
socket.on('host_room', (payload) => {
let roomId = generateRoomId();
while (rooms[roomId]) roomId = generateRoomId();
const name = payload && payload.name ? String(payload.name).slice(0, 16) : 'HOST';
rooms[roomId] = {
id: roomId,
started: false,
players: [newPlayer(socket.id, name)],
config: presetFor(INITIAL_MODE),
};
socket.join(roomId);
socket.data.roomId = roomId;
socket.emit('room_created', { roomId });
emitLobby(roomId);
emitMode(roomId);
});

// --- ROOM JOINING (works for QR scan AND manual code) ---
socket.on('join_room', (payload) => {
const roomId = payload && payload.roomId ? String(payload.roomId).toUpperCase() : '';
const name = payload && payload.name ? String(payload.name).slice(0, 16) : 'PLAYER';
const room = rooms[roomId];
if (!room) {
socket.emit('join_error', { message: 'INVALID ROOM' });
return;
}
if (room.players.length >= 2) {
socket.emit('join_error', { message: 'ROOM FULL' });
return;
}
room.players.push(newPlayer(socket.id, name));
socket.join(roomId);
socket.data.roomId = roomId;
socket.emit('room_joined', { roomId });
socket.to(roomId).emit('opponent_joined', { id: socket.id, name });
emitLobby(roomId);
emitMode(roomId);
});

// --- IN-APP HIT MODE SWITCH (runtime, per room, both players) ---
socket.on('set_room_mode', (payload) => {
const room = rooms[socket.data.roomId];
if (!room) return;
const mode = payload && typeof payload.mode === 'string' ? payload.mode : '';
if (!['normal', 'test', 'walls'].includes(mode)) return;
room.config = presetFor(mode);
emitMode(room.id);
});

// --- READY SYNC ---
socket.on('player_ready', (payload) => {
const room = rooms[socket.data.roomId];
if (!room) return;
const player = findPlayer(room, socket.id);
if (!player) return;
player.ready = !!(payload && payload.ready === true);
emitLobby(room.id);
const allReady = room.players.length === 2 && room.players.every((p) => p.ready);
if (allReady && !room.started) {
room.started = true;
runCountdown(room.id);
}
});

// --- TELEMETRY (heading + GPS) ---
socket.on('telemetry', (payload) => {
const room = rooms[socket.data.roomId];
if (!room) return;
const player = findPlayer(room, socket.id);
if (!player) return;
if (payload && typeof payload.heading === 'number') player.heading = payload.heading;
if (payload && typeof payload.lat === 'number' && typeof payload.lng === 'number') {
player.lat = payload.lat;
player.lng = payload.lng;
player.hasGps = true;
}
const opp = getOpponent(room, socket.id);
if (opp) {
io.to(opp.id).emit('opponent_telemetry', {
id: player.id,
name: player.name,
heading: player.heading,
lat: player.lat,
lng: player.lng,
hasGps: player.hasGps,
hp: player.hp,
alive: player.alive,
});
}
});

// --- HIT SCAN VALIDATION (uses the room's live config) ---
socket.on('shoot', (payload) => {
const room = rooms[socket.data.roomId];
if (!room || !room.started) return;
const shooter = findPlayer(room, socket.id);
const victim = getOpponent(room, socket.id);
if (!shooter || !victim || !shooter.alive || !victim.alive) return;

const cfg = room.config || presetFor(INITIAL_MODE);
const sh = payload && typeof payload.heading === 'number' ? payload.heading : shooter.heading;
if (payload && typeof payload.lat === 'number') shooter.lat = payload.lat;
if (payload && typeof payload.lng === 'number') shooter.lng = payload.lng;

let hit = false;
let info = {};

if (cfg.ignoreAim) {
// WALLS: any shot at a living opponent connects (through walls, no aiming).
hit = true;
info = { mode: 'walls' };
} else if (shooter.hasGps && victim.hasGps && shooter.lat !== null && victim.lat !== null) {
// GPS: must aim toward the opponent's real-world position, within range.
const b = bearing(shooter.lat, shooter.lng, victim.lat, victim.lng);
const d = haversine(shooter.lat, shooter.lng, victim.lat, victim.lng);
const delta = angularDistance(sh, b);
hit = d <= cfg.rangeM && delta <= cfg.angleDeg;
info = { mode: cfg.mode, delta, distance: d };
} else {
// Fallback (no GPS): both players must face each other (headings ~180 apart).
const facing = angularDistance(angularDistance(sh, victim.heading), 180);
hit = facing <= cfg.angleDeg;
info = { mode: 'compass', delta: facing };
}

if (!hit) {
socket.emit('shot_missed', info);
return;
}

socket.emit('hit_confirmed', info);
victim.hp = Math.max(0, victim.hp - HIT_DAMAGE);
io.to(victim.id).emit('hit_taken', { hp: victim.hp });

if (victim.hp <= 0) {
// --- ELIMINATION + RESPAWN (no game over on a kill) ---
victim.alive = false;
shooter.kills += 1;
victim.deaths += 1;
io.to(room.id).emit('fragged', {
killer: shooter.id,
killerName: shooter.name,
victim: victim.id,
victimName: victim.name,
kills: shooter.kills,
respawnMs: RESPAWN_MS,
});
io.to(room.id).emit('score', { players: publicPlayers(room) });
const vid = victim.id;
const rid = room.id;
setTimeout(() => {
const r = rooms[rid];
if (!r) return;
const v = findPlayer(r, vid);
if (!v) return;
v.hp = MAX_HP;
v.alive = true;
io.to(vid).emit('respawn', { hp: MAX_HP });
}, RESPAWN_MS);
}
});

// --- LEAVE / DISCONNECT (ends the game for the other player) ---
socket.on('leave_game', () => endGame(socket, 'OPPONENT LEFT'));
socket.on('disconnect', () => endGame(socket, 'OPPONENT DISCONNECTED'));
});

// --- LISTENER ---
const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
console.log('ARGEYM VPS listening on port ' + PORT + ' | ' + CONFIG_LINE);
});
SERVER_EOF

# --- CI/CD WORKFLOW ---
cat << 'YML_EOF' > .github/workflows/build.yml
name: AR Shooter Cross-Platform Build

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build-ios:
    name: Build Unsigned iOS IPA
    runs-on: macos-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.24.5'
      - name: Generate Native Host Projects
        run: flutter create --org com.argeym --project-name argeym --platforms=ios,android .
      - name: Inject iOS Permissions
        run: |
          PLIST=ios/Runner/Info.plist
          CAM="Argeym uses the rear camera to render the live augmented-reality battlefield and align targets in real time."
          LOC="Argeym uses your location to measure the real-world distance and bearing to your opponent for hit detection."
          /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription $CAM" "$PLIST" || /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string $CAM" "$PLIST"
          /usr/libexec/PlistBuddy -c "Set :NSLocationWhenInUseUsageDescription $LOC" "$PLIST" || /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string $LOC" "$PLIST"
      - name: Resolve Dependencies
        run: flutter pub get
      - name: Build iOS
        run: flutter build ios --release --no-codesign
      - name: Package Unsigned IPA
        run: |
          mkdir -p build/ipa/Payload
          cp -r build/ios/iphoneos/Runner.app build/ipa/Payload/Runner.app
          cd build/ipa
          zip -r -q app-release.ipa Payload
      - name: Upload iOS Artifact
        uses: actions/upload-artifact@v4
        with:
          name: ios-release-ipa
          path: build/ipa/app-release.ipa

  build-android:
    name: Build Android APK
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: zulu
          java-version: '17'
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.24.5'
      - name: Generate Native Host Projects
        run: flutter create --org com.argeym --project-name argeym --platforms=ios,android .
      - name: Inject Android Permissions
        run: |
          MANIFEST=android/app/src/main/AndroidManifest.xml
          if ! grep -q "android.permission.CAMERA" "$MANIFEST"; then
            sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <application#' "$MANIFEST"
          fi
          if ! grep -q "android.permission.ACCESS_FINE_LOCATION" "$MANIFEST"; then
            sed -i 's#<application#<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application#' "$MANIFEST"
          fi
      - name: Patch Plugin compileSdk
        run: |
          if [ -f android/build.gradle.kts ]; then
            printf 'subprojects {\n    afterEvaluate {\n        extensions.findByName("android")?.let { (it as com.android.build.gradle.BaseExtension).compileSdkVersion(34) }\n    }\n}\n\n' | cat - android/build.gradle.kts > android/build.gradle.kts.tmp && mv android/build.gradle.kts.tmp android/build.gradle.kts
          fi
          if [ -f android/build.gradle ]; then
            printf 'subprojects {\n    afterEvaluate { project ->\n        if (project.hasProperty("android")) {\n            project.android { compileSdkVersion 34 }\n        }\n    }\n}\n\n' | cat - android/build.gradle > android/build.gradle.tmp && mv android/build.gradle.tmp android/build.gradle
          fi
      - name: Resolve Dependencies
        run: flutter pub get
      - name: Patch Plugins Referencing Flutter Gradle Extension
        run: |
          PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
          find "$PUB_CACHE_DIR" -path '*/android/build.gradle' -print0 | while IFS= read -r -d '' f; do
            sed -i \
              -e 's/flutter\.compileSdkVersion/34/g' \
              -e 's/flutter\.minSdkVersion/21/g' \
              -e 's/flutter\.targetSdkVersion/34/g' \
              "$f"
          done
      - name: Build APK
        run: flutter build apk --release
      - name: Upload Android Artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
YML_EOF

# --- IGNORE RULES ---
cat << 'GITIGNORE_EOF' > .gitignore
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
server/node_modules/
*.iml
.idea/
GITIGNORE_EOF

# --- GIT AUTOMATION ---
if [ -n "$ARGEYM_SKIP_GIT" ]; then
echo "ARGEYM_SKIP_GIT set: project files generated, skipping git automation."
exit 0
fi

if [ ! -d .git ]; then
git init
fi
git checkout -B main
git add -A
git commit -m "ARGEYM: in-app runtime hit-mode switch (normal/test/walls)"
git remote remove origin 2>/dev/null || true
git remote add origin "<https://<INSERT_TOKEN_HERE>@github.com/dophycoder/argeym.git>"
git push -u origin main --force
