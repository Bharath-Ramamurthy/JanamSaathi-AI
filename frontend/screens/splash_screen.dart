// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'signup_screen.dart';
import 'home_page.dart';
import '../services/api.dart';
// import '../services/socket/socket_manager.dart'; // uncomment if you initialize SocketManager here

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiService api = ApiService();

  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedProfileString = prefs.getString("user_profile");

      Map<String, dynamic> savedProfile = {};

      if (savedProfileString != null && savedProfileString.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedProfileString);
          if (decoded is Map) {
            // safely convert to Map<String, dynamic>
            savedProfile = Map<String, dynamic>.from(decoded as Map);
          } else {
            // fallback: not the expected shape
            savedProfile = {};
          }
        } catch (e) {
          // corrupted JSON — ignore and treat as no profile
          savedProfile = {};
        }
      }

      // Normalize field names for consistency
      if ((savedProfile['user_name'] == null || savedProfile['user_name'].toString().isEmpty) &&
          (savedProfile['name'] != null && savedProfile['name'].toString().isNotEmpty)) {
        savedProfile['user_name'] = savedProfile['name'];
      }

      if ((savedProfile['photo_url'] == null || savedProfile['photo_url'].toString().isEmpty) &&
          (savedProfile['image_url'] != null && savedProfile['image_url'].toString().isNotEmpty)) {
        savedProfile['photo_url'] = savedProfile['image_url'];
      }

      // Optional: initialize socket manager early so WebSocket connections are ready
      // (uncomment and adapt if you have SocketManager.initialize)
      // try {
      //   await SocketManager.initialize(apiService: api, wsPath: '/ws');
      // } catch (_) { /* non-fatal */ }

      // Validate API connectivity (optional, non-blocking)
      try {
        await api.recommendMatches().timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // ignore timeout — continue to home
      } catch (_) {
        // ignore other errors — continue to home
      }

      if (!mounted) return;

      if (savedProfile.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(apiService: api, currentUser: savedProfile),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SignUpScreen()),
        );
      }
    } catch (e) {
      // Any unexpected error — fallback to signup screen
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignUpScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover, // full screen
              width: double.infinity,
              height: double.infinity,
            ),
            const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
