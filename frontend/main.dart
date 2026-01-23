import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/api.dart';
import 'services/socket/socket_manager.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Needed for async ops before runApp

  // ✅ Initialize ApiService and SocketManager before app start
  final apiService = ApiService();
  SocketManager.initialize(apiService: apiService, wsPath: '/ws');

  runApp(const MatchMakingApp());
}

class MatchMakingApp extends StatelessWidget {
  const MatchMakingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Match Maker',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
