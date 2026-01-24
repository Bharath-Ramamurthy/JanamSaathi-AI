// lib/screens/view_report_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/socket/report_socket.dart';

class ViewReportPage extends StatefulWidget {
  final String partnerId;

  const ViewReportPage({
    super.key,
    required this.partnerId,
  });

  @override
  State<ViewReportPage> createState() => _ViewReportPageState();
}

class _ViewReportPageState extends State<ViewReportPage> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _errorMessage;

  // Socket-driven flow
  bool _showSocketOverlay = true;
  int _currentStep = 0;
  String _statusText = 'checking if report already exists';
  StreamSubscription<Map<String, dynamic>>? _reportSub;
  Timer? _reportTimeout;

  final List<String> _steps = [
    'Checking if report already exists',
	'Creating the report',
    'Fetching the report',
    'Generating horoscope compatibility',
    'Updating the report',
  ];

  @override
  void initState() {
    super.initState();
    _startReportSocketFlow();
  }

  @override
  void dispose() {
    _reportSub?.cancel();
    _reportTimeout?.cancel();
    super.dispose();
  }

  Future<void> _startReportSocketFlow() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
      _showSocketOverlay = true;
      _currentStep = 0;
      _statusText = _steps[0];
    });

    try {
      final Stream<Map<String, dynamic>> stream =
          await ReportSocket().fetchReportStream(partnerId: widget.partnerId);

      await _reportSub?.cancel();
      _reportTimeout?.cancel();

      _reportTimeout = Timer(const Duration(seconds: 90), () {
        _cancelSocketFlow('Report generation timed out.');
      });

      _reportSub = stream.listen(
        (msg) {
          try {
            _handleReportMessage(msg);
          } catch (e) {
            _cancelSocketFlow('Unexpected socket message format.');
          }
        },
        onError: (err) {
          _cancelSocketFlow('Socket error: $err');
        },
        cancelOnError: true,
      );
    } catch (e) {
      _cancelSocketFlow('Failed to start socket flow: $e');
    }
  }

  void _handleReportMessage(Map<String, dynamic> msg) {
    final dynamic payload = msg['payload'] ?? msg;
    Map<String, dynamic>? payloadMap;
    String? stage;

    if (payload is Map<String, dynamic>) {
      payloadMap = payload;
      stage = (payload['stage'] ?? payload['status'] ?? payload['step'])?.toString();
    } else {
      stage = (msg['stage'] ?? msg['status'])?.toString();
    }

    final lower = stage?.toLowerCase();

    if (lower != null && (lower.contains('check') || lower.contains('exists'))) {
      _setStep(0, payloadMap?['message']?.toString() ?? _steps[0]);
      final exists = payloadMap?['exists'] == true || payloadMap?['exists'] == 'true';
      _setStep(exists ? 1 : 2, exists ? 'Fetching the report' : 'Creating the report');
      return;
    }

    if (lower != null && lower.contains('update')) {
      _setStep(1, payloadMap?['message']?.toString() ?? 'Updating the report');
      final isDone = payloadMap?['status'] == 'done' ||
          payloadMap?.containsKey('result') == true ||
          payloadMap?['final'] == true;
      if (isDone) {
        _finishWithReportFromPayload(payloadMap);
      }
      return;
    }

    if (lower != null && lower.contains('create')) {
      _setStep(2, payloadMap?['message']?.toString() ?? 'creating the report');
      return;
    }

    if (lower != null && (lower.contains('horoscope') || lower.contains('astro'))) {
      _setStep(3, payloadMap?['message']?.toString() ?? 'generating horoscope compatibility');
      return;
    }

    if (lower != null && (lower.contains('done') || lower.contains('final') || lower.contains('result'))) {
      _finishWithReportFromPayload(payloadMap ?? msg);
      return;
    }

    if (payloadMap != null &&
        (payloadMap['result'] is Map<String, dynamic> ||
            payloadMap['report'] is Map<String, dynamic> ||
            payloadMap['data'] is Map<String, dynamic>)) {
      _finishWithReportFromPayload(payloadMap);
      return;
    }

    final maybeMsg = payloadMap?['message']?.toString() ?? payload?.toString() ?? '';
    if (maybeMsg.isNotEmpty) {
      final next = (_currentStep + 1).clamp(0, _steps.length - 1);
      _setStep(next, maybeMsg);
    }
  }

  void _setStep(int stepIndex, String statusText) {
    if (!mounted) return;
    setState(() {
      _currentStep = stepIndex.clamp(0, _steps.length - 1);
      _statusText = statusText;
    });
  }

  Future<void> _finishWithReportFromPayload(Map<String, dynamic>? payload) async {
    _reportTimeout?.cancel();
    await _reportSub?.cancel();

    Map<String, dynamic>? finalReport;

    if (payload == null) {
      finalReport = null;
    } else if (payload['result'] is Map<String, dynamic>) {
      finalReport = Map<String, dynamic>.from(payload['result']);
    } else if (payload['report'] is Map<String, dynamic>) {
      finalReport = Map<String, dynamic>.from(payload['report']);
    } else if (payload['data'] is Map<String, dynamic>) {
      finalReport = Map<String, dynamic>.from(payload['data']);
    } else {
      finalReport = Map<String, dynamic>.from(payload);
    }

    if (!mounted) return;
    setState(() {
      _report = finalReport;
      _loading = false;
      _showSocketOverlay = false;
      _errorMessage = null;
    });
  }

  Future<void> _cancelSocketFlow(String errorMsg) async {
    _reportTimeout?.cancel();
    await _reportSub?.cancel();

    if (!mounted) return;
    setState(() {
      _showSocketOverlay = false;
      _loading = false;
      _errorMessage = errorMsg;
    });
  }

  String _formatScore(dynamic raw) {
    if (raw == null) return 'N/A';
    final s = raw.toString().trim().toLowerCase();
    if (s.contains('no data') || s.contains('not found') || s.contains('invalid')) {
      return raw.toString();
    }

    final d = double.tryParse(raw.toString());
    if (d != null) {
      double value = d;
      if (value > 0 && value <= 1) value *= 100;
      if (value > 100) value = 100;
      return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
    }

    return raw.toString();
  }

  Widget _buildReportContent() {
    if (_report == null || _report!.isEmpty) {
      return const Center(child: Text("No report found."));
    }

    final rawHoroscope = _report!['horoscope_score'] ??
        _report!['horoscope_compatibility'] ??
        'N/A';
    final rawCompatibility = _report!['compatibility_score'] ??
        _report!['sentiment_avg'] ??
        'N/A';

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildScoreCard("Horoscope Score", _formatScore(rawHoroscope)),
        const SizedBox(height: 16),
        _buildScoreCard("Compatibility Score", _formatScore(rawCompatibility)),
      ],
    );
  }

  Widget _buildScoreCard(String title, String value) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            Container(
              height: 64,
              width: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurple.shade50,
              ),
              alignment: Alignment.center,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.45),
        child: Center(
          child: Card(
            elevation: 12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Preparing report', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(_statusText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 18),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(_steps.length, (i) {
                        final stepText = _steps[i];
                        final isCurrent = i == _currentStep;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: isCurrent
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Opacity(
                                  opacity: isCurrent ? 1.0 : 0.4,
                                  child: Text(
                                    stepText,
                                    style: TextStyle(
                                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                      color: isCurrent ? Colors.black : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await _reportSub?.cancel();
                            _reportTimeout?.cancel();
                            if (!mounted) return;
                            setState(() {
                              _showSocketOverlay = true;
                              _loading = true;
                              _errorMessage = null;
                              _currentStep = 0;
                              _statusText = _steps[0];
                            });
                            await _startReportSocketFlow();
                          },
                          child: const Text('Retry'),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            await _reportSub?.cancel();
                            _reportTimeout?.cancel();
                            if (!mounted) return;
                            setState(() {
                              _showSocketOverlay = false;
                              _loading = false;
                              _errorMessage = 'Socket flow cancelled by user.';
                            });
                          },
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compatibility Report'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: "Back",
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry socket flow',
            onPressed: () {
              _startReportSocketFlow();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(child: Text(_errorMessage!))
                  : _buildReportContent(),
          if (_showSocketOverlay) _buildOverlay(),
        ],
      ),
    );
  }
}
