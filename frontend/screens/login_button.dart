import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matchmaking_app/screens/login_page.dart';

class LogoutButton extends StatelessWidget {
  final String text;
  final Future<void> Function()? onLogout; // optional extra logout work

  const LogoutButton({super.key, this.text = "Logout", this.onLogout});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        // optional hook for additional logout work (API call, analytics, etc.)
        if (onLogout != null) {
          await onLogout!();
        }

        // clear local stored data (tokens, user info). adjust keys if needed.
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        // Replace the whole navigation stack with the LoginScreen
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      },
      child: Text(text),
    );
  }
}
