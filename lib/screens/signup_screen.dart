import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';

// 1️⃣ Define user roles
enum UserRole { owner, manager, finance, hr, cashier }

extension UserRoleExtension on UserRole {
  String toDjangoString() {
    return switch (this) {
      UserRole.owner => "OWNER",
      UserRole.manager => "MANAGER",
      UserRole.finance => "FINANCE",
      UserRole.hr => "HR",
      UserRole.cashier => "CASHIER",
    };
  }

  String get displayName {
    return toDjangoString().replaceAll('_', ' ').toLowerCase().toTitleCase();
  }
}

extension StringExtension on String {
  String toTitleCase() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

// 2️⃣ AuthService
class AuthService {
  final String baseUrl = "http://10.0.2.2:8000/api"; // Your Django backend URL

  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse("$baseUrl/signup/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final errorBody = jsonDecode(response.body);
      String errorMessage = "Signup failed. ";
      if (errorBody is Map<String, dynamic>) {
        errorBody.forEach((key, value) {
          errorMessage += "$key: ${value.toString().replaceAll(RegExp(r'[\[\]]'), '')} ";
        });
      }
      throw Exception(errorMessage);
    }
  }
}

// 3️⃣ Signup Screen
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _shopIdController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  UserRole _selectedRole = UserRole.owner;

  bool get _requiresNewShopName => _selectedRole == UserRole.owner;
  bool get _requiresExistingShopId => !_requiresNewShopName;

  void _showSnackBar(String message, {Color color = Colors.red}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 4)),
      );
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final Map<String, dynamic> signupData = {
      "username": _usernameController.text.trim(),
      "email": _emailController.text.trim(),
      "password": _passwordController.text.trim(),
      "role": _selectedRole.toDjangoString(),
    };

    if (_requiresNewShopName) {
      signupData["shop_name"] = _shopNameController.text.trim();
    } else if (_requiresExistingShopId) {
      final int? shopId = int.tryParse(_shopIdController.text.trim());
      if (shopId == null) {
        _showSnackBar("Shop ID must be a number");
        setState(() => _isLoading = false);
        return;
      }
      signupData["shop"] = shopId;
    }

    try {
      final response = await _authService.signup(signupData);
      final expireDate = response['user']['expire_date'] ?? '';

      _showSnackBar(
        "Account created successfully! Trial expires on $expireDate",
        color: Colors.green,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      _showSnackBar(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const List<UserRole> allRoles = [
      UserRole.owner,
      UserRole.manager,
      UserRole.finance,
      UserRole.hr,
      UserRole.cashier,
    ];

    final actionText = _requiresNewShopName ? "Create Owner Account" : "Sign Up";

    return Scaffold(
      appBar: AppBar(
        title: Text(actionText, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person)),
                validator: (val) => val == null || val.isEmpty ? "Enter username" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email)),
                validator: (val) => val == null || !val.contains('@') ? "Enter valid email" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)),
                validator: (val) => val == null || val.length < 6 ? "Password min 6 chars" : null,
              ),
              const SizedBox(height: 16),

              // Role selection
              SegmentedButton<UserRole>(
                segments: allRoles.map((role) {
                  return ButtonSegment(
                    value: role,
                    label: Text(role.displayName),
                    icon: Icon(role == UserRole.owner ? Icons.store : Icons.person_outline),
                  );
                }).toList(),
                selected: <UserRole>{_selectedRole},
                onSelectionChanged: (Set<UserRole> newSelection) {
                  setState(() {
                    _selectedRole = newSelection.first;
                    _shopNameController.clear();
                    _shopIdController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),

              if (_requiresNewShopName)
                TextFormField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(labelText: "Shop Name (New Shop)", prefixIcon: Icon(Icons.store)),
                  validator: (val) => val == null || val.isEmpty ? "Enter shop name" : null,
                )
              else
                TextFormField(
                  controller: _shopIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Shop ID to Join", prefixIcon: Icon(Icons.tag)),
                  validator: (val) {
                    if (val == null || val.isEmpty) return "Enter shop ID";
                    if (int.tryParse(val) == null) return "Shop ID must be a number";
                    return null;
                  },
                ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _signup,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(actionText),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
                child: const Text("Already have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
