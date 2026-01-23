// lib/screens/profile_detail_page.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_page.dart';
import 'view_report_page.dart';

class ProfileDetailPage extends StatefulWidget {
  final Map<String, dynamic> profileData;
  final Map<String, dynamic> currentUser;

  const ProfileDetailPage({
    super.key,
    required this.profileData,
    required this.currentUser,
  });

  @override
  _ProfileDetailPageState createState() => _ProfileDetailPageState();
}

class _ProfileDetailPageState extends State<ProfileDetailPage> {
  String compatibilityScore = '';
  bool reportExists = false;

  @override
  void initState() {
    super.initState();
  }

  /// Build full image URL using base URL if needed.
  String? _fullImageUrl(String? imagePath, {String? baseUrl}) {
    if (imagePath == null || imagePath.trim().isEmpty) return null;
    final trimmed = imagePath.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (baseUrl != null && trimmed.startsWith('/')) return '$baseUrl$trimmed';
    if (baseUrl != null) return '$baseUrl/$trimmed';
    return trimmed;
  }

  String _extractPartnerId(Map<String, dynamic> p) {
    final raw = p['id'] ??
        p['user_id'] ??
        p['userId'] ??
        p['id_str'] ??
        p['user_name'] ??
        p['email'];
    return raw?.toString().trim() ?? '';
  }

  Future<String> _getSenderId() async {
    final fromMap = widget.currentUser['id'] ??
        widget.currentUser['user_id'] ??
        widget.currentUser['userId'];
    if (fromMap != null) return fromMap.toString();

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

    final stored = prefs.getString('user_profile');
    if (stored != null && stored.isNotEmpty) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(stored));
        final fallback =
            map['id'] ?? map['user_id'] ?? map['user_name'] ?? map['email'];
        if (fallback != null) return fallback.toString();
      } catch (_) {}
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profileData;
    final imageUrl = _fullImageUrl(
        profile['image_url'] ?? profile['photo_url'] ?? profile['avatar']);

    String displayName = profile['user_name']?.toString() ??
        profile['name']?.toString() ??
        profile['full_name']?.toString() ??
        '';

    String initialChar() => displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(title: Text(displayName.isNotEmpty ? displayName : 'Profile')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Image / placeholder
            Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                image: (imageUrl != null && imageUrl.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                    : null,
              ),
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? Center(
                      child: Text(initialChar(),
                          style: const TextStyle(fontSize: 60, color: Colors.white)),
                    )
                  : null,
            ),
            const SizedBox(height: 20),

            // Profile Details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(displayName,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text('Education: ${profile['education'] ?? 'Not provided'}'),
                  Text('Salary: ₹${profile['salary'] ?? 'Not provided'}'),
                  Text('Caste: ${profile['caste'] ?? 'Not provided'}'),
                  Text('Religion: ${profile['religion'] ?? 'Not provided'}'),
                  Text('Color: ${profile['color'] ?? 'Not provided'}'),
                  Text('DOB: ${profile['dob'] ?? 'Not provided'}'),
                  Text('Place of Birth: ${profile['place_of_birth'] ?? 'Not provided'}'),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Action Buttons side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final senderId = await _getSenderId();
                        final receiverId = _extractPartnerId(profile);
                        final receiverName = profile['user_name']?.toString() ?? '';

                        if (senderId.isEmpty || receiverId.isEmpty) return;

                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              senderId: senderId,
                              receiverId: receiverId,
                              receiverName: receiverName,
                              backendHost: '', // not used for WS
                            ),
                          ),
                        );
                      },
                      child: const Text('Start Chat'),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final receiverId = _extractPartnerId(profile);
                        if (receiverId.isEmpty) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ViewReportPage(partnerId: receiverId),
                          ),
                        );
                      },
                      child: const Text("View Report"),
                    ),
                  ),
                ],
              ),
            ),

            // Compatibility Score Display (if any)
            if (compatibilityScore.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Compatibility: $compatibilityScore',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
