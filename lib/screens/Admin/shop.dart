import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart';

// ============================
// 1. API Constants
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000';
const String _SHOPS_API_URL = '$_API_BASE_URL/api/shops/';
const String _REFRESH_URL = '$_API_BASE_URL/api/token/refresh/';

// ============================
// 2. ShopScreen Widget
// ============================
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  List shops = [];
  bool isLoading = true;
  String _accessToken = '';
  String _refreshToken = '';
  String role = '';

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_accessToken",
  };

  @override
  void initState() {
    super.initState();
    _loadPrefsAndFetch();
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

  Future<void> _loadPrefsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? '';
    _refreshToken = prefs.getString('refreshToken') ?? '';
    role = prefs.getString('role') ?? '';

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      // Redirect to login if no token
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    if (role != "CASHIER") {
      fetchShops();
    } else {
      setState(() => isLoading = false); // Cashier won't fetch shops
    }
  }

  // FETCH SHOPS (Updated with Refresh Logic)
  Future<void> fetchShops() async {
    setState(() => isLoading = true);
    http.Response response = await http.get(Uri.parse(_SHOPS_API_URL), headers: headers);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      // Retry call with new Access Token
      response = await http.get(Uri.parse(_SHOPS_API_URL), headers: headers);
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          shops = jsonDecode(response.body);
          isLoading = false;
        });
      }
    } else if (response.statusCode == 401) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unauthorized access. Please login again.")),
        );
      }
    } else {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load shops: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE SHOP (Updated with Refresh Logic)
  Future<void> deleteShop(int id) async {
    http.Response response = await http.delete(Uri.parse("$_SHOPS_API_URL$id/"), headers: headers);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      // Retry call with new Access Token
      response = await http.delete(Uri.parse("$_SHOPS_API_URL$id/"), headers: headers);
    }

    if (response.statusCode == 204) {
      fetchShops();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete shop: ${response.body}")),
        );
      }
    }
  }

  // MODIFIED: Go to form screen with auto-select logic
  void goToFormScreen(Map? shop) async {
    final prefs = await SharedPreferences.getInstance();
    final userShopId = prefs.getInt('userShopId');

    if (role == "CASHIER") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Access Denied! Cashiers cannot edit or add shops.")),
      );
      return;
    }

    Map? shopToEdit = shop;

    // Auto-select logic: If 'Add' is clicked (shop == null) and the user has a shop ID,
    // find that shop in the list and set it as the shop to edit.
    if (shopToEdit == null && userShopId != null) {
      shopToEdit = shops.firstWhere(
            (s) => s["id"] == userShopId,
        orElse: () => null,
      );

      if (shopToEdit != null) {
        // Log auto-selection for debugging
        debugPrint("DEBUG: Auto-selecting user's assigned shop: ${shopToEdit!["name"]}");
      }
    }

    // If shopToEdit is still null, it means the user is a full Admin/Manager
    // and is indeed adding a new shop.

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopFormScreen(
          shop: shopToEdit, // Pass the auto-selected shop or the one clicked 'Edit'
          accessToken: _accessToken,
          refreshTokenUtility: _refreshTokenUtility,
          onSaved: fetchShops,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Shop Management")),
      drawer: const SideBar(selectedPage: 'Shops'),
      floatingActionButton: role != "CASHIER"
          ? FloatingActionButton(
        onPressed: () => goToFormScreen(null),
        child: const Icon(Icons.add),
      )
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text("ID")),
            DataColumn(label: Text("Name")),
            DataColumn(label: Text("Location")),
            DataColumn(label: Text("Active")),
            DataColumn(label: Text("Actions")),
          ],
          rows: shops.map((shop) {
            return DataRow(cells: [
              DataCell(Text(shop["id"].toString())),
              DataCell(Text(shop["name"] ?? "-")),
              DataCell(Text(shop["location"] ?? "-")),
              DataCell(Text(shop["is_active"].toString())),
              DataCell(Row(
                children: [
                  if (role != "CASHIER") ...[
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => goToFormScreen(shop),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => deleteShop(shop["id"]),
                    ),
                  ] else
                    const Text("No access"),
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
// 3. ShopFormScreen Widget (MODIFIED for Read-Only)
// ============================
typedef RefreshTokenUtility = Future<bool> Function();

class ShopFormScreen extends StatefulWidget {
  final Map? shop;
  final String accessToken;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback onSaved;

  const ShopFormScreen({
    super.key,
    this.shop,
    required this.accessToken,
    required this.refreshTokenUtility,
    required this.onSaved,
  });

  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  bool isActive = true;
  late String _currentAccessToken;
  int? _loggedInUserShopId; // ADDED: User's assigned shop ID

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;

    // Load shop ID asynchronously, then trigger a state update
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _loggedInUserShopId = prefs.getInt('userShopId');
        });
      }
    });

    if (widget.shop != null) {
      nameController.text = widget.shop!["name"];
      locationController.text = widget.shop!["location"] ?? "";
      isActive = widget.shop!["is_active"];
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

  // SAVE SHOP (Unchanged)
  Future<void> saveShop() async {
    if (!_formKey.currentState!.validate()) return;

    final isNewShop = widget.shop == null;

    // If the form is read-only and is for adding a new shop, prevent save (shouldn't happen with current logic)
    final bool isReadOnly = (widget.shop != null && widget.shop!["id"] == _loggedInUserShopId);
    if (isReadOnly && isNewShop) return;

    final payload = {
      "name": nameController.text,
      "location": locationController.text,
      "is_active": isActive,
    };

    // If the shop was auto-selected, we must ensure we use its ID for PUT.
    final shopId = widget.shop != null
        ? widget.shop!["id"]
        : null;

    final url = isNewShop
        ? Uri.parse(_SHOPS_API_URL)
        : Uri.parse("$_SHOPS_API_URL$shopId/");

    final method = isNewShop ? 'POST' : 'PUT';

    http.Response response = await _makeApiCall(method, url, payload);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';

        // Retry call with new Access Token
        response = await _makeApiCall(method, url, payload);
      }
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
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
          SnackBar(content: Text("Failed to save shop: ${response.body}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine read-only state: true if editing a specific shop
    // AND that shop's ID matches the logged-in user's assigned shop ID.
    final bool isReadOnly = (widget.shop != null && widget.shop!["id"] == _loggedInUserShopId);
    final bool isAddingNew = widget.shop == null;

    return Scaffold(
      appBar: AppBar(title: Text(isAddingNew ? "Add Shop" : "Edit Shop")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Shop Name (Read-Only if assigned to user)
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Shop Name",
                  filled: isReadOnly,
                  fillColor: isReadOnly ? Colors.grey[200] : null,
                ),
                validator: (v) => v!.isEmpty ? "Required" : null,
                readOnly: isReadOnly,
              ),
              // Location (Read-Only if assigned to user)
              TextFormField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: "Location",
                  filled: isReadOnly,
                  fillColor: isReadOnly ? Colors.grey[200] : null,
                ),
                readOnly: isReadOnly,
              ),
              const SizedBox(height: 10),
              // Active Status (Editable even if Name/Location is read-only)
              SwitchListTile(
                title: const Text("Active"),
                value: isActive,
                onChanged: (v) => setState(() => isActive = v),
              ),
              const SizedBox(height: 20),
              // Save button is enabled unless the user is adding a new shop
              // and has an assigned shop ID (which shouldn't happen with the parent screen's logic)
              ElevatedButton(
                  onPressed: saveShop,
                  child: const Text("Save")
              ),
            ],
          ),
        ),
      ),
    );
  }
}
