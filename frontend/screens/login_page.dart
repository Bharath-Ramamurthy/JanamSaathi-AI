// lib/ui/pages/login_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_page.dart';
import 'signup_screen.dart';
import '../services/api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final ApiService api = ApiService();

  bool _isLoggingIn = false;

  String? _validateEmail(String? val) {
    if (val == null || val.isEmpty) return 'Required';
    final emailRegex = RegExp(r"^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$");
    if (!emailRegex.hasMatch(val.trim())) return 'Enter a valid email';
    return null;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoggingIn = true);

    final email = emailController.text.trim();
    final password = passwordController.text;

    try {
      final data = await api.loginUser(email, password);

      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> localProfile = {};

      // Save tokens
      if (data.containsKey("access_token")) {
        await prefs.setString("authToken", data["access_token"]);
      }
      if (data.containsKey("refresh_token")) {
        await prefs.setString("refreshToken", data["refresh_token"]);
      }

      // Save user profile (from backend response)
      if (data.containsKey("user") && data["user"] is Map) {
        localProfile = Map<String, dynamic>.from(data["user"]);
        await prefs.setString("user_profile", jsonEncode(localProfile));

        // Save user ID separately for easy access
        if (localProfile.containsKey('id')) {
          await prefs.setString('userId', localProfile['id'].toString());
        } else if (localProfile.containsKey('user_id')) {
          await prefs.setString('userId', localProfile['user_id'].toString());
        }
      } else {
        // Fallback: reuse stored profile or minimal one
        final stored = prefs.getString("user_profile");
        if (stored != null && stored.isNotEmpty) {
          localProfile = Map<String, dynamic>.from(jsonDecode(stored));
          if (localProfile.containsKey('id')) {
            await prefs.setString('userId', localProfile['id'].toString());
          }
        } else {
          localProfile = {"email": email};
          await prefs.setString("user_profile", jsonEncode(localProfile));
        }
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            apiService: api,
            currentUser: localProfile,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: Column(
                  children: [
                    const Text(
                      "Welcome back to JananSaathi AI!",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Image.asset(
                      "assets/icon.png",
                      height: 120,
                      width: 120,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // Email field
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email ID",
                    hintText: "you@example.com",
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                ),
              ),
              // Password field
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    hintText: "Enter your password",
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Required';
                    if (val.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Login button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoggingIn ? null : _login,
                  child: _isLoggingIn
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Log In"),
                ),
              ),
              const SizedBox(height: 12),
              // Sign-up prompt
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SignUpScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Create one",
                      style: TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
