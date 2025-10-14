import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart'; // Ensure this path is correct

// --- 1. ColorScreen (List View) ---

class ColorScreen extends StatefulWidget {
  const ColorScreen({super.key});
  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

class _ColorScreenState extends State<ColorScreen> {
  final String apiUrl = "http://10.0.2.2:8000/api/colors/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  String accessToken = ''; // Renamed for clarity
  String refreshToken = ''; // Added to hold the Refresh Token
  List colors = [];
  bool isLoading = true;

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $accessToken", // Use accessToken
  };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetch(); // Renamed method
  }

  Future<void> _loadTokensAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken') ?? '';
    refreshToken = prefs.getString('refreshToken') ?? ''; // Load Refresh Token

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    fetchColors();
  }

  // REUSABLE TOKEN REFRESH UTILITY (Added)
  Future<bool> _refreshTokenUtility() async {
    final response = await http.post(
      Uri.parse(refreshUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'refresh': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newAccessToken = data['access'] as String;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', newAccessToken);

      setState(() {
        accessToken = newAccessToken; // Update local state for headers
      });
      return true;
    } else {
      // Refresh failed (Refresh Token expired). Force re-login.
      // FIX: Correctly awaiting SharedPreferences.getInstance() before calling clear()
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

  // FETCH COLORS (Updated with Refresh Logic)
  Future<void> fetchColors() async {
    setState(() => isLoading = true);
    Future<http.Response> _makeCall() => http.get(Uri.parse(apiUrl), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200) {
      setState(() {
        colors = jsonDecode(response.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load colors: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE COLOR (Updated with Refresh Logic)
  Future<void> deleteColor(int id) async {
    Future<http.Response> _makeCall() => http.delete(Uri.parse("$apiUrl$id/"), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 204) {
      fetchColors();
    } else {
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete color: ${response.body}")),
        );
      }
    }
  }

  void goToFormScreen(Map? color) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ColorFormScreen(
          color: color,
          accessToken: accessToken, // Pass access token
          refreshToken: refreshToken, // Pass refresh token
          onSaved: fetchColors,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Colors Management")),
      drawer: const SideBar(selectedPage: 'Color'), // Uncomment if Sidebar is available
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
          rows: colors.map((color) {
            return DataRow(cells: [
              DataCell(Text(color["id"].toString())),
              DataCell(Text(color["name"] ?? "-")),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => goToFormScreen(color),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteColor(color["id"]),
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

// --- 2. ColorFormScreen (Form View) ---

class ColorFormScreen extends StatefulWidget {
  final Map? color;
  final String accessToken; // Renamed prop
  final String refreshToken; // Added prop
  final VoidCallback onSaved;

  const ColorFormScreen({
    super.key,
    this.color,
    required this.accessToken,
    required this.refreshToken,
    required this.onSaved,
  });

  @override
  State<ColorFormScreen> createState() => _ColorFormScreenState();
}

class _ColorFormScreenState extends State<ColorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();

  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";
  final String apiUrl = "http://10.0.2.2:8000/api/colors/";

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${widget.accessToken}",
  };

  @override
  void initState() {
    super.initState();
    if (widget.color != null) {
      nameController.text = widget.color!["name"];
    }
  }

  // REUSABLE TOKEN REFRESH UTILITY (Added)
  Future<bool> _refreshTokenUtility() async {
    final response = await http.post(
      Uri.parse(refreshUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'refresh': widget.refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newAccessToken = data['access'] as String;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('accessToken', newAccessToken);

      return true;
    } else {
      // FIX: Correctly awaiting SharedPreferences.getInstance() before calling clear()
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

  // SAVE COLOR (Updated with Refresh Logic)
  Future<void> saveColor() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = {"name": nameController.text};

    final url = widget.color == null
        ? Uri.parse(apiUrl)
        : Uri.parse("$apiUrl${widget.color!["id"]}/");

    Future<http.Response> _makeCall() => widget.color == null
        ? http.post(url, headers: headers, body: jsonEncode(payload))
        : http.put(url, headers: headers, body: jsonEncode(payload));

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } else if (response.statusCode != 401 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save color: ${response.body}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.color == null ? "Add Color" : "Edit Color")),
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
              ElevatedButton(onPressed: saveColor, child: const Text("Save")),
            ],
          ),
        ),
      ),
    );
  }
}