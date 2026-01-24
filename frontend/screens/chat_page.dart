import 'dart:async';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/socket/socket_manager.dart';
import '../services/socket/chat_socket.dart';
import '../services/socket/assess_socket.dart';
import '../services/socket/request_response.dart';
import 'view_report_page.dart';

class ChatPage extends StatefulWidget {
  final String senderId;
  final String receiverId;
  final String backendHost;
  final String? receiverName;
  final String? topic;

  const ChatPage({
    super.key,
    required this.senderId,
    required this.receiverId,
    required this.backendHost,
    this.receiverName,
    this.topic,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService apiService = ApiService();

  StreamSubscription<Map<String, dynamic>>? _msgSub;

  bool _isAssessing = false;
  late String _topic;
  List<Map<String, String>> messages = [];

  final Map<String, String> _topicLabels = {
    "future_goals": "Where do you see us in 5 years?",
    "money_conflict": "How should we handle disagreements about money?",
    "emotional_vulnerability": "What are your biggest fears in relationships?",
    "family_values": "How important is family to you?",
  };

  bool _showAssessOverlay = false;
  int _currentAssessStep = 0;
  String _assessStatusText = 'Initializing...';
  StreamSubscription<Map<String, dynamic>>? _assessSub;
  Timer? _assessTimeoutTimer;

  // These are the only statuses shown on the UI during assessment (per your request).
  final List<String> _assessSteps = [
    "Fetching chat messages",
    "Analysing the sentiments using AI",
    "Generating compatibility score",
    "Creating/updating report",
    "Generating horoscope compatibility",
    "Finalizing",
  ];

  @override
  void initState() {
    super.initState();
    _topic = widget.topic ?? "future_goals";
    _initSocketSubscriptions();
  }

  void _onTopicSelected(String topic) {
    setState(() {
      _topic = topic;
    });
  }

  Future<void> _initSocketSubscriptions() async {
    try {
      await SocketManager.instance.connect();
    } catch (_) {}

    _msgSub = ChatSocket.instance.incomingChatStream.listen(
      (msg) {
        try {
          final payload = (msg['payload'] is Map<String, dynamic>)
              ? msg['payload'] as Map<String, dynamic>
              : <String, dynamic>{};
          final sender = (payload['from'] ??
                  payload['sender'] ??
                  msg['from'] ??
                  msg['sender'] ??
                  'system')
              .toString();
          final text =
              (payload['text'] ?? payload['message'] ?? msg['text'] ?? '')
                  .toString();

          if (mounted) {
            setState(() {
              messages.add({"sender": sender, "text": text});
            });
            _scrollToBottom();
          }
        } catch (_) {
          final raw = msg.toString();
          if (mounted) {
            setState(() => messages.add({"sender": "system", "text": raw}));
            _scrollToBottom();
          }
        }
      },
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Chat stream error: $err')));
        }
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (mounted) {
      setState(() => messages.add({
            "sender": widget.senderId,
            "text": text,
            "topic": _topic,
          }));
      _controller.clear();
      _scrollToBottom();
    }

    try {
      final sendResult = await ChatSocket.instance.sendMessageOptimistic(
        to: widget.receiverId,
        text: text,
        metadata: {"topic": _topic},
      );

      sendResult.ack.then((ackMsg) {}).catchError((err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Message send failed: $err')));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startAssessment() async {
    if (_isAssessing) return;
    setState(() {
      _isAssessing = true;
      _showAssessOverlay = true;
      _currentAssessStep = 0;
      _assessStatusText =
          'Conversation analysis using AI on ${_topicLabels[_topic] ?? _topic}...';
    });

    final List<Map<String, String>> msgs = messages.map((m) {
      return {'sender': m['sender'] ?? '', 'text': m['text'] ?? ''};
    }).toList();

    try {
      await _assessSub?.cancel();
      _assessTimeoutTimer?.cancel();

      _assessTimeoutTimer = Timer(const Duration(seconds: 90), () {
        _cancelAssessmentFlow('Assessment timed out.');
      });

      _assessSub = (await AssessSocket().startAssessment(
        partnerId: widget.receiverId,
        topic: _topic,
        messages: msgs,
      ))
          .listen(
        (msg) {
          try {
            final payload = msg['payload'] ?? {};
            final stage =
                (payload['stage'] ?? payload['status'] ?? '').toString();

            if (stage.isNotEmpty) {
              _updateAssessmentStage(stage, null);
            }

            if (payload['status'] == 'done' || payload['result'] != null) {
              _finishAssessment(payload['result'] ?? payload);
            }
          } catch (e) {
            _cancelAssessmentFlow('Bad assessment message: $e');
          }
        },
        onError: (err) {
          _cancelAssessmentFlow('Assessment error: $err');
        },
        cancelOnError: true,
      );
    } catch (e) {
      _cancelAssessmentFlow('Failed to start assessment: $e');
    }
  }

  // ✅ UPDATED VERSION
  void _updateAssessmentStage(String stage, String? message) {
    final lower = stage.toLowerCase();

    // Don't show any "done" or "final" label
    if (lower.contains('done') || lower.contains('final')) {
      // Progress will complete visually inside _finishAssessment()
      return;
    }

    int stepIndex = _currentAssessStep;
    if (lower.contains('fetch')) stepIndex = 0;
    else if (lower.contains('sentiment') || lower.contains('analyse')) stepIndex = 1;
    else if (lower.contains('score') || lower.contains('generated')) stepIndex = 2;
    else if (lower.contains('report')) stepIndex = 3;
    else if (lower.contains('horoscope')) stepIndex = 4;

    if (mounted) {
      setState(() {
        _currentAssessStep = stepIndex.clamp(0, _assessSteps.length - 1);
        _assessStatusText = _assessSteps[_currentAssessStep];
      });
    }
  }

  // ✅ UPDATED VERSION
  Future<void> _finishAssessment(Map<String, dynamic> result) async {
    _assessTimeoutTimer?.cancel();
    await _assessSub?.cancel();

    if (!mounted) return;

    // Smoothly animate progress to 100% before closing overlay
    setState(() {
      _currentAssessStep = _assessSteps.length - 1; // Full progress (100%)
      _assessStatusText = "Finalizing...";
    });

    // Wait a short moment to visually complete the progress
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() {
      _isAssessing = false;
      _showAssessOverlay = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Assessment complete')),
    );
  }

  Future<void> _cancelAssessmentFlow(String errorMsg) async {
    _assessTimeoutTimer?.cancel();
    await _assessSub?.cancel();

    if (!mounted) return;
    setState(() {
      _isAssessing = false;
      _showAssessOverlay = false;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorMsg)));
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _assessSub?.cancel();
    _assessTimeoutTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildMessageTile(Map<String, String> m) {
    final sender = m['sender'] ?? '';
    final text = m['text'] ?? '';
    final isMe = sender == widget.senderId;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: isMe ? Colors.blue.shade200 : Colors.grey.shade200,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(widget.receiverName ?? widget.receiverId),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ViewReportPage(partnerId: widget.receiverId),
                          ),
                        );
                      },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  "assets/report.png",
                                  width: 93,
                                  height: 93,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              "Report",
                              style: TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _isAssessing
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          )
                        : GestureDetector(
                            onTap: _startAssessment,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipOval(
                                      child: Image.asset(
                                        "assets/compatability.webp",
                                        width: 93,
                                        height: 93,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    "Assess",
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
                    child: DropdownButton<String>(
                      value: _topic,
                      isExpanded: true,
                      items: _topicLabels.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _onTopicSelected(val);
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4),
                    child: Text(
                      "Chat on the selected topic for 10–15 minutes, then click 'AI Analyse button' (top-right) for accurate results.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade900,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, idx) => _buildMessageTile(messages[idx]),
                ),
              ),
              const Divider(height: 1),
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _sendMessage,
                        child: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showAssessOverlay)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Assessing: ${_topicLabels[_topic] ?? _topic}\n$_assessStatusText',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: (_currentAssessStep + 1) / (_assessSteps.length),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
