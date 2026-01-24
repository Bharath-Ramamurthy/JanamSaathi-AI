// lib/services/socket/socket_manager.dart

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart' show IOWebSocketChannel;
import 'package:web_socket_channel/html.dart' show HtmlWebSocketChannel;
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart'; // relative to lib/services/socket/

/// SocketManager
/// Single shared WebSocket connection manager used by domain sockets (chat/report/assess)
/// and RequestResponse. Initialize once at app start:
///   SocketManager.initialize(apiService: ApiService(), wsPath: '/ws');
///
/// Usage:
///   await SocketManager.instance.connect();
///   SocketManager.instance.send({...});
///   SocketManager.instance.streamFor('chat').listen(...);
class SocketManager {
  // ---------- Singleton ----------
  static SocketManager? _instance;
  static SocketManager get instance {
    if (_instance == null) {
      throw StateError('SocketManager is not initialized. Call initialize(...) first.');
    }
    return _instance!;
  }

  /// Initialize once. Provide ApiService so manager can refresh tokens when needed.
  static void initialize({required ApiService apiService, String wsPath = '/ws'}) {
    if (_instance != null) return;
    _instance = SocketManager._internal(apiService, wsPath);
  }

  // ---------- Internals ----------
  final ApiService _api;
  final String _wsPath;
  WebSocketChannel? _channel;

  // Broadcast incoming parsed JSON messages
  final StreamController<Map<String, dynamic>> _incomingController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Broadcast connection state: true = connected, false = disconnected
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  // Buffer outgoing messages while offline
  final Queue<Map<String, dynamic>> _outgoingBuffer = Queue<Map<String, dynamic>>();

  // Connection/bookkeeping flags
  bool _connected = false;
  bool _connecting = false;
  int _reconnectAttempts = 0;
  final int _reconnectMaxAttempts = 12;
  Timer? _heartbeatTimer;
  Duration _heartbeatInterval = const Duration(seconds: 30);

  // Internal subscription reference to raw channel stream
  StreamSubscription? _channelSub;

  // Random generator for jitter
  final Random _rand = Random();

  // Private constructor
  SocketManager._internal(this._api, this._wsPath);

  // ---------- Public API ----------

  /// Connect non-blocking. Manager handles reconnect/backoff.
  Future<void> connect() async {
    if (_connected || _connecting) return;
    _connecting = true;
    try {
      await _attemptConnectWithAuth();
    } finally {
      _connecting = false;
    }
  }

  /// Whether socket currently appears connected
  bool get isConnected => _connected;

  /// Stream of parsed incoming JSON messages (broadcast).
  Stream<Map<String, dynamic>> get incoming => _incomingController.stream;

  /// Stream of connection state changes (broadcast).
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Send JSON-serializable Map. If disconnected and bufferIfDisconnected==true, message is buffered.
  void send(Map<String, dynamic> data, {bool bufferIfDisconnected = true}) {
    final payload = jsonEncode(data);
    if (_connected && _channel != null) {
      try {
        _channel!.sink.add(payload);
      } catch (e) {
        if (bufferIfDisconnected) _outgoingBuffer.addLast(data);
      }
    } else {
      if (bufferIfDisconnected) _outgoingBuffer.addLast(data);
    }
  }

  /// Convenience filtered stream by message 'type' and optional 'request_id'
  Stream<Map<String, dynamic>> streamFor(String type, {String? requestId}) {
    if (requestId == null) {
      return incoming.where((m) => m['type'] == type);
    } else {
      return incoming.where((m) => m['type'] == type && (m['request_id'] == requestId));
    }
  }

  /// Graceful disconnect. Stops heartbeat and closes connection.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectAttempts = 0;
    _connected = false;
    _connectionController.add(false);
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    await _channelSub?.cancel();
    _channelSub = null;
  }

  /// Dispose resources entirely (incoming controllers, etc.)
  Future<void> dispose() async {
    await disconnect();
    try {
      await _incomingController.close();
    } catch (_) {}
    try {
      await _connectionController.close();
    } catch (_) {}
  }

  // ---------- Internal helpers ----------

  Future<void> _attemptConnectWithAuth() async {
    final token = await _getAccessTokenFromPrefs();
    if (token == null) {
      _connecting = false;
      throw StateError('No auth token found in SharedPreferences');
    }

    try {
      await _connect(token);
      _reconnectAttempts = 0;
      _flushBuffer();
    } catch (e) {
      // Try refresh token once then retry connecting
      try {
        await _api.refreshToken();
        final refreshed = await _getAccessTokenFromPrefs();
        if (refreshed == null) throw e;
        await _connect(refreshed);
        _reconnectAttempts = 0;
        _flushBuffer();
      } catch (e2) {
        _scheduleReconnect();
      }
    }
  }

  Future<void> _connect(String token) async {
    final uri = _buildWsUri(token);
    try {
      if (kIsWeb) {
        // Browser implementation (headers ignored by browsers)
        _channel = HtmlWebSocketChannel.connect(uri.toString());
      } else {
        // Native/desktop implementation allows headers
        _channel = IOWebSocketChannel.connect(uri, headers: _wsHeaders(token));
      }

      // Cancel previous subscription if any
      await _channelSub?.cancel();

      _channelSub = _channel!.stream.listen(
        _onRawData,
        onDone: _onDone,
        onError: _onError,
        cancelOnError: true,
      );

      _connected = true;
      _connectionController.add(true);
      _startHeartbeat();
    } catch (e) {
      _connected = false;
      _connectionController.add(false);
      rethrow;
    }
  }

  /// UPDATED: Build WebSocket URI using backendHost and fixed port
  Uri _buildWsUri(String token) {
    final scheme = (_api.baseUrl.startsWith('https')) ? 'wss' : 'ws';
    final port = 8000; // WebSocket port (optional)
    
    return Uri(
      scheme: scheme,
      host: _api.backendHost,
      port: port,
      path: _wsPath,
      queryParameters: kIsWeb ? {'token': token} : null,
    );
  }

  Map<String, dynamic> _wsHeaders(String token) {
    return kIsWeb ? {} : {'Authorization': 'Bearer $token'};
  }

  Future<String?> _getAccessTokenFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authToken');
  }

  void _onRawData(dynamic raw) {
    try {
      if (raw == null) return;
      final String str = raw is String ? raw : (raw is List<int> ? utf8.decode(raw) : raw.toString());
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) {
        _incomingController.add(decoded);
      } else {
        // Optionally wrap arrays or other payloads
      }
    } catch (e) {
      // Malformed JSON - ignore or log in debug
      // print('SocketManager: malformed incoming data: $e');
    }
  }

  void _onDone() {
    _connected = false;
    _connectionController.add(false);
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
  }

  void _onError(dynamic err) {
    _connected = false;
    _connectionController.add(false);
    _heartbeatTimer?.cancel();
    _scheduleReconnect();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_connected && _channel != null) {
        try {
          final ping = {'type': 'ping', 'ts': DateTime.now().toIso8601String()};
          _channel!.sink.add(jsonEncode(ping));
        } catch (_) {}
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _reconnectMaxAttempts) {
      return;
    }

    _reconnectAttempts += 1;
    final baseBackoff = 2 * _reconnectAttempts;
    final jitterFactor = (_rand.nextDouble() * 0.5) - 0.25; // [-0.25, +0.25]
    final backoffSeconds = max(1, (baseBackoff * (1 + jitterFactor)).round());
    final delay = Duration(seconds: backoffSeconds);

    Future.delayed(delay, () async {
      if (!_connected && !_connecting) {
        _connecting = true;
        try {
          try {
            await _api.refreshToken();
          } catch (_) {}
          final token = await _getAccessTokenFromPrefs();
          if (token != null) {
            await _connect(token);
            _reconnectAttempts = 0;
            _flushBuffer();
          }
        } catch (e) {
          _scheduleReconnect();
        } finally {
          _connecting = false;
        }
      }
    });
  }

  void _flushBuffer() {
    while (_outgoingBuffer.isNotEmpty && _connected && _channel != null) {
      final msg = _outgoingBuffer.removeFirst();
      try {
        _channel!.sink.add(jsonEncode(msg));
      } catch (e) {
        _outgoingBuffer.addFirst(msg);
        break;
      }
    }
  }
}
