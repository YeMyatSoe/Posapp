import 'package:flutter/material.dart';
// Note: Assuming these imports exist in the project structure
import '../services/auth_service.dart';
import 'login_screen.dart';

// 1. Define the UserRole enum based on Django choices
enum UserRole {
  owner,
  manager,
  finance,
  hr,
  cashier,
  // Note: SUPER_ADMIN is usually provisioned internally and excluded from signup UI
}

// Helper extension to get the Django-friendly string value
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

// Placeholder stubs for completeness
class AuthService {
  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
    // Simulate API delay and success
    await Future.delayed(const Duration(seconds: 1));
    if (data['username'] == 'error') {
      throw Exception("Username already exists or API failed.");
    }
    return {'user': {'username': data['username']}};
  }
}

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
  final TextEditingController _shopIdController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLoading = false;

  // Initialize with Owner role
  UserRole _selectedRole = UserRole.owner;

  // Helper properties to check role type
  bool get _requiresNewShopName => _selectedRole == UserRole.owner;
  bool get _requiresExistingShopId => !_requiresNewShopName;

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _signup() async {
    // Only proceed if the form fields pass local validation
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Base signup data
    final Map<String, dynamic> signupData = {
      "username": _usernameController.text,
      "email": _emailController.text,
      "password": _passwordController.text,
      // Use the correct Django string for the selected role
      "role": _selectedRole.toDjangoString(),
    };

    // Conditional logic for shop field based on role
    if (_requiresNewShopName) {
      // OWNER: Requires a shop_name
      final String shopName = _shopNameController.text.trim();
      signupData["shop_name"] = shopName;
    } else if (_requiresExistingShopId) {
      // MANAGER, CASHIER, etc.: Require an existing shop ID
      final int? shopId = int.tryParse(_shopIdController.text);
      if (shopId == null) {
        _showErrorSnackBar("Error: Please enter a valid numeric Shop ID to join.");
        setState(() => _isLoading = false);
        return;
      }
      // Send the numeric shop ID as an INTEGER, resolving the "Expected pk value, received str" error
      signupData["shop"] = shopId;
    }

    try {
      final response = await _authService.signup(signupData);

      if (mounted) {
        final roleName = _selectedRole.displayName;
        _showSuccessSnackBar("$roleName account created for ${response['user']['username']}! Please login.");

        // Navigate to the LoginScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      // API call failed
      if (mounted) {
        // Display user-friendly error from backend (e.g., validation errors)
        _showErrorSnackBar(e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentRoleDisplay = _selectedRole.displayName;
    final String actionText = _requiresNewShopName ? "Create Owner Account" : "Sign Up as $currentRoleDisplay";

    // List of all user-selectable roles
    const List<UserRole> allRoles = [
      UserRole.owner,
      UserRole.manager,
      UserRole.finance,
      UserRole.hr,
      UserRole.cashier,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
            "Sign Up as $currentRoleDisplay",
            style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Create Account",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.indigo),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Role Selection Segmented Button for all roles
                SegmentedButton<UserRole>(
                  segments: allRoles.map((role) {
                    IconData icon;
                    if (role == UserRole.owner) {
                      icon = Icons.store;
                    } else if (role == UserRole.cashier) {
                      icon = Icons.point_of_sale;
                    } else if (role == UserRole.manager) {
                      icon = Icons.star_border;
                    } else if (role == UserRole.finance) {
                      icon = Icons.account_balance;
                    } else if (role == UserRole.hr) {
                      icon = Icons.groups;
                    } else {
                      icon = Icons.person_outline;
                    }

                    return ButtonSegment<UserRole>(
                      value: role,
                      label: Text(role.displayName),
                      icon: Icon(icon, size: 18),
                    );
                  }).toList(),
                  selected: <UserRole>{_selectedRole},
                  onSelectionChanged: (Set<UserRole> newSelection) {
                    setState(() {
                      _selectedRole = newSelection.first;
                      // Clear shop fields when switching roles
                      _shopIdController.clear();
                      _shopNameController.clear();
                    });
                  },
                  multiSelectionEnabled: false,
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: Colors.indigo.shade600,
                  ),
                ),

                const SizedBox(height: 32),

                // --- User Credentials ---
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: "Username",
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (val) =>
                  val == null || val.isEmpty ? "Please enter a username" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (val) =>
                  val == null || val.isEmpty || !val.contains('@') ? "Please enter a valid email" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (val) =>
                  val == null || val.length < 6 ? "Password must be at least 6 characters" : null,
                ),

                const SizedBox(height: 16),

                // --- Conditional Shop Field ---
                if (_requiresNewShopName)
                // Owner: Requires a new Shop Name to create the shop
                  TextFormField(
                    controller: _shopNameController,
                    decoration: const InputDecoration(
                      labelText: "Shop Name (New Shop)",
                      hintText: "Enter the name for your new shop",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.store),
                    ),
                    validator: (val) => (val == null || val.isEmpty) ? "Please enter a shop name" : null,
                  )
                else
                // Other roles: Require an existing Shop ID to join
                  TextFormField(
                    controller: _shopIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Shop ID to Join",
                      hintText: "Enter the numeric ID of your shop",
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                      prefixIcon: Icon(Icons.tag),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return "Please enter your shop's ID";
                      }
                      // Crucial check to ensure input is a number
                      if (int.tryParse(val) == null) {
                        return "Shop ID must be a number";
                      }
                      return null;
                    },
                  ),

                const SizedBox(height: 32),

                // --- Submit Button ---
                ElevatedButton(
                  onPressed: _isLoading ? null : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                      : Text(
                    actionText,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    // Navigate to the LoginScreen
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  child: const Text(
                    "Already have an account? Login",
                    style: TextStyle(color: Colors.indigo),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
