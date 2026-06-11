import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late sio.Socket _socket;
  bool _connected = false;

  final StreamController<Map<String, dynamic>> _lobbyController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _stateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _opponentsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _firedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _hitController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _killedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _respawnedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _roomDeletedController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get lobbyStream => _lobbyController.stream;
  Stream<Map<String, dynamic>> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get opponentsStream => _opponentsController.stream;
  Stream<Map<String, dynamic>> get firedStream => _firedController.stream;
  Stream<Map<String, dynamic>> get hitStream => _hitController.stream;
  Stream<Map<String, dynamic>> get killedStream => _killedController.stream;
  Stream<Map<String, dynamic>> get respawnedStream => _respawnedController.stream;
  Stream<String> get roomDeletedStream => _roomDeletedController.stream;
  Stream<String> get errorStream => _errorController.stream;

  bool get isConnected => _connected;
  String get socketId => _socket.id ?? '';

  void connect(String serverUrl) {
    _socket = sio.io(serverUrl, sio.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setTimeout(5000)
        .build());

    _socket.onConnect((_) {
      _connected = true;
      debugPrint('[Socket] Connected: ${_socket.id}');
    });

    _socket.onDisconnect((_) {
      _connected = false;
      debugPrint('[Socket] Disconnected');
    });

    _socket.onConnectError((err) {
      _connected = false;
      _errorController.add('Connection failed: $err');
      debugPrint('[Socket] Connect error: $err');
    });

    _socket.onConnectTimeout((_) {
      _connected = false;
      _errorController.add('Connection timed out');
      debugPrint('[Socket] Connect timeout');
    });

    _socket.on('lobby_update', (data) {
      _lobbyController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('state_change', (data) {
      _stateController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('opponents_update', (data) {
      _opponentsController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('player_fired', (data) {
      _firedController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('player_hit', (data) {
      _hitController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('player_killed', (data) {
      _killedController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('player_respawned', (data) {
      _respawnedController.add(Map<String, dynamic>.from(data));
    });

    _socket.on('room_deleted', (data) {
      final reason = data is Map ? (data['reason'] ?? 'Unknown') : data.toString();
      _roomDeletedController.add(reason);
    });

    _socket.connect();
  }

  void createRoom(String nickname, Function(Map<String, dynamic>) callback) {
    _socket.emitWithAck('create_room', {'nickname': nickname}).then((response) {
      callback(Map<String, dynamic>.from(response));
    });
  }

  void joinRoom(String roomId, String nickname, Function(Map<String, dynamic>) callback) {
    _socket.emitWithAck('join_room', {
      'roomId': roomId,
      'nickname': nickname
    }).then((response) {
      callback(Map<String, dynamic>.from(response));
    });
  }

  void updatePosition(double lat, double lon, double heading) {
    _socket.emit('update_position', {
      'lat': lat,
      'lon': lon,
      'heading': heading
    });
  }

  void fire(double heading) {
    _socket.emit('fire', {'heading': heading});
  }

  void respawn() {
    _socket.emit('respawn');
  }

  void leaveRoom() {
    _socket.emit('leave_room');
  }

  void disconnect() {
    _socket.dispose();
    _connected = false;
  }

  void dispose() {
    _lobbyController.close();
    _stateController.close();
    _opponentsController.close();
    _firedController.close();
    _hitController.close();
    _killedController.close();
    _respawnedController.close();
    _roomDeletedController.close();
    _errorController.close();
    disconnect();
  }
}
