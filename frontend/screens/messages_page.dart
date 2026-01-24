// lib/ui/pages/messages_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../services/api.dart';
import '../../screens/chat_page.dart';

class MessagesPage extends StatefulWidget {
  final ApiService apiService;

  const MessagesPage({Key? key, required this.apiService}) : super(key: key);

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = _loadConversations();
  }

  Future<List<Conversation>> _loadConversations() async {
    final raw = await widget.apiService.fetchConversations();
    final parsed = _parseConversations(raw);
    return parsed;
  }

  Future<void> _refresh() async {
    final future = _loadConversations();
    if (!mounted) return;
    setState(() {
      _conversationsFuture = future;
    });
    await _conversationsFuture;
  }

  Future<String> _currentUserId() async {
    final prefs = await SharedPreferences.getInstance();

    final possible = <String?>[
      prefs.getString('userId'),
      prefs.getString('user_id'),
      prefs.getString('id'),
      prefs.getString('userid'),
    ];
    for (final v in possible) {
      if (v != null && v.isNotEmpty) return v;
    }

    final profileStr = prefs.getString('user_profile');
    if (profileStr != null && profileStr.isNotEmpty) {
      try {
        final profile = jsonDecode(profileStr);
        if (profile is Map && (profile['id'] != null || profile['user_id'] != null)) {
          return (profile['id'] ?? profile['user_id']).toString();
        }
      } catch (_) {}
    }

    return '';
  }

  List<Conversation> _parseConversations(dynamic raw) {
    final List<dynamic> rawList = <dynamic>[];

    if (raw is List) {
      rawList.addAll(raw);
    } else if (raw is Map<String, dynamic>) {
      if (raw['conversations'] is List) {
        rawList.addAll(raw['conversations'] as List);
      } else if (raw['data'] is List) {
        rawList.addAll(raw['data'] as List);
      } else {
        final firstList = raw.values.whereType<List>().firstWhere(
              (_) => true,
              orElse: () => <dynamic>[],
            );
        rawList.addAll(firstList);
      }
    } else if (raw is String) {
      try {
        final parsed = jsonDecode(raw);
        return _parseConversations(parsed);
      } catch (_) {
        return [Conversation(id: '', name: raw)];
      }
    }

    final out = <Conversation>[];
    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        out.add(Conversation.fromJson(item));
      } else if (item is String) {
        try {
          final parsed = jsonDecode(item);
          if (parsed is Map<String, dynamic>) {
            out.add(Conversation.fromJson(parsed));
            continue;
          }
        } catch (_) {}
        out.add(Conversation(id: '', name: item));
      } else {
        out.add(Conversation.empty());
      }
    }
    return out;
  }

  Widget _buildTile(Conversation c) {
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey.shade200,
        backgroundImage:
            (c.avatarUrl != null && c.avatarUrl!.isNotEmpty) ? NetworkImage(c.avatarUrl!) : null,
        child: (c.avatarUrl == null || c.avatarUrl!.isEmpty)
            ? Text(c.initials, style: const TextStyle(fontWeight: FontWeight.bold))
            : null,
      ),
      title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Topic removed from subtitle as per request
      onTap: () async {
        if (c.id.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Invalid conversation id')));
          return;
        }

        final senderId = await _currentUserId();
        if (senderId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current user id not found. Please log in again.')),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              senderId: senderId,
              receiverId: c.id,
              backendHost: widget.apiService.backendHost,
              receiverName: c.name,
              topic: c.topic, // still passed to ChatPage
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Conversation>>(
          future: _conversationsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Failed to load conversations:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            } else {
              final items = snapshot.data ?? <Conversation>[];
              if (items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Center(child: Text('No conversations yet')),
                    SizedBox(height: 12),
                    Center(child: Text('When people message you, their chats will appear here.')),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) => _buildTile(items[idx]),
              );
            }
          },
        ),
      ),
    );
  }
}

/// Simplified conversation model aligned with backend
class Conversation {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? topic;

  Conversation({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.topic,
  });

  Conversation.empty()
      : id = '',
        name = 'Unknown',
        avatarUrl = null,
        topic = null;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    String _getId(Map<String, dynamic> m) =>
        (m['id'] ?? m['user_id'] ?? m['userId'] ?? '').toString();

    String _getName(Map<String, dynamic> m) =>
        (m['user_name'] ?? m['name'] ?? m['full_name'] ?? 'Unknown').toString();

    String? _getAvatar(Map<String, dynamic> m) =>
        (m['avatar_url'] ?? m['photo_url'] ?? m['image'] ?? m['avatar'])?.toString();

    return Conversation(
      id: _getId(json),
      name: _getName(json),
      avatarUrl: _getAvatar(json),
      topic: json['topic']?.toString(),
    );
  }

  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.length == 1
        ? parts[0][0].toUpperCase()
        : (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
