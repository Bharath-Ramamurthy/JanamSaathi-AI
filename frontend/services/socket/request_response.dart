// lib/services/socket/request_response.dart

import 'dart:async';
import 'dart:collection';
import 'package:uuid/uuid.dart';
import 'socket_manager.dart';

/// RequestResponse
/// Utility to correlate requests sent over the unified WebSocket with responses.
///
/// Usage patterns:
///   final rid = RequestResponse.instance.nextRequestId();
///   payload['request_id'] = rid;
///   final ack = RequestResponse.instance.sendWithAck(payload);
///   // or await final result:
///   final finalMsg = await RequestResponse.instance.sendAndWaitFinal(payload);
///
/// Behavior:
///  - sendWithAck: completes when the server sends an 'ack' (or an echoed 'chat' message)
///                 or when a final message arrives for that request_id (flexible).
///  - sendAndWaitFinal: completes only when server sends a message for request_id that
///                      indicates completion (payload.status == 'done' or payload contains 'result')
class RequestResponse {
  RequestResponse._internal() {
    _incomingSub = SocketManager.instance.incoming.listen(_onIncoming, onError: (err) {
      // propagate or log if you want; currently we complete pending futures with error on incoming stream error
      _completeAllWithError(err);
    });
  }

  static final RequestResponse instance = RequestResponse._internal();

  final Uuid _uuid = const Uuid();

  /// pending map: request_id -> completer
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  /// We keep an auxiliary map for sendAndWaitFinal to know which completer expects final-only
  final Set<String> _awaitFinalOnly = HashSet<String>();

  late final StreamSubscription<Map<String, dynamic>> _incomingSub;

  /// Generate a new request id (UUID v4)
  String nextRequestId() => _uuid.v4();

  /// Send a payload and return a Future that resolves on ack or final (configurable timeout).
  ///
  /// The provided payload MUST NOT already contain a request_id (this method will add one).
  /// If the server responds with:
  ///   - { type: 'ack', request_id: '<rid>' }  --> resolves
  ///   - { type: '<any>', request_id: '<rid>', payload: { status: 'done' | 'error' } } --> resolves
  ///
  /// Throws TimeoutException on timeout.
  Future<Map<String, dynamic>> sendWithAck(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final rid = nextRequestId();
    payload['request_id'] = rid;

    final completer = Completer<Map<String, dynamic>>();
    _pending[rid] = completer;

    // Send via SocketManager (it will buffer if disconnected)
    SocketManager.instance.send(payload);

    // Wait for ack/final or timeout
    try {
      final res = await completer.future.timeout(timeout, onTimeout: () {
        _pending.remove(rid);
        _awaitFinalOnly.remove(rid);
        throw TimeoutException('No ack/response for request $rid within ${timeout.inSeconds}s');
      });
      return res;
    } finally {
      // ensure cleanup if completer already completed
      _pending.remove(rid);
      _awaitFinalOnly.remove(rid);
    }
  }

  /// Send a payload and wait until the server sends a final message for the request_id.
  ///
  /// Final message detection rules:
  ///  - msg['request_id'] == rid
  ///  - AND (msg['payload']?.['status'] == 'done' OR msg['payload'] contains 'result' OR msg['type'] == 'error')
  Future<Map<String, dynamic>> sendAndWaitFinal(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final rid = nextRequestId();
    payload['request_id'] = rid;

    final completer = Completer<Map<String, dynamic>>();
    _pending[rid] = completer;
    _awaitFinalOnly.add(rid);

    SocketManager.instance.send(payload);

    try {
      final res = await completer.future.timeout(timeout, onTimeout: () {
        _pending.remove(rid);
        _awaitFinalOnly.remove(rid);
        throw TimeoutException('No final response for request $rid within ${timeout.inSeconds}s');
      });
      return res;
    } finally {
      _pending.remove(rid);
      _awaitFinalOnly.remove(rid);
    }
  }

  /// Internal incoming message handler: routes incoming messages to pending completers
  void _onIncoming(Map<String, dynamic> msg) {
    try {
      final dynamic ridRaw = msg['request_id'];
      final String? rid = ridRaw is String ? ridRaw : (ridRaw?.toString());
      final String? type = msg['type'] is String ? msg['type'] as String : null;
      final dynamic payload = msg['payload'];

      if (rid == null) {
        // No request_id → nothing to correlate for RequestResponse
        return;
      }

      if (!_pending.containsKey(rid)) {
        // no one is waiting for this request_id
        return;
      }

      final completer = _pending[rid]!;

      // If caller asked for final-only, only complete on final signals
      if (_awaitFinalOnly.contains(rid)) {
        final bool isFinal = _isFinalMessage(msg);
        if (isFinal) {
          if (!completer.isCompleted) completer.complete(msg);
        }
        // else ignore intermediate messages (streaming); don't complete yet
        return;
      }

      // For sendWithAck (default), accept ack OR final as completion:
      //  - type == 'ack' -> complete
      //  - type == 'error' -> completeError
      //  - payload.status == 'done' OR payload contains 'result' -> complete with msg
      if (type == 'ack') {
        if (!completer.isCompleted) completer.complete(msg);
        return;
      }

      if (type == 'error') {
        if (!completer.isCompleted) completer.completeError(Exception(msg));
        return;
      }

      // If message contains final indicator, complete with it
      if (_isFinalMessage(msg)) {
        if (!completer.isCompleted) completer.complete(msg);
        return;
      }

      // As a fallback: if server echoes request_id in a message type equal to original (some servers do),
      // complete the completer (this is optional/lenient).
      if (type != null && type != 'report' && type != 'assess' && type != 'chat') {
        // don't auto-complete for typical streaming types unless final/ack
      }
    } catch (e) {
      // ignore parse errors; do not crash the listener
    }
  }

  bool _isFinalMessage(Map<String, dynamic> msg) {
    try {
      final dynamic payload = msg['payload'];
      if (payload is Map<String, dynamic>) {
        final status = payload['status'];
        if (status == 'done' || status == 'error') return true;
        if (payload.containsKey('result')) return true;
      }
      // Alternatively, server might include a top-level 'final' flag
      if (msg.containsKey('final') && (msg['final'] == true || msg['final'] == 'true')) return true;
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Helper to complete all pending futures with an error (used when incoming stream errors)
  void _completeAllWithError(Object err) {
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(err);
      }
    }
    _pending.clear();
    _awaitFinalOnly.clear();
  }

  /// Dispose subscription (call during app shutdown to free resources)
  Future<void> dispose() async {
    try {
      await _incomingSub.cancel();
    } catch (_) {}
    _completeAllWithError(Exception('RequestResponse disposed'));
  }
}
