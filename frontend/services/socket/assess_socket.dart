// lib/services/socket/assess_socket.dart

import 'dart:async';
import 'request_response.dart';
import 'socket_manager.dart';

/// AssessSocket
/// - Starts an 'assess' job and exposes streaming or one-shot APIs.
/// - Server contract (expected):
///    Client sends: { type: "assess", request_id: "...", payload: { partner_id, topic, messages } }
///    Server streams: { type: "assess", request_id: "...", payload: { progress/ chunk / result / status } }
///    Final message must indicate completion: payload.status == 'done' or payload contains 'result'
class AssessSocket {
  AssessSocket();

  /// Start an assessment job and return a Stream of `assess` events for this request.
  ///
  /// The returned Stream only emits events where:
  ///   event['type'] == 'assess' && event['request_id'] == requestId
  ///
  /// If you supply `requestId`, that id will be used (useful for tests or correlation).
  /// Otherwise a new request_id is generated.
  Future<Stream<Map<String, dynamic>>> startAssessment({
    required String partnerId,
    required String topic,
    required List<Map<String, String>> messages,
    String? requestId,
  }) async {
    final rid = requestId ?? RequestResponse.instance.nextRequestId();

    // Best-effort: try to connect; if it fails, send() will buffer the payload.
    try {
      await SocketManager.instance.connect();
    } catch (_) {
      // ignore: send will buffer
    }

    final envelope = {
      'type': 'assess',
      'request_id': rid,
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {
        'partner_id': partnerId,
        'topic': topic,
        'messages': messages,
      },
      'meta': {'version': '1.0'}
    };

    SocketManager.instance.send(envelope, bufferIfDisconnected: true);

    // Return filtered stream for this assessment job
    return SocketManager.instance.streamFor('assess', requestId: rid);
  }

  /// Convenience: start an assessment and await the final message (one-shot).
  ///
  /// Uses RequestResponse.sendAndWaitFinal so ack/final detection and timeouts are centralized.
  /// The returned Map is the final server message (including request_id and payload).
  Future<Map<String, dynamic>> startAssessmentOnce({
    required String partnerId,
    required String topic,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    // Best-effort try to connect
    try {
      await SocketManager.instance.connect();
    } catch (_) {
      // ignore - RequestResponse will still send and wait (SocketManager buffers)
    }

    final payload = {
      'type': 'assess',
      'request_id': RequestResponse.instance.nextRequestId(),
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {
        'partner_id': partnerId,
        'topic': topic,
        'messages': messages,
      },
      'meta': {'version': '1.0'}
    };

    return await RequestResponse.instance.sendAndWaitFinal(payload, timeout: timeout);
  }

  /// Cancel a running assessment job. Server should honor and stop processing.
  /// Provide the same requestId you started the job with.
  void cancelAssessment(String requestId) {
    final envelope = {
      'type': 'cancel',
      'request_id': requestId,
      'client_ts': DateTime.now().toIso8601String(),
      'meta': {'reason': 'user_cancelled'}
    };

    SocketManager.instance.send(envelope, bufferIfDisconnected: true);
  }
}
