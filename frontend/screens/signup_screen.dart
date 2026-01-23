// lib/screens/signup_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';
import 'login_page.dart';
import '../services/api.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController userName = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();
  final TextEditingController emailId = TextEditingController();
  final TextEditingController dob = TextEditingController();
  final TextEditingController placeOfBirth = TextEditingController();
  final TextEditingController salary = TextEditingController();
  final TextEditingController religion = TextEditingController();
  final TextEditingController caste = TextEditingController();

  final ApiService api = ApiService();

  File? _pickedImage;
  bool _isSubmitting = false;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _passwordsMatch = false;

  String? selGender;
  String? selEducation;
  String? selLivingArrangement;
  String? selCulturalPractices;
  String? selPreferredFood;
  String? selParentsInvolvement;
  String? selHomeVibe;
  String? selFinancialAttitude;
  String? selExpenseSharing;
  String? selEmotionalConnection;
  String? selHomeSetupPreference;
  String? selWeekendStyle;
  String? selLongTermGoals;
  String? selHouseholdRole;

  final List<String> genders = ["Male", "Female", "Transgender", "Non-binary"];
  final List<String> educations = [
    "SSLC / 10th grade",
    "PUC / 12th grade",
    "B.Tech",
    "B.Com",
    "MBBS",
    "M.Sc / M. Tech"
  ];
  final List<String> livingArrangements = [
    "Joint family",
    "Nuclear family",
    "Flexible"
  ];
  final List<String> culturalPractices = [
    "Follow traditions strictly",
    "Mix of modern + traditional",
    "Flexible / not strict"
  ];
  final List<String> preferredFoods = ["Vegetarian", "Non-Vegetarian", "Vegan"];
  final List<String> parentsInvolvement = [
    "Actively involved",
    "Advisory",
    "Minimal"
  ];
  final List<String> homeVibes = [
    "Chill, comfy, relaxed",
    "Tidy, organized, routine",
    "Flexible, in-between"
  ];

  final List<String> financialAttitude = [
    "Saver / cautious with money",
    "Balanced spender",
    "Free spender / experience-driven"
  ];

  final List<String> expenseSharing = [
    "Equal sharing",
    "Based on income ratio",
    "Traditional (one leads financially)"
  ];

  final List<String> emotionalConnection = [
    "Need deep emotional bond",
    "Balanced affection & space",
    "Value independence more"
  ];

  final List<String> homeSetupPreference = [
    "Urban / city life",
    "Suburban comfort",
    "Countryside / peaceful living"
  ];

  final List<String> weekendStyle = [
    "Relaxing at home",
    "Exploring outdoors / traveling",
    "Social events / parties",
    "Learning or creative hobbies"
  ];

  final List<String> longTermGoals = [
    "Build wealth and stability",
    "Balanced life & happiness",
    "Adventure and new experiences",
    "Career-driven and ambitious"
  ];

  final List<String> householdRole = [
    "Shared responsibilities equally",
    "Traditional gender roles",
    "Flexible depending on situation"
  ];

  @override
  void initState() {
    super.initState();
    password.addListener(_checkPasswordsMatch);
    confirmPassword.addListener(_checkPasswordsMatch);
  }

  void _checkPasswordsMatch() {
    final match = password.text.isNotEmpty &&
        confirmPassword.text.isNotEmpty &&
        password.text == confirmPassword.text;
    if (match != _passwordsMatch) {
      setState(() => _passwordsMatch = match);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? xfile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (xfile != null) {
        setState(() {
          _pickedImage = File(xfile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image pick failed: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final profile = {
      "user_name": userName.text.trim(),
      "password": password.text.trim(),
      "email_id": emailId.text.trim(),
      "gender": selGender,
      "dob": dob.text.trim(),
      "place_of_birth": placeOfBirth.text.trim(),
      "education": selEducation,
      "salary": salary.text.trim(),
      "religion": religion.text.trim(),
      "caste": caste.text.trim(),
      "preferences": {
        "living_arrangement": selLivingArrangement,
        "cultural_practices": selCulturalPractices,
        "preferred_food": selPreferredFood,
        "parents_involvement": selParentsInvolvement,
        "home_vibe": selHomeVibe,
        "financial_attitude": selFinancialAttitude,
        "expense_sharing": selExpenseSharing,
        "emotional_connection": selEmotionalConnection,
        "home_setup_preference": selHomeSetupPreference,
        "weekend_style": selWeekendStyle,
        "long_term_goals": selLongTermGoals,
        "household_role": selHouseholdRole,
      }
    };

    try {
      final resp = await api.signupWithPhoto(profile, file: _pickedImage);

      final prefs = await SharedPreferences.getInstance();
      final prefsMap = profile["preferences"] as Map<String, dynamic>;

      final localProfile = {
        "user_name": profile["user_name"],
        "email_id": profile["email_id"],
        "gender": profile["gender"],
        "dob": profile["dob"],
        "place_of_birth": profile["place_of_birth"],
        "education": profile["education"],
        "salary": profile["salary"],
        "religion": profile["religion"],
        "caste": profile["caste"],
        "living_arrangement": prefsMap["living_arrangement"],
        "cultural_practices": prefsMap["cultural_practices"],
        "preferred_food": prefsMap["preferred_food"],
        "parents_involvement": prefsMap["parents_involvement"],
        "home_vibe": prefsMap["home_vibe"],
        "financial_attitude": prefsMap["financial_attitude"],
        "expense_sharing": prefsMap["expense_sharing"],
        "emotional_connection": prefsMap["emotional_connection"],
        "home_setup_preference": prefsMap["home_setup_preference"],
        "weekend_style": prefsMap["weekend_style"],
        "long_term_goals": prefsMap["long_term_goals"],
        "household_role": prefsMap["household_role"],
        "photo_url": resp['image_url'] ?? resp['photo_url'] ?? '',
      };

      if (resp.containsKey('access_token')) {
        await prefs.setString('authToken', resp['access_token']);
      }
      if (resp.containsKey('refresh_token')) {
        await prefs.setString('refreshToken', resp['refresh_token']);
      }

      await prefs.setString("user_profile", jsonEncode(localProfile));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(apiService: api, currentUser: localProfile),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Signup failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget buildTextField(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: suffix,
        ),
        validator: validator ??
            (val) {
              if (val == null || val.isEmpty) return 'Required';
              if (label == "Create Password" && val.length < 8) {
                return 'Minimum 8 characters';
              }
              if (label == "Email ID" &&
                  !RegExp(r"^[^@]+@[^@]+\.[^@]+").hasMatch(val)) {
                return 'Invalid email';
              }
              return null;
            },
      ),
    );
  }

  Widget buildDropdown(
    String label,
    String? selectedValue,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        value: selectedValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
            .toList(),
        onChanged: onChanged,
        validator: (val) => val == null ? "Required" : null,
      ),
    );
  }

  @override
  void dispose() {
    userName.dispose();
    emailId.dispose();
    password.removeListener(_checkPasswordsMatch);
    confirmPassword.removeListener(_checkPasswordsMatch);
    password.dispose();
    confirmPassword.dispose();
    dob.dispose();
    placeOfBirth.dispose();
    salary.dispose();
    religion.dispose();
    caste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign Up")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    const Text(
                      "Welcome to JanamSaathi AI!",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Image.asset("assets/icon.png", height: 120, width: 120),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 48,
                        backgroundImage: _pickedImage != null
                            ? FileImage(_pickedImage!)
                            : null,
                        child: _pickedImage == null
                            ? const Icon(Icons.add_a_photo)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Existing user? "),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            "Log In",
                            style: TextStyle(
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              buildTextField("Name", userName),
              buildTextField("Email ID", emailId),
              buildTextField(
                "Create Password",
                password,
                hint: "Min 8 chars with upper, lower, number & special",
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TextFormField(
                  controller: confirmPassword,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirm Password",
                    hintText: "Re-type password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Required';
                    if (val != password.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8, left: 6),
                child: Text(
                  password.text.isEmpty && confirmPassword.text.isEmpty
                      ? ''
                      : (_passwordsMatch
                          ? "Passwords match"
                          : "Passwords do not match"),
                  style: TextStyle(
                    color: _passwordsMatch ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
              ),
              buildDropdown("Gender", selGender, genders,
                  (val) => setState(() => selGender = val)),
              buildTextField("Date of Birth", dob, hint: "YYYY-MM-DD"),
              buildTextField("Place of Birth", placeOfBirth, hint: "Birth City"),
              buildDropdown("Highest Qualification", selEducation, educations,
                  (val) => setState(() => selEducation = val)),
              buildTextField("Salary", salary,
                  keyboardType: TextInputType.number,
                  hint: "In Lakhs per annum"),
              buildTextField("Religion", religion),
              buildTextField("Caste", caste),
              buildDropdown("Preferred living arrangement", selLivingArrangement,
                  livingArrangements,
                  (val) => setState(() => selLivingArrangement = val)),
              buildDropdown("Cultural practices", selCulturalPractices,
                  culturalPractices,
                  (val) => setState(() => selCulturalPractices = val)),
              buildDropdown("Preferred food", selPreferredFood, preferredFoods,
                  (val) => setState(() => selPreferredFood = val)),
              buildDropdown("Parents involvement", selParentsInvolvement,
                  parentsInvolvement,
                  (val) => setState(() => selParentsInvolvement = val)),
              buildDropdown("Home vibe", selHomeVibe, homeVibes,
                  (val) => setState(() => selHomeVibe = val)),
              buildDropdown(
                "How would you describe your approach to money?",
                selFinancialAttitude,
                financialAttitude,
                (val) => setState(() => selFinancialAttitude = val),
              ),
              buildDropdown(
                "How should household expenses be shared?",
                selExpenseSharing,
                expenseSharing,
                (val) => setState(() => selExpenseSharing = val),
              ),
              buildDropdown(
                "What kind of emotional connection do you value most?",
                selEmotionalConnection,
                emotionalConnection,
                (val) => setState(() => selEmotionalConnection = val),
              ),
              buildDropdown(
                "What kind of home setup do you prefer?",
                selHomeSetupPreference,
                homeSetupPreference,
                (val) => setState(() => selHomeSetupPreference = val),
              ),
              buildDropdown(
                "How do you usually like to spend weekends?",
                selWeekendStyle,
                weekendStyle,
                (val) => setState(() => selWeekendStyle = val),
              ),
              buildDropdown(
                "What are your long-term life goals?",
                selLongTermGoals,
                longTermGoals,
                (val) => setState(() => selLongTermGoals = val),
              ),
              buildDropdown(
                "How would you like household roles to be managed?",
                selHouseholdRole,
                householdRole,
                (val) => setState(() => selHouseholdRole = val),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Continue"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
