// lib/services/socket/report_socket.dart

import 'dart:async';
import 'request_response.dart';
import 'socket_manager.dart';

/// ReportSocket
/// - Starts a 'view_report' job and exposes streaming or one-shot APIs.
/// - Server contract (expected):
///    Client sends: { type: "view_report", request_id: "...", payload: { partner_id: "..." } }
///    Server streams: { type: "report", request_id: "...", payload: { ... } }
///    Final message must indicate completion: payload.status == 'done' or payload contains 'result'
class ReportSocket {
  ReportSocket();

  /// Start a view-report job and return a Stream of `report` events for this request.
  ///
  /// The returned Stream only emits events where:
  ///   event['type'] == 'report' && event['request_id'] == requestId
  ///
  /// If you supply `requestId`, that id will be used (useful for tests or correlation).
  /// Otherwise a new request_id is generated.
  Future<Stream<Map<String, dynamic>>> fetchReportStream({
    required String partnerId,
    String? requestId,
  }) async {
    final rid = requestId ?? RequestResponse.instance.nextRequestId();

    // Best-effort ensure socket tries to connect; failures here are non-fatal because
    // SocketManager.send will buffer if disconnected.
    try {
      await SocketManager.instance.connect();
    } catch (_) {
      // ignore — send() will buffer the request if disconnected
    }

    final envelope = {
      'type': 'view_report',
      'request_id': rid,
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {'partner_id': partnerId},
      'meta': {'version': '1.0'}
    };

    SocketManager.instance.send(envelope, bufferIfDisconnected: true);

    // Return filtered stream from SocketManager
    return SocketManager.instance.streamFor('report', requestId: rid);
  }

  /// Convenience: start a report job and await its final message (one-shot).
  ///
  /// Uses RequestResponse.sendAndWaitFinal so ack/final detection and timeouts are centralized.
  /// The returned Map is the final server message (including request_id and payload).
  Future<Map<String, dynamic>> fetchReportOnce({
    required String partnerId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Ensure connection attempt
    try {
      await SocketManager.instance.connect();
    } catch (_) {
      // ignore; RequestResponse will still send and wait (SocketManager buffers)
    }

    final payload = {
      'type': 'view_report',
      'client_ts': DateTime.now().toIso8601String(),
      'payload': {'partner_id': partnerId},
      'meta': {'version': '1.0'}
    };

    // sendAndWaitFinal will add request_id and wait for final message (payload.status == 'done' or contains 'result')
    return await RequestResponse.instance.sendAndWaitFinal(payload, timeout: timeout);
  }

  /// Cancel a running report job. Server should honor and stop processing.
  /// Provide the same requestId you started the job with.
  void cancelReport(String requestId) {
    final envelope = {
      'type': 'cancel',
      'request_id': requestId,
      'client_ts': DateTime.now().toIso8601String(),
      'meta': {'reason': 'user_cancelled'}
    };

    SocketManager.instance.send(envelope, bufferIfDisconnected: true);
  }
}
