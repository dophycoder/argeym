#!/usr/bin/env bash
set -e

# --- DIRECTORY SCAFFOLD ---
mkdir -p ios/Runner
mkdir -p lib
mkdir -p server
mkdir -p .github/workflows

# --- FLUTTER MANIFEST ---
# geolocator ^10.1.1 uses geolocator_android 4.4.x which does NOT reference
# flutter.compileSdkVersion and builds cleanly with AGP 8.x / Flutter 3.24.x
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
  geolocator: ^10.1.1
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

List<CameraDescription> gCameras = <CameraDescription>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { gCameras = await availableCameras(); } catch (_) { gCameras = []; }
  runApp(const ARShooterApp());
}

class HitMode {
  static const String normal = 'normal';
  static const String test   = 'test';
  static const String walls  = 'walls';
}

String modeLabel(String m, double range, double angle) {
  switch (m) {
    case HitMode.walls: return 'WALLS • hit anywhere';
    case HitMode.test:  return 'TEST • ${range.toStringAsFixed(0)}m / ${angle.toStringAsFixed(0)}°';
    default:            return 'NORMAL • ${range.toStringAsFixed(0)}m / ${angle.toStringAsFixed(0)}°';
  }
}
IconData modeIcon(String m) {
  switch (m) {
    case HitMode.walls: return Icons.layers_clear;
    case HitMode.test:  return Icons.science;
    default:            return Icons.verified;
  }
}
Color modeColor(String m) {
  switch (m) {
    case HitMode.walls: return const Color(0xFFFF4D5E);
    case HitMode.test:  return const Color(0xFFFFC93C);
    default:            return const Color(0xFF27E6A4);
  }
}

class C {
  static const Color bg     = Color(0xFF0B0F14);
  static const Color panel  = Color(0xFF161E29);
  static const Color panel2 = Color(0xFF1F2A38);
  static const Color accent = Color(0xFF27E6A4);
  static const Color danger = Color(0xFFFF4D5E);
  static const Color warn   = Color(0xFFFFC93C);
  static const Color muted  = Color(0xFF8A97A6);
}

class ARShooterApp extends StatelessWidget {
  const ARShooterApp({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'ARGEYM',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: C.bg,
        colorScheme: base.colorScheme.copyWith(primary: C.accent, secondary: C.accent, surface: C.panel),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: C.accent, foregroundColor: Colors.black,
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

class Prefs {
  static const _kName = 'callsign';
  static Future<String> loadName() async => (await SharedPreferences.getInstance()).getString(_kName) ?? '';
  static Future<void> saveName(String n) async => (await SharedPreferences.getInstance()).setString(_kName, n);
}

double _deg2rad(double d) => d * pi / 180.0;
double _rad2deg(double r) => r * 180.0 / pi;
double bearingBetween(double lat1, double lon1, double lat2, double lon2) {
  final dLon = _deg2rad(lon2 - lon1);
  final y = sin(dLon) * cos(_deg2rad(lat2));
  final x = cos(_deg2rad(lat1)) * sin(_deg2rad(lat2)) - sin(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * cos(dLon);
  return (_rad2deg(atan2(y, x)) + 360) % 360;
}
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1), dLon = _deg2rad(lon2 - lon1);
  final a = sin(dLat/2)*sin(dLat/2) + cos(_deg2rad(lat1))*cos(_deg2rad(lat2))*sin(dLon/2)*sin(dLon/2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}
double normalizeSigned(double a) { double d = (a+180)%360; if(d<0) d+=360; return d-180; }
String prettyDistance(double m) => m < 1000 ? '${m.toStringAsFixed(m<10?1:0)} m' : '${(m/1000).toStringAsFixed(2)} km';

class NetworkService {
  NetworkService._internal();
  static final NetworkService instance = NetworkService._internal();
  static const String serverUrl = 'http://185.216.71.84:3001';
  IO.Socket? socket;
  IO.Socket connect() {
    final ex = socket;
    if (ex != null) { if (!ex.connected) ex.connect(); return ex; }
    final s = IO.io(serverUrl, IO.OptionBuilder().setTransports(['websocket']).enableReconnection()
        .setReconnectionAttempts(1000000).setReconnectionDelay(1000).setReconnectionDelayMax(5000).disableAutoConnect().build());
    socket = s; s.connect(); return s;
  }
  void dispose() { socket?.dispose(); socket = null; }
}

class SensorService {
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _posSub;
  double heading = 0.0;
  double? lat, lng;
  bool gpsReady = false, gpsDenied = false;

  Future<void> start() async {
    final stream = FlutterCompass.events;
    if (stream != null) _compassSub = stream.listen((e) { final h = e.heading; if (h != null) heading = (h+360)%360; });
    await _initGps();
  }
  Future<void> _initGps() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { gpsDenied = true; return; }
      if (!await Geolocator.isLocationServiceEnabled()) return;
      _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0))
          .listen((p) { lat = p.latitude; lng = p.longitude; gpsReady = true; });
    } catch (_) {}
  }
  void stop() { _compassSub?.cancel(); _posSub?.cancel(); _compassSub = null; _posSub = null; }
}

// ── HOME ────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _saved = false;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final n = await Prefs.loadName();
    if (!mounted) return;
    setState(() { _ctrl.text = n; _saved = n.isNotEmpty; });
  }
  Future<void> _save() async {
    final n = _ctrl.text.trim(); if (n.isEmpty) return;
    await Prefs.saveName(n); FocusScope.of(context).unfocus(); setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Callsign saved'), duration: Duration(seconds: 1)));
  }
  void _play() {
    final n = _ctrl.text.trim();
    if (n.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a callsign first'))); return; }
    Prefs.saveName(n);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LobbyScreen(callsign: n)));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width:84,height:84,decoration:BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(22),border:Border.all(color:C.accent,width:2)),
          child: const Icon(Icons.adjust, color: C.accent, size: 44)),
        const SizedBox(height:18),
        const Text('ARGEYM', style: TextStyle(fontSize:40,fontWeight:FontWeight.w900,letterSpacing:6)),
        const SizedBox(height:4),
        const Text('AUGMENTED REALITY DUEL', style: TextStyle(fontSize:12,color:C.muted,letterSpacing:3)),
        const SizedBox(height:40),
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR CALLSIGN', style: TextStyle(fontSize:12,color:C.muted,letterSpacing:2)),
            const SizedBox(height:10),
            TextField(controller:_ctrl, maxLength:16, textCapitalization:TextCapitalization.characters,
              style: const TextStyle(fontSize:22,fontWeight:FontWeight.bold),
              decoration: InputDecoration(counterText:'',hintText:'e.g. VIPER',filled:true,fillColor:C.panel2,
                border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none),
                suffixIcon:IconButton(icon:const Icon(Icons.save_outlined,color:C.accent),onPressed:_save)),
              onChanged:(_)=>setState(()=>_saved=false), onSubmitted:(_)=>_save()),
            const SizedBox(height:6),
            Text(_saved?'Saved — you can change it anytime':'Tap save to store your callsign',
              style: const TextStyle(fontSize:12,color:C.muted)),
          ])),
        const SizedBox(height:28),
        SizedBox(width:double.infinity, child: ElevatedButton.icon(onPressed:_play,
          icon:const Icon(Icons.play_arrow_rounded), label:const Text('ENTER LOBBY'))),
      ],
    )))),
  );
}

// ── LOBBY ───────────────────────────────────────────────────────────────────
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.callsign});
  final String callsign;
  @override State<LobbyScreen> createState() => _LobbyScreenState();
}
class _LobbyScreenState extends State<LobbyScreen> {
  final _net = NetworkService.instance;
  final _codeCtrl = TextEditingController();
  late final IO.Socket _socket;
  String? _roomId;
  bool _isHost = false, _selfReady = false, _scanning = false;
  String _status = 'IDLE';
  List<Map<String,dynamic>> _players = [];
  String _mode = HitMode.normal;
  double _range = 80, _angle = 12;

  @override void initState() { super.initState(); _socket = _net.connect(); _bind(); }

  void _bind() {
    _socket.onConnect((_)=>_setStatus('CONNECTED'));
    _socket.onConnectError((_)=>_setStatus('CONNECTION ERROR'));
    _socket.onReconnect((_)=>_setStatus('RECONNECTED'));
    _socket.onDisconnect((_)=>_setStatus('RECONNECTING'));
    _socket.on('room_mode',(data){ if(!mounted||data is! Map) return;
      setState((){ _mode=(data['mode']??_mode).toString(); _range=(data['rangeM'] is num)?(data['rangeM'] as num).toDouble():_range; _angle=(data['angleDeg'] is num)?(data['angleDeg'] as num).toDouble():_angle; }); });
    _socket.on('room_created',(data){ if(!mounted) return;
      setState((){ _roomId=(data as Map)['roomId'].toString(); _isHost=true; _status='WAITING FOR PLAYER'; }); });
    _socket.on('room_joined',(data){ if(!mounted) return;
      setState((){ _roomId=(data as Map)['roomId'].toString(); _status='JOINED ROOM'; }); });
    _socket.on('lobby_update',(data){ if(!mounted) return;
      final list=(data is Map&&data['players'] is List)?data['players'] as List:[];
      setState((){ _players=list.map((e)=>Map<String,dynamic>.from(e as Map)).toList(); }); });
    _socket.on('join_error',(data){ if(!mounted) return;
      setState((){ _status=(data is Map&&data['message']!=null)?data['message'].toString():'INVALID ROOM'; _scanning=false; }); });
    _socket.on('start_countdown',(_)=>_goToGame());
  }
  void _unbind() { for(final e in ['room_mode','room_created','room_joined','lobby_update','join_error','start_countdown']) _socket.off(e); }
  void _setStatus(String v) { if(!mounted) return; setState(()=>_status=v); }
  void _host() => _socket.emit('host_room',{'name':widget.callsign});
  void _joinByCode() {
    final code=_codeCtrl.text.trim().toUpperCase();
    if(code.isEmpty){ setState(()=>_status='ENTER A ROOM CODE'); return; }
    FocusScope.of(context).unfocus();
    _socket.emit('join_room',{'roomId':code,'name':widget.callsign});
  }
  void _setMode(String m) => _socket.emit('set_room_mode',{'roomId':_roomId,'mode':m});
  void _toggleReady() {
    if(_roomId==null) return;
    setState(()=>_selfReady=!_selfReady);
    _socket.emit('player_ready',{'roomId':_roomId,'ready':_selfReady});
  }
  void _onScan(BarcodeCapture cap) {
    if(cap.barcodes.isEmpty) return;
    final code=cap.barcodes.first.rawValue;
    if(code==null||code.trim().isEmpty){ setState(()=>_status='INVALID QR CODE'); return; }
    setState(()=>_scanning=false);
    _socket.emit('join_room',{'roomId':code.trim(),'name':widget.callsign});
  }
  void _goToGame() {
    final id=_roomId; if(id==null||!mounted) return;
    _unbind();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder:(_)=>GameplayScreen(
      socket:_socket, roomId:id, isHost:_isHost, callsign:widget.callsign,
      initialMode:_mode, initialRange:_range, initialAngle:_angle)));
  }
  void _leaveLobby() { _socket.emit('leave_game',{'roomId':_roomId}); _unbind(); Navigator.of(context).pop(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(icon:const Icon(Icons.arrow_back_ios_new,color:C.accent),
        onPressed: _scanning?()=>setState(()=>_scanning=false):_leaveLobby),
      title: const Text('LOBBY',style:TextStyle(letterSpacing:4,fontWeight:FontWeight.w900))),
    body: _scanning?_buildScanner():_buildLobby());

  Widget _buildScanner() => Stack(children:[
    MobileScanner(onDetect:_onScan),
    Align(alignment:Alignment.bottomCenter, child:Padding(padding:const EdgeInsets.all(24),
      child:ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor:C.danger,foregroundColor:Colors.white),
        onPressed:()=>setState(()=>_scanning=false), child:const Text('CANCEL')))),
  ]);

  Widget _statusChip() => Container(
    padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
    decoration:BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(20)),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.wifi_tethering,size:16,color:C.accent), const SizedBox(width:8),
      Text(_status,style:const TextStyle(fontSize:13,color:C.muted,letterSpacing:1))]));

  Widget _modeSelector() {
    Widget chip(String m, String title, IconData icon) {
      final sel=_mode==m;
      return Expanded(child:GestureDetector(onTap:()=>_setMode(m),child:Container(
        margin:const EdgeInsets.symmetric(horizontal:4), padding:const EdgeInsets.symmetric(vertical:12),
        decoration:BoxDecoration(color:sel?modeColor(m).withOpacity(0.15):C.panel2,borderRadius:BorderRadius.circular(12),
          border:Border.all(color:sel?modeColor(m):Colors.transparent,width:1.5)),
        child:Column(children:[Icon(icon,color:sel?modeColor(m):C.muted,size:20),const SizedBox(height:6),
          Text(title,style:TextStyle(fontSize:11,fontWeight:FontWeight.bold,color:sel?modeColor(m):C.muted))]))));
    }
    return Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(16)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('HIT MODE — applies to both players',style:TextStyle(fontSize:12,color:C.muted,letterSpacing:1)),
        const SizedBox(height:10),
        Row(children:[chip(HitMode.normal,'NORMAL',Icons.verified),chip(HitMode.test,'TEST',Icons.science),chip(HitMode.walls,'WALLS',Icons.layers_clear)]),
        const SizedBox(height:8),
        Text(modeLabel(_mode,_range,_angle),style:TextStyle(fontSize:12,color:modeColor(_mode),fontWeight:FontWeight.bold))]));
  }

  Widget _playerTile(Map<String,dynamic> p, bool isMe) {
    final ready=p['ready']==true;
    return Container(margin:const EdgeInsets.symmetric(vertical:6),padding:const EdgeInsets.symmetric(horizontal:16,vertical:14),
      decoration:BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(14),
        border:Border.all(color:ready?C.accent:C.panel2,width:1.5)),
      child:Row(children:[
        Icon(isMe?Icons.person:Icons.person_outline,color:ready?C.accent:C.muted),const SizedBox(width:12),
        Expanded(child:Text('${p['name']??'PLAYER'}${isMe?'  (you)':''}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
        Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
          decoration:BoxDecoration(color:ready?C.accent.withOpacity(0.15):C.panel2,borderRadius:BorderRadius.circular(20)),
          child:Text(ready?'READY':'NOT READY',style:TextStyle(fontSize:12,fontWeight:FontWeight.bold,color:ready?C.accent:C.muted)))]));
  }

  Widget _buildLobby() {
    final myId=_socket.id;
    return SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(children:[
      _statusChip(), const SizedBox(height:24),
      if(_roomId==null)...[
        const SizedBox(height:10), const Icon(Icons.sports_esports,size:56,color:C.muted), const SizedBox(height:22),
        SizedBox(width:double.infinity,child:ElevatedButton.icon(onPressed:_host,icon:const Icon(Icons.add_circle_outline),label:const Text('HOST ROOM'))),
        const SizedBox(height:22),
        const Row(children:[Expanded(child:Divider(color:C.panel2)),
          Padding(padding:EdgeInsets.symmetric(horizontal:10),child:Text('OR JOIN',style:TextStyle(color:C.muted,letterSpacing:2))),
          Expanded(child:Divider(color:C.panel2))]),
        const SizedBox(height:16),
        Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:C.panel,borderRadius:BorderRadius.circular(16)),child:Column(children:[
          TextField(controller:_codeCtrl,maxLength:6,textCapitalization:TextCapitalization.characters,textAlign:TextAlign.center,
            inputFormatters:[FilteringTextInputFormatter.allow(RegExp('[a-fA-F0-9]')),
              TextInputFormatter.withFunction((o,n)=>n.copyWith(text:n.text.toUpperCase()))],
            style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900,letterSpacing:6),
            decoration:InputDecoration(counterText:'',hintText:'ABC123',filled:true,fillColor:C.panel2,
              border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none)),
            onSubmitted:(_)=>_joinByCode()),
          const SizedBox(height:12),
          SizedBox(width:double.infinity,child:ElevatedButton.icon(onPressed:_joinByCode,icon:const Icon(Icons.login),label:const Text('JOIN BY CODE'))),
          const SizedBox(height:10),
          SizedBox(width:double.infinity,child:ElevatedButton.icon(
            style:ElevatedButton.styleFrom(backgroundColor:C.panel2,foregroundColor:Colors.white),
            onPressed:()=>setState(()=>_scanning=true),icon:const Icon(Icons.qr_code_scanner),label:const Text('SCAN QR'))),
        ])),
      ] else ...[
        if(_isHost) Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),
          child:QrImageView(data:_roomId!,size:200)),
        const SizedBox(height:14),
        SelectableText('ROOM  $_roomId',style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,letterSpacing:3)),
        const SizedBox(height:6),
        const Text('Share this code with your opponent',style:TextStyle(fontSize:12,color:C.muted)),
        const SizedBox(height:18),
        _modeSelector(), const SizedBox(height:18),
        const Align(alignment:Alignment.centerLeft,child:Text('PLAYERS',style:TextStyle(fontSize:12,color:C.muted,letterSpacing:2))),
        const SizedBox(height:6),
        ..._players.map((p)=>_playerTile(p,p['id']==myId)),
        if(_players.length<2) const Padding(padding:EdgeInsets.symmetric(vertical:10),
          child:Text('Waiting for opponent…',style:TextStyle(color:C.muted))),
        const SizedBox(height:24),
        SizedBox(width:double.infinity,child:ElevatedButton(
          style:ElevatedButton.styleFrom(backgroundColor:_selfReady?C.accent:C.panel2,
            foregroundColor:_selfReady?Colors.black:Colors.white,padding:const EdgeInsets.symmetric(vertical:20)),
          onPressed:_toggleReady, child:Text(_selfReady?'READY ✓':'TAP TO READY'))),
      ],
    ])));
  }
}

// ── GAMEPLAY ─────────────────────────────────────────────────────────────────
enum GamePhase { countdown, active, ended }

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key,required this.socket,required this.roomId,required this.isHost,
    required this.callsign,this.initialMode=HitMode.normal,this.initialRange=80,this.initialAngle=12});
  final IO.Socket socket;
  final String roomId, callsign, initialMode;
  final bool isHost;
  final double initialRange, initialAngle;
  @override State<GameplayScreen> createState() => _GameplayScreenState();
}
class _GameplayScreenState extends State<GameplayScreen> {
  CameraController? _camera;
  final _sensors = SensorService();
  Timer? _telemetryTimer, _renderTimer;
  GamePhase _phase = GamePhase.countdown;
  String _countdownLabel = '3';
  static const _maxAmmo = 30;
  int _ammo = _maxAmmo, _hp = 100, _myKills = 0, _myDeaths = 0;
  bool _alive = true, _reloading = false;
  double _orangeFlash = 0, _redFlash = 0;
  String _endReason = '', _respawnText = '';
  late String _mode; late double _range, _angle;
  String _oppName = 'OPPONENT';
  double? _oppLat, _oppLng;
  bool _oppGps = false;

  @override
  void initState() {
    super.initState();
    _mode=widget.initialMode; _range=widget.initialRange; _angle=widget.initialAngle;
    _startSensors(); _bind(); _initCamera();
    _renderTimer=Timer.periodic(const Duration(milliseconds:120),(_){if(mounted)setState((){});});
  }

  Future<void> _startSensors() async {
    await _sensors.start();
    _telemetryTimer=Timer.periodic(const Duration(milliseconds:300),(_){
      widget.socket.emit('telemetry',{'roomId':widget.roomId,'heading':_sensors.heading,'lat':_sensors.lat,'lng':_sensors.lng});
    });
  }

  Future<void> _initCamera() async {
    if(gCameras.isEmpty) return;
    final rear=gCameras.firstWhere((c)=>c.lensDirection==CameraLensDirection.back,orElse:()=>gCameras.first);
    final ctrl=CameraController(rear,ResolutionPreset.high,enableAudio:false);
    try { await ctrl.initialize(); } catch(_){ return; }
    if(!mounted){ await ctrl.dispose(); return; }
    setState(()=>_camera=ctrl);
  }

  void _bind() {
    widget.socket.on('room_mode',(data){ if(!mounted||data is! Map) return;
      setState((){ _mode=(data['mode']??_mode).toString(); _range=(data['rangeM'] is num)?(data['rangeM'] as num).toDouble():_range; _angle=(data['angleDeg'] is num)?(data['angleDeg'] as num).toDouble():_angle; }); });
    widget.socket.on('countdown',(data){ if(!mounted) return;
      final c=(data is Map&&data['count']!=null)?(data['count'] as num).toInt():0;
      setState((){_phase=GamePhase.countdown;_countdownLabel=c>0?c.toString():'GO!';}); });
    widget.socket.on('game_start',(_){ if(!mounted) return; setState(()=>_phase=GamePhase.active); });
    widget.socket.on('hit_confirmed',(_)=>_flashOrange());
    widget.socket.on('shot_missed',(_){});
    widget.socket.on('hit_taken',(data){ if(!mounted) return;
      final hp=(data is Map&&data['hp']!=null)?(data['hp'] as num).toInt():_hp;
      setState(()=>_hp=hp); _flashRed(); });
    widget.socket.on('opponent_telemetry',(data){ if(!mounted||data is! Map) return;
      setState((){ _oppName=(data['name']??_oppName).toString();
        _oppLat=(data['lat'] is num)?(data['lat'] as num).toDouble():null;
        _oppLng=(data['lng'] is num)?(data['lng'] as num).toDouble():null;
        _oppGps=data['hasGps']==true; }); });
    widget.socket.on('fragged',(data){ if(!mounted||data is! Map) return;
      final myId=widget.socket.id??'';
      if(data['killer']==myId) setState(()=>_myKills+=1);
      if(data['victim']==myId) setState((){ _myDeaths+=1; _alive=false; _respawnText='ELIMINATED BY ${data['killerName']??'ENEMY'}'; }); });
    widget.socket.on('respawn',(data){ if(!mounted) return;
      final hp=(data is Map&&data['hp']!=null)?(data['hp'] as num).toInt():100;
      setState((){ _hp=hp; _alive=true; _ammo=_maxAmmo; _reloading=false; _respawnText=''; }); });
    widget.socket.on('game_ended',(data){ if(!mounted) return;
      setState((){ _phase=GamePhase.ended; _endReason=(data is Map&&data['reason']!=null)?data['reason'].toString():'GAME ENDED'; }); });
  }

  void _flashOrange(){ if(!mounted) return; setState(()=>_orangeFlash=0.30);
    Future.delayed(const Duration(milliseconds:250),(){if(mounted)setState(()=>_orangeFlash=0);}); }
  void _flashRed(){ if(!mounted) return; setState(()=>_redFlash=0.50);
    Future.delayed(const Duration(milliseconds:350),(){if(mounted)setState(()=>_redFlash=0);}); }

  void _shoot() {
    if(_phase!=GamePhase.active||!_alive||_reloading||_ammo<=0) return;
    setState(()=>_ammo-=1);
    widget.socket.emit('shoot',{'roomId':widget.roomId,'heading':_sensors.heading,'lat':_sensors.lat,'lng':_sensors.lng});
  }
  void _reload() {
    if(_phase!=GamePhase.active||_reloading||!_alive) return;
    setState(()=>_reloading=true);
    Future.delayed(const Duration(seconds:2),(){if(!mounted) return; setState((){_ammo=_maxAmmo;_reloading=false;});});
  }
  void _setMode(String m) => widget.socket.emit('set_room_mode',{'roomId':widget.roomId,'mode':m});
  void _openModePicker() {
    showModalBottomSheet(context:context,backgroundColor:C.panel,
      shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(20))),
      builder:(ctx){ Widget tile(String m,String title,String sub,IconData icon){
        final sel=_mode==m;
        return ListTile(leading:Icon(icon,color:sel?modeColor(m):C.muted),
          title:Text(title,style:TextStyle(fontWeight:FontWeight.bold,color:sel?modeColor(m):Colors.white)),
          subtitle:Text(sub,style:const TextStyle(color:C.muted)),
          trailing:sel?Icon(Icons.check,color:modeColor(m)):null,
          onTap:(){ _setMode(m); Navigator.pop(ctx); });
      }
      return SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Padding(padding:EdgeInsets.all(16),child:Text('HIT MODE',style:TextStyle(letterSpacing:3,fontWeight:FontWeight.w900,fontSize:16))),
        tile(HitMode.normal,'NORMAL','80 m / 12° — real aiming',Icons.verified),
        tile(HitMode.test,'TEST','300 m / 45° — long range',Icons.science),
        tile(HitMode.walls,'THROUGH WALLS','hit anywhere, no aiming',Icons.layers_clear),
        const SizedBox(height:12)]));});
  }
  void _leaveToMenu() {
    widget.socket.emit('leave_game',{'roomId':widget.roomId});
    Navigator.of(context).popUntil((r)=>r.isFirst);
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel(); _renderTimer?.cancel(); _sensors.stop(); _camera?.dispose();
    for(final e in ['room_mode','countdown','game_start','hit_confirmed','shot_missed','hit_taken','opponent_telemetry','fragged','respawn','game_ended'])
      widget.socket.off(e);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam=_camera; final sz=MediaQuery.of(context).size;
    return Scaffold(backgroundColor:Colors.black,body:Stack(fit:StackFit.expand,children:[
      cam!=null&&cam.value.isInitialized?CameraPreview(cam):const ColoredBox(color:Colors.black),
      IgnorePointer(child:AnimatedContainer(duration:const Duration(milliseconds:100),color:Colors.orange.withOpacity(_orangeFlash))),
      IgnorePointer(child:AnimatedContainer(duration:const Duration(milliseconds:100),color:Colors.red.withOpacity(_redFlash))),
      if(_phase==GamePhase.active) _buildOpponentLayer(sz.width,sz.height),
      if(_phase==GamePhase.active&&_alive) _buildCrosshair(),
      if(_phase==GamePhase.active) _buildHud(),
      if(_phase==GamePhase.active&&!_alive) _buildRespawnOverlay(),
      if(_phase==GamePhase.countdown) _buildCountdown(),
      if(_phase==GamePhase.ended) _buildEnded(),
      _buildModeTag(),
    ]));
  }

  Widget _buildModeTag() => Positioned(top:MediaQuery.of(context).padding.top+6,left:0,right:0,
    child:Center(child:Text(modeLabel(_mode,_range,_angle).toUpperCase(),
      style:TextStyle(fontSize:11,color:modeColor(_mode),letterSpacing:2,fontWeight:FontWeight.bold))));

  String _gpsHint(){ if(_sensors.gpsDenied) return 'LOCATION DENIED — enable to see opponent';
    if(!_sensors.gpsReady) return 'ACQUIRING GPS…'; if(!_oppGps) return 'WAITING FOR OPPONENT GPS…'; return 'SEARCHING…'; }

  Widget _buildOpponentLayer(double w,double h){
    final have=_oppLat!=null&&_oppLng!=null&&_sensors.lat!=null&&_sensors.lng!=null;
    if(!have) return Positioned(top:h*0.16,left:0,right:0,child:Center(child:_hintChip(_gpsHint())));
    final b=bearingBetween(_sensors.lat!,_sensors.lng!,_oppLat!,_oppLng!);
    final dist=distanceMeters(_sensors.lat!,_sensors.lng!,_oppLat!,_oppLng!);
    final rel=normalizeSigned(b-_sensors.heading);
    const fovHalf=35.0;
    if(rel.abs()<=fovHalf){
      double x=(w/2+(rel/fovHalf)*(w/2-70)).clamp(70,w-70);
      return Positioned(left:x-70,top:h*0.28,child:_targetMarker(dist));
    }
    return Positioned(left:rel<0?14:null,right:rel<0?null:14,top:h*0.42,child:_edgeArrow(rel<0,dist));
  }

  Widget _hintChip(String t) => Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:8),
    decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(20)),
    child:Text(t,style:const TextStyle(fontSize:13,color:C.warn,letterSpacing:1)));

  Widget _targetMarker(double dist) => Column(mainAxisSize:MainAxisSize.min,children:[
    Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
      decoration:BoxDecoration(color:C.danger.withOpacity(0.85),borderRadius:BorderRadius.circular(8)),
      child:Text(_oppName,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w900,color:Colors.white))),
    const SizedBox(height:4), const Icon(Icons.crop_free,color:C.danger,size:90), const SizedBox(height:4),
    Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
      decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(8)),
      child:Text(prettyDistance(dist),style:const TextStyle(fontSize:13,fontWeight:FontWeight.bold,color:C.accent)))]);

  Widget _edgeArrow(bool left,double dist) => Column(mainAxisSize:MainAxisSize.min,children:[
    Icon(left?Icons.arrow_back_ios_new:Icons.arrow_forward_ios,color:C.warn,size:40),const SizedBox(height:6),
    Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
      decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(8)),
      child:Column(children:[Text(_oppName,style:const TextStyle(fontSize:12,fontWeight:FontWeight.bold)),
        Text(prettyDistance(dist),style:const TextStyle(fontSize:12,color:C.accent))]))]);

  Widget _buildCrosshair() => const Center(child:Icon(Icons.add,color:C.accent,size:56));

  Widget _buildHud() => SafeArea(child:Padding(padding:const EdgeInsets.all(14),child:Stack(children:[
    Align(alignment:Alignment.topLeft,child:Row(children:[
      _badge(Icons.favorite,'$_hp',_hp>30?C.accent:C.danger),const SizedBox(width:8),
      _badge(Icons.military_tech,'$_myKills : $_myDeaths',C.warn)])),
    Align(alignment:Alignment.topRight,child:Row(mainAxisSize:MainAxisSize.min,children:[
      _badge(Icons.bolt,'$_ammo/$_maxAmmo',Colors.white),const SizedBox(width:8),
      GestureDetector(onTap:_openModePicker,child:Container(padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(10),border:Border.all(color:modeColor(_mode),width:1)),
        child:Icon(modeIcon(_mode),color:modeColor(_mode),size:22))),
      const SizedBox(width:8),
      GestureDetector(onTap:_leaveToMenu,child:Container(padding:const EdgeInsets.all(10),
        decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(10)),
        child:const Icon(Icons.exit_to_app,color:C.danger,size:22)))])),
    Align(alignment:Alignment.bottomCenter,child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
      _actionButton(_reloading?'RELOADING':'RELOAD',C.panel2,_reload,Icons.autorenew),
      _actionButton('FIRE',C.danger,_shoot,Icons.gps_fixed)]))])));

  Widget _badge(IconData icon,String text,Color color) => Container(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
    decoration:BoxDecoration(color:Colors.black54,borderRadius:BorderRadius.circular(10)),
    child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:18,color:color),const SizedBox(width:6),
      Text(text,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))]));

  Widget _actionButton(String label,Color color,VoidCallback onTap,IconData icon) => ElevatedButton.icon(
    onPressed:onTap,style:ElevatedButton.styleFrom(backgroundColor:color,foregroundColor:Colors.white,
      padding:const EdgeInsets.symmetric(horizontal:24,vertical:18)),
    icon:Icon(icon,size:20),label:Text(label,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)));

  Widget _buildCountdown() => Container(color:Colors.black54,child:Center(
    child:Text(_countdownLabel,style:const TextStyle(fontSize:88,fontWeight:FontWeight.w900,color:Colors.white))));

  Widget _buildRespawnOverlay() => Container(color:Colors.red.withOpacity(0.25),child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.dangerous,color:C.danger,size:70),const SizedBox(height:12),
    Text(_respawnText,textAlign:TextAlign.center,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
    const SizedBox(height:8),const Text('RESPAWNING…',style:TextStyle(fontSize:16,color:C.warn,letterSpacing:2))])));

  Widget _buildEnded() => Container(color:Colors.black87,child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Text('GAME OVER',style:TextStyle(fontSize:48,fontWeight:FontWeight.w900,letterSpacing:4)),
    const SizedBox(height:8),Text(_endReason,style:const TextStyle(fontSize:16,color:C.muted)),
    const SizedBox(height:16),Text('FRAGS  $_myKills   DEATHS  $_myDeaths',style:const TextStyle(fontSize:18,color:C.accent,fontWeight:FontWeight.bold)),
    const SizedBox(height:28),ElevatedButton(onPressed:()=>Navigator.of(context).popUntil((r)=>r.isFirst),child:const Text('RETURN TO MENU'))])));
}
DART_EOF

# --- VPS SERVER PACKAGE ---
cat << 'PKG_EOF' > server/package.json
{
  "name": "argeym-server",
  "version": "1.3.0",
  "private": true,
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": { "socket.io": "^4.7.5" }
}
PKG_EOF

# --- VPS SERVER ---
cat << 'SERVER_EOF' > server/server.js
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
SERVER_EOF

# ── CI/CD ────────────────────────────────────────────────────────────────────
cat << 'YML_EOF' > .github/workflows/build.yml
name: AR Shooter Cross-Platform Build

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  # ── iOS ────────────────────────────────────────────────────────────────────
  build-ios:
    name: Build Unsigned iOS IPA
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, flutter-version: '3.24.5' }
      - run: flutter create --org com.argeym --project-name argeym --platforms=ios,android .
      - name: Inject iOS permissions
        run: |
          P=ios/Runner/Info.plist
          CAM="Argeym uses the rear camera to render the live AR battlefield."
          LOC="Argeym uses your location to measure distance and bearing to your opponent."
          /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription $CAM" "$P" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string $CAM" "$P"
          /usr/libexec/PlistBuddy -c "Set :NSLocationWhenInUseUsageDescription $LOC" "$P" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string $LOC" "$P"
      - run: flutter pub get
      - run: flutter build ios --release --no-codesign
      - run: |
          mkdir -p build/ipa/Payload
          cp -r build/ios/iphoneos/Runner.app build/ipa/Payload/Runner.app
          cd build/ipa && zip -r -q app-release.ipa Payload
      - uses: actions/upload-artifact@v4
        with: { name: ios-release-ipa, path: build/ipa/app-release.ipa }

  # ── Android ────────────────────────────────────────────────────────────────
  build-android:
    name: Build Android APK
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: zulu, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, flutter-version: '3.24.5' }

      - name: Generate native projects
        run: flutter create --org com.argeym --project-name argeym --platforms=ios,android .

      - name: Inject Android permissions
        run: |
          M=android/app/src/main/AndroidManifest.xml
          grep -q "CAMERA" "$M" || sed -i 's|<application|<uses-permission android:name="android.permission.CAMERA"/>\n    <application|' "$M"
          grep -q "ACCESS_FINE_LOCATION" "$M" || sed -i 's|<application|<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application|' "$M"
          grep -q "INTERNET" "$M" || sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"

      # ── THE FIX ─────────────────────────────────────────────────────────────
      # geolocator_android ≤4.4.x (used by geolocator ^10.1.1) reads
      # flutter.compileSdkVersion from the Flutter Gradle plugin's extension.
      # That extension is NOT available in the root project scope used by
      # subprojects{} hacks.  The only 100% reliable fix is to supply a
      # local.properties key that the plugin reads BEFORE it evaluates its
      # own build.gradle.  Flutter's Gradle plugin exposes compileSdkVersion
      # via the "flutter" extension only to library sub-projects it owns;
      # for third-party plugins it falls back to local.properties.
      # ────────────────────────────────────────────────────────────────────────
      - name: Pin compileSdkVersion in local.properties
        run: |
          # Ensure the file exists (flutter create already makes it, but be safe)
          touch android/local.properties
          # Remove any existing compileSdkVersion line then append the correct one
          grep -v "^flutter.compileSdkVersion" android/local.properties > android/local.properties.tmp \
            && mv android/local.properties.tmp android/local.properties
          echo "flutter.compileSdkVersion=34" >> android/local.properties
          echo "flutter.minSdkVersion=21"     >> android/local.properties
          echo "flutter.targetSdkVersion=34"  >> android/local.properties
          cat android/local.properties

      - run: flutter pub get
      - run: flutter build apk --release

      - uses: actions/upload-artifact@v4
        with: { name: android-release-apk, path: build/app/outputs/flutter-apk/app-release.apk }
YML_EOF

# --- .gitignore ---
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

# --- GIT ---
if [ -n "$ARGEYM_SKIP_GIT" ]; then echo "Skipping git."; exit 0; fi
[ ! -d .git ] && git init
git checkout -B main
git add -A
git commit -m "ARGEYM: fix geolocator compileSdk via local.properties"
git remote remove origin 2>/dev/null || true
git remote add origin "https://<INSERT_TOKEN_HERE>@github.com/dophycoder/argeym.git"
git push -u origin main --force