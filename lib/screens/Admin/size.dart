import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart';

// ============================
// 1. API Constants
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000';
const String _SIZES_API_URL = '$_API_BASE_URL/api/sizes/';
const String _REFRESH_URL = '$_API_BASE_URL/api/token/refresh/';

// ============================
// 2. SizeScreen Widget
// ============================
class SizeScreen extends StatefulWidget {
  const SizeScreen({super.key});
  @override
  State<SizeScreen> createState() => _SizeScreenState();
}

class _SizeScreenState extends State<SizeScreen> {
  String _accessToken = '';
  String _refreshToken = ''; // Added refresh token
  List sizes = [];
  bool isLoading = true;

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_accessToken",
  };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetch();
  }

  // REUSABLE TOKEN REFRESH UTILITY
  Future<bool> _refreshTokenUtility() async {
    final response = await http.post(
      Uri.parse(_REFRESH_URL),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'refresh': _refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newAccessToken = data['access'] as String;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', newAccessToken);

      if (mounted) {
        setState(() {
          _accessToken = newAccessToken; // Update local state
        });
      }
      return true;
    } else {
      // Refresh failed (Refresh Token expired). Force re-login.
      await (await SharedPreferences.getInstance()).clear();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session expired. Please log in again.")),
        );
      }
      return false;
    }
  }

  Future<void> _loadTokensAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? '';
    _refreshToken = prefs.getString('refreshToken') ?? '';

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      if (mounted) await Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    fetchSizes();
  }

  // FETCH SIZES (Updated with Refresh Logic)
  Future<void> fetchSizes() async {
    setState(() => isLoading = true);
    http.Response response = await http.get(Uri.parse(_SIZES_API_URL), headers: headers);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      // Retry call with new Access Token
      response = await http.get(Uri.parse(_SIZES_API_URL), headers: headers);
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          sizes = jsonDecode(response.body);
          isLoading = false;
        });
      }
    } else if (response.statusCode == 401) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized. Please login again.")),
        );
      }
    } else {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load sizes: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE SIZE (Updated with Refresh Logic)
  Future<void> deleteSize(int id) async {
    http.Response response = await http.delete(Uri.parse("$_SIZES_API_URL$id/"), headers: headers);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      // Retry call with new Access Token
      response = await http.delete(Uri.parse("$_SIZES_API_URL$id/"), headers: headers);
    }

    if (response.statusCode == 204) {
      fetchSizes();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete size: ${response.body}")),
        );
      }
    }
  }

  void goToFormScreen(Map? size) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SizeFormScreen(
          size: size,
          accessToken: _accessToken, // Pass the current token
          refreshTokenUtility: _refreshTokenUtility, // Pass the utility function
          onSaved: fetchSizes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sizes Management")),
      drawer: const SideBar(selectedPage: 'Size'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => goToFormScreen(null),
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text("ID")),
            DataColumn(label: Text("Name")),
            DataColumn(label: Text("Actions")),
          ],
          rows: sizes.map((size) {
            return DataRow(cells: [
              DataCell(Text(size["id"].toString())),
              DataCell(Text(size["name"] ?? "-")),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => goToFormScreen(size),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteSize(size["id"]),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ============================
// 3. SizeFormScreen Widget
// ============================
typedef RefreshTokenUtility = Future<bool> Function();

class SizeFormScreen extends StatefulWidget {
  final Map? size;
  final String accessToken; // Renamed from token to accessToken
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback onSaved;

  const SizeFormScreen({
    super.key,
    this.size,
    required this.accessToken,
    required this.refreshTokenUtility,
    required this.onSaved,
  });

  @override
  State<SizeFormScreen> createState() => _SizeFormScreenState();
}

class _SizeFormScreenState extends State<SizeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  late String _currentAccessToken; // Mutable token state for retries

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;
    if (widget.size != null) {
      nameController.text = widget.size!["name"];
    }
  }

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_currentAccessToken",
  };

  // Helper function to make the API call (POST or PUT)
  Future<http.Response> _makeApiCall(String method, Uri url, Map<String, dynamic> payload) async {
    final body = jsonEncode(payload);
    switch (method) {
      case 'POST':
        return http.post(url, headers: headers, body: body);
      case 'PUT':
        return http.put(url, headers: headers, body: body);
      default:
        throw Exception("Invalid HTTP method");
    }
  }

  // SAVE SIZE (Updated with Refresh Logic)
  Future<void> saveSize() async {
    if (!_formKey.currentState!.validate()) return;

    final isNewSize = widget.size == null;
    final payload = {"name": nameController.text};

    final url = isNewSize
        ? Uri.parse(_SIZES_API_URL)
        : Uri.parse("$_SIZES_API_URL${widget.size!["id"]}/");

    final method = isNewSize ? 'POST' : 'PUT';

    http.Response response = await _makeApiCall(method, url, payload);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();

      if (success) {
        // Retrieve the new token from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';

        // Retry call with new Access Token
        response = await _makeApiCall(method, url, payload);
      }
    }

    if ([200, 201].contains(response.statusCode)) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } else if (response.statusCode == 401) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized. Please login again.")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save size: ${response.body}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.size == null ? "Add Size" : "Edit Size")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name"),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveSize, child: const Text("Save")),
            ],
          ),
        ),
      ),
    );
  }
}