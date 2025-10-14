import 'dart:convert';
import 'package:http/http.dart' as http;
enum UserRole { owner, cashier }
class AuthService {
  final String baseUrl = "http://10.0.2.2:8000/api"; // change to your backend url

  Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );

      // Status code 201 Created is expected upon successful signup
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        // Parse the body to show the specific error from Django (e.g., validation errors)
        final errorBody = jsonDecode(response.body);
        String errorMessage = "Signup failed. ";

        // Custom error parsing for DRF validation messages
        if (errorBody is Map<String, dynamic>) {
          errorBody.forEach((key, value) {
            errorMessage += "$key: ${value.toString().replaceAll(RegExp(r'[\[\]]'), '')} ";
          });
        }

        throw Exception(errorMessage);
      }
    } on http.ClientException catch (e) {
      throw Exception("Network error: Could not connect to the server at $baseUrl. Check if the backend is running and the URL is correct. Details: $e");
    } catch (e) {
      // Re-throw any other exceptions
      throw Exception(e.toString());
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse("$baseUrl/login/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Login failed: ${response.body}");
    }
  }
}
