import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/admin/sidebar.dart';

// ============================
// 1. API Constants
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000';
const String _SUPPLIERS_API_URL = '$_API_BASE_URL/api/suppliers/';
const String _SHOPS_API_URL = '$_API_BASE_URL/api/shops/';
const String _REFRESH_URL = '$_API_BASE_URL/api/token/refresh/';

// ============================
// 2. SupplierScreen Widget
// ============================
class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});
  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  List suppliers = [];
  bool isLoading = true;

  String _accessToken = '';
  String _refreshToken = '';

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_accessToken",
  };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetchSuppliers();
  }

  // ------------------------------
  // TOKEN REFRESH UTILITY
  // ------------------------------
  Future<bool> _refreshTokenUtility() async {
    if (_refreshToken.isEmpty) return false;

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
          _accessToken = newAccessToken;
        });
      }
      return true;
    } else {
      await (await SharedPreferences.getInstance()).clear();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Session expired. Please log in again."),
          ),
        );
      }
      return false;
    }
  }

  // ------------------------------
  // LOAD TOKENS AND FETCH SUPPLIERS
  // ------------------------------
  Future<void> _loadTokensAndFetchSuppliers() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? '';
    _refreshToken = prefs.getString('refreshToken') ?? '';

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await fetchSuppliers();
  }

  // ------------------------------
  // FETCH SUPPLIERS
  // ------------------------------
  Future<void> fetchSuppliers() async {
    setState(() => isLoading = true);
    http.Response response = await http.get(
      Uri.parse(_SUPPLIERS_API_URL),
      headers: headers,
    );

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await http.get(
        Uri.parse(_SUPPLIERS_API_URL),
        headers: headers,
      );
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          suppliers = jsonDecode(response.body);
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
          SnackBar(
            content: Text("Failed to load suppliers: ${response.statusCode}"),
          ),
        );
      }
    }
  }

  // ------------------------------
  // DELETE SUPPLIER
  // ------------------------------
  Future<void> deleteSupplier(int id) async {
    http.Response response = await http.delete(
      Uri.parse("$_SUPPLIERS_API_URL$id/"),
      headers: headers,
    );

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await http.delete(
        Uri.parse("$_SUPPLIERS_API_URL$id/"),
        headers: headers,
      );
    }

    if (response.statusCode == 204) {
      fetchSuppliers();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to delete supplier: ${response.body}"),
          ),
        );
      }
    }
  }

  void goToFormScreen(Map? supplier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierFormScreen(
          supplier: supplier,
          accessToken: _accessToken,
          refreshTokenUtility: _refreshTokenUtility,
          onSaved: fetchSuppliers,
        ),
      ),
    );
  }

  Future<void> _showPayDialog(Map supplier) async {
    final TextEditingController amountController = TextEditingController();
    final double remaining = supplier["remaining_amount"]?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("Pay Remaining to ${supplier["name"]}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Remaining: \$${remaining.toStringAsFixed(2)}"),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Enter amount to pay",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountController.text.trim()) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Enter a valid amount")),
                  );
                  return;
                }

                Navigator.pop(ctx);
                await _payRemainingAmount(supplier["id"], amount);
              },
              child: const Text("Pay"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _payRemainingAmount(int supplierId, double amount) async {
    final url = Uri.parse("$_SUPPLIERS_API_URL$supplierId/pay/");
    http.Response response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({"amount": amount}),
    );

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({"amount": amount}),
      );
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Payment successful. Remaining: \$${data['remaining_amount']}",
          ),
        ),
      );
      fetchSuppliers(); // refresh the table
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to pay: ${response.body}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Supplier Management")),
      drawer: const SideBar(selectedPage: 'Supplier'),
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
                  DataColumn(label: Text("Phone")),
                  DataColumn(label: Text("Email")),
                  DataColumn(label: Text("Address")),
                  DataColumn(label: Text("Shop")),
                  DataColumn(label: Text("Remaining Amount")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: suppliers.map((supplier) {
                  return DataRow(
                    cells: [
                      DataCell(Text(supplier["id"].toString())),
                      DataCell(Text(supplier["name"] ?? "-")),
                      DataCell(Text(supplier["phone"] ?? "-")),
                      DataCell(Text(supplier["email"] ?? "-")),
                      DataCell(Text(supplier["address"] ?? "-")),
                      DataCell(
                        Text(
                          supplier["shop"] != null
                              ? supplier["shop"]["name"]
                              : "-",
                        ),
                      ),
                      DataCell(
                        Text(
                          supplier["remaining_amount"] != null
                              ? "\$${supplier["remaining_amount"].toString()}"
                              : "\$0",
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => goToFormScreen(supplier),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteSupplier(supplier["id"]),
                            ),
                            if ((supplier["remaining_amount"] ?? 0) > 0)
                              IconButton(
                                icon: const Icon(
                                  Icons.attach_money,
                                  color: Colors.green,
                                ),
                                tooltip: "Pay Remaining",
                                onPressed: () => _showPayDialog(supplier),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}

// ============================
// 3. SupplierFormScreen Widget (MODIFIED for Read-Only Shop)
// ============================
typedef RefreshTokenUtility = Future<bool> Function();

class SupplierFormScreen extends StatefulWidget {
  final Map? supplier;
  final String accessToken;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback onSaved;

  const SupplierFormScreen({
    super.key,
    this.supplier,
    required this.accessToken,
    required this.refreshTokenUtility,
    required this.onSaved,
  });

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  List shops = [];
  int? selectedShopId;
  int? _loggedInUserShopId; // ADDED: User's assigned shop ID
  late String _currentAccessToken;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;

    // Load user shop ID, then fetch shops and handle auto-selection
    _loadUserShopIdAndFetchData();

    if (widget.supplier != null) {
      nameController.text = widget.supplier!["name"] ?? "";
      phoneController.text = widget.supplier!["phone"] ?? "";
      emailController.text = widget.supplier!["email"] ?? "";
      addressController.text = widget.supplier!["address"] ?? "";
      selectedShopId = widget.supplier!["shop"]?["id"];
    }
  }

  // NEW: Loads user shop ID and handles auto-selection
  Future<void> _loadUserShopIdAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedInUserShopId = prefs.getInt('userShopId');

    await fetchShops();

    // Auto-select logic: Only for new suppliers if a user shop ID exists
    if (widget.supplier == null && _loggedInUserShopId != null) {
      final isValidShop = shops.any(
        (shop) => shop["id"] == _loggedInUserShopId,
      );

      if (isValidShop) {
        if (mounted) {
          setState(() {
            selectedShopId = _loggedInUserShopId;
            debugPrint(
              'DEBUG: SupplierForm Auto-selected shop ID: $selectedShopId',
            );
          });
        }
      }
    }
  }

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_currentAccessToken",
  };

  // Helper function to make API calls (GET, POST, PUT)
  Future<http.Response> _makeApiCall(
    String method,
    Uri url, {
    Map<String, dynamic>? payload,
  }) async {
    final body = payload != null ? jsonEncode(payload) : null;
    switch (method) {
      case 'GET':
        return http.get(url, headers: headers);
      case 'POST':
        return http.post(url, headers: headers, body: body);
      case 'PUT':
        return http.put(url, headers: headers, body: body);
      default:
        throw Exception("Invalid HTTP method");
    }
  }

  // FETCH SHOPS
  Future<void> fetchShops() async {
    http.Response response = await _makeApiCall(
      'GET',
      Uri.parse(_SHOPS_API_URL),
    );

    // Check for 401 and attempt refresh
    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';
        response = await _makeApiCall('GET', Uri.parse(_SHOPS_API_URL));
      }
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          shops = jsonDecode(response.body);
        });
      }
    } else if (response.statusCode != 401) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load shops: ${response.statusCode}"),
          ),
        );
      }
    }
  }

  // SAVE SUPPLIER
  Future<void> saveSupplier() async {
    if (!_formKey.currentState!.validate()) return;

    final isNewSupplier = widget.supplier == null;
    final payload = {
      "name": nameController.text,
      "phone": phoneController.text,
      "email": emailController.text,
      "address": addressController.text,
      "shop_id": selectedShopId,
    };

    final url = isNewSupplier
        ? Uri.parse(_SUPPLIERS_API_URL)
        : Uri.parse("$_SUPPLIERS_API_URL${widget.supplier!["id"]}/");

    final method = isNewSupplier ? 'POST' : 'PUT';

    http.Response response = await _makeApiCall(method, url, payload: payload);

    // Check for 401 and attempt refresh
    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';

        // Retry call with new Access Token
        response = await _makeApiCall(method, url, payload: payload);
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
          SnackBar(content: Text("Failed to save supplier: ${response.body}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine read-only state for the shop field
    final bool isReadOnlyShop =
        selectedShopId != null && selectedShopId == _loggedInUserShopId;

    final bool isFetchingShops = shops.isEmpty && _loggedInUserShopId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier == null ? "Add Supplier" : "Edit Supplier"),
      ),
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
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: "Phone"),
              ),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(labelText: "Address"),
              ),
              const SizedBox(height: 10),
              // Shop Dropdown - Modified for read-only and visual cues
              isFetchingShops
                  ? const Center(child: LinearProgressIndicator())
                  : DropdownButtonFormField<int>(
                      value: selectedShopId,
                      items: shops.map<DropdownMenuItem<int>>((shop) {
                        return DropdownMenuItem(
                          value: shop["id"],
                          child: Text(
                            shop["name"],
                            style: TextStyle(
                              color: isReadOnlyShop
                                  ? Colors.grey[700]
                                  : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                      // 🎯 KEY CHANGE: Disable `onChanged` if read-only
                      onChanged: isReadOnlyShop
                          ? null
                          : (value) => setState(() => selectedShopId = value),

                      decoration: InputDecoration(
                        labelText: "Shop",
                        // Visual cue for read-only state
                        filled: isReadOnlyShop,
                        fillColor: isReadOnlyShop ? Colors.grey[200] : null,
                        // Disable the suffix arrow and add lock icon when read-only
                        suffixIcon: isReadOnlyShop
                            ? const Icon(Icons.lock_outline, size: 20)
                            : null,
                      ),
                      validator: (value) =>
                          value == null ? "Please select a shop" : null,
                    ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: saveSupplier,
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
