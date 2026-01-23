// lib/services/socket/chat_socket.dart

import 'dart:async';
import 'package:uuid/uuid.dart';
import 'request_response.dart';
import 'socket_manager.dart';

/// SendResult: returned by sendMessageOptimistic.
/// - localId: the client-generated id you should use to render optimistic UI.
/// - ack: future that resolves when server acknowledges / confirms the message.
class SendResult {
  final String localId;
  final Future<Map<String, dynamic>> ack;
  SendResult({required this.localId, required this.ack});
}

/// ChatSocket - a thin domain wrapper for chat behavior on top of SocketManager.
///
/// Responsibilities:
///  - create stable request_id (localId) for optimistic UI
///  - send envelope: { type: 'chat', request_id, payload: {...} }
///  - wait for ack (server may reply with {type:'ack', ack_for: localId} or {type:'chat', request_id: localId})
///  - broadcast incoming chat messages via `incomingChatStream`
class ChatSocket {
  ChatSocket._internal() {
    _uuid = const Uuid();
    _pendingAcks = <String, Completer<Map<String, dynamic>>>{};

    // Subscribe to the unified socket incoming stream for lifetime of app
    _incomingSub = SocketManager.instance.incoming.listen(
      _handleIncoming,
      onError: (err) {
        // propagate to listeners or log if needed
      },
    );

    // Optional: subscribe to connection state to surface failures for pending messages
    _connSub = SocketManager.instance.connectionStream.listen((connected) {
      if (!connected) {
        // mark all pending as errored after a short grace period if desired.
        // For now, do not auto-fail; keep pending so they can resolve after reconnect.
      }
    });
  }

  static final ChatSocket instance = ChatSocket._internal();

  // --- internals ---
  late final Uuid _uuid;
  late final Map<String, Completer<Map<String, dynamic>>> _pendingAcks;
  late final StreamSubscription _incomingSub;
  StreamSubscription<bool>? _connSub;

  final StreamController<Map<String, dynamic>> _chatController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Public stream for chat messages. Emits maps from server where type == 'chat'
  /// (also delivery/receipt/typing events forwarded here).
  Stream<Map<String, dynamic>> get incomingChatStream => _chatController.stream;

  /// Timeout for ack waiting
  Duration ackTimeout = const Duration(seconds: 15);

  /// Send a chat message optimistically.
  ///
  /// Returns a SendResult containing:
  ///  - localId: immediate client id (use it to render optimistic message)
  ///  - ack: Future that resolves to the server ack/message when the server acknowledges
  ///
  /// Server ack patterns supported:
  ///  - { type: 'ack', ack_for: '<localId>', payload: { server_message_id: 'm123' } }
  ///  - { type: 'chat', request_id: '<localId>', payload: { ... } } (server echoes final message)
  Future<SendResult> sendMessageOptimistic({
    required String to,
    required String text,
    Map<String, dynamic>? metadata,
    bool bufferIfDisconnected = true,
  }) async {
    // Ensure socket manager attempts to connect (non-blocking)
    try {
      await SocketManager.instance.connect();
    } catch (e) {
      // connect may fail but we still want to allow buffering; proceed to send which will buffer
    }

    // Use RequestResponse to generate consistent UUIDs across system
    final localId = RequestResponse.instance.nextRequestId();

    final envelope = {
      'type': 'chat',
      'request_id': localId,
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {
        'to': to,
        'text': text,
        if (metadata != null) 'meta': metadata,
      },
      'meta': {'version': '1.0'}
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingAcks[localId] = completer;

    // Send via SocketManager (it will buffer if disconnected)
    try {
      SocketManager.instance.send(envelope, bufferIfDisconnected: bufferIfDisconnected);
    } catch (e) {
      // immediate send failure
      _pendingAcks.remove(localId);
      completer.completeError(e);
      return SendResult(localId: localId, ack: completer.future);
    }

    // ack timeout guard: if no ack within ackTimeout, complete with error
    final timer = Timer(ackTimeout, () {
      if (!completer.isCompleted) {
        _pendingAcks.remove(localId);
        completer.completeError(TimeoutException('No ack received for message $localId within ${ackTimeout.inSeconds}s'));
      }
    });

    // when completer completes, cancel timer
    completer.future.whenComplete(() => timer.cancel());

    return SendResult(localId: localId, ack: completer.future);
  }

  /// Mark a pending message as failed from UI (retry/cancel workflows)
  void markFailed(String localId, [Object? error]) {
    final c = _pendingAcks.remove(localId);
    if (c != null && !c.isCompleted) {
      c.completeError(error ?? Exception('Marked as failed by client'));
    }
  }

  /// Retry a previously failed message using the same localId (server should accept duplicate request_id or treat as retry)
  Future<SendResult> retryWithLocalId({
    required String localId,
    required String to,
    required String text,
    Map<String, dynamic>? metadata,
    bool bufferIfDisconnected = true,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    _pendingAcks[localId] = completer;

    final envelope = {
      'type': 'chat',
      'request_id': localId,
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {
        'to': to,
        'text': text,
        if (metadata != null) 'meta': metadata,
      },
      'meta': {'version': '1.0', 'retry': true}
    };

    await SocketManager.instance.connect();
    SocketManager.instance.send(envelope, bufferIfDisconnected: bufferIfDisconnected);

    final timer = Timer(ackTimeout, () {
      if (!completer.isCompleted) {
        _pendingAcks.remove(localId);
        completer.completeError(TimeoutException('No ack received for retried message $localId within ${ackTimeout.inSeconds}s'));
      }
    });

    completer.future.whenComplete(() => timer.cancel());

    return SendResult(localId: localId, ack: completer.future);
  }

  /// Handle raw incoming messages from SocketManager
  void _handleIncoming(Map<String, dynamic> msg) {
    try {
      final t = msg['type'] is String ? msg['type'] as String : null;

      if (t == null) return;

      // 1) Acks
      if (t == 'ack') {
        // Server might use ack_for or request_id or payload.ack_for
        final ackFor = _extractAckFor(msg);
        if (ackFor != null) {
          _completePending(ackFor, msg);
          // don't forward ack messages as chat
          return;
        }
      }

      // 2) Chat messages (server echo or messages from others)
      if (t == 'chat') {
        final reqId = msg['request_id'];
        if (reqId != null && reqId is String && _pendingAcks.containsKey(reqId)) {
          // treat echoed chat as confirmation
          _completePending(reqId, msg);
        }

        // forward to listeners (both inbound new messages and server-echoed messages)
        _chatController.add(msg);
        return;
      }

      // 3) Other chat-related events (delivery, receipt, typing, presence)
      if (t == 'delivery' || t == 'receipt' || t == 'typing' || t == 'presence') {
        _chatController.add(msg);
        return;
      }

      // 4) Unknown type — ignore or optionally forward/log
    } catch (e) {
      // ignore malformed messages
    }
  }

  /// Helper: try to complete pending completer for requestId with message
  void _completePending(String requestId, Map<String, dynamic> msg) {
    final completer = _pendingAcks.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(msg);
    }
  }

  /// Helper: extract ack_for from different possible shapes
  String? _extractAckFor(Map<String, dynamic> msg) {
    try {
      final v1 = msg['ack_for'];
      if (v1 is String && v1.isNotEmpty) return v1;
      final v2 = msg['request_id'];
      if (v2 is String && v2.isNotEmpty) return v2;
      final payload = msg['payload'];
      if (payload is Map && payload['ack_for'] is String) return payload['ack_for'] as String;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clean up resources (unsubscribe handlers). Call on app dispose if desired.
  Future<void> dispose() async {
    try {
      await _incomingSub.cancel();
    } catch (_) {}
    try {
      await _connSub?.cancel();
    } catch (_) {}

    if (!_chatController.isClosed) await _chatController.close();

    // Complete remaining pending acks with an error
    for (final e in _pendingAcks.entries) {
      if (!e.value.isCompleted) e.value.completeError(Exception('ChatSocket disposed'));
    }
    _pendingAcks.clear();
  }
}
