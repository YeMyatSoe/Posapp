import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/admin/sidebar.dart';
// import '../../widgets/admin/sidebar.dart'; // Ensure this import is correct

// --- 1. BrandScreen (List View) ---

class BrandScreen extends StatefulWidget {
  const BrandScreen({super.key});
  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  final String apiUrl = "http://10.0.2.2:8000/api/brands/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  String accessToken = '';
  String refreshToken = '';
  List brands = [];
  bool isLoading = true;

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $accessToken",
  };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetch();
  }

  Future<void> _loadTokensAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken') ?? '';
    refreshToken = prefs.getString('refreshToken') ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    fetchBrands();
  }

  // REUSABLE TOKEN REFRESH UTILITY
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

  // FETCH BRANDS WITH REFRESH LOGIC
  Future<void> fetchBrands() async {
    setState(() => isLoading = true);
    Future<http.Response> _makeCall() => http.get(Uri.parse(apiUrl), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200) {
      setState(() {
        brands = jsonDecode(response.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      // Only show error if the final attempt failed and didn't redirect
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load brands: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE BRAND WITH REFRESH LOGIC
  Future<void> deleteBrand(int id) async {
    Future<http.Response> _makeCall() => http.delete(Uri.parse("$apiUrl$id/"), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 204) {
      fetchBrands();
    } else {
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete brand: ${response.body}")),
        );
      }
    }
  }

  void goToFormScreen(Map? brand) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandFormScreen(
          brand: brand,
          accessToken: accessToken, // Pass access token
          refreshToken: refreshToken, // Pass refresh token
          onSaved: fetchBrands,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Brands Management")),
       drawer: const SideBar(selectedPage: 'Brand'), // Uncomment if Sidebar is available
      floatingActionButton: FloatingActionButton(
        onPressed: () => goToFormScreen(null),
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          // ... DataTable columns and rows
          columns: const [
            DataColumn(label: Text("ID")),
            DataColumn(label: Text("Name")),
            DataColumn(label: Text("Shop")),
            DataColumn(label: Text("Active")),
            DataColumn(label: Text("Actions")),
          ],
          rows: brands.map((brand) {
            return DataRow(cells: [
              DataCell(Text(brand["id"].toString())),
              DataCell(Text(brand["name"] ?? "-")),
              DataCell(Text(brand["shop"]?["name"] ?? "-")),
              DataCell(Text(brand["is_active"].toString())),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => goToFormScreen(brand),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteBrand(brand["id"]),
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

// --- 2. BrandFormScreen (Form View) ---

class BrandFormScreen extends StatefulWidget {
  final Map? brand;
  final String accessToken; // Updated prop name
  final String refreshToken; // NEW: Added refresh token prop
  final VoidCallback onSaved;

  const BrandFormScreen({
    super.key,
    this.brand,
    required this.accessToken,
    required this.refreshToken,
    required this.onSaved
  });

  @override
  State<BrandFormScreen> createState() => _BrandFormScreenState();
}

class _BrandFormScreenState extends State<BrandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  bool isActive = true;

  List shops = [];
  int? selectedShopId;
  int? _loggedInUserShopId;
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";
  final String shopsUrl = "http://10.0.2.2:8000/api/shops/";
  final String brandsUrl = "http://10.0.2.2:8000/api/brands/";

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${widget.accessToken}", // Use widget.accessToken
  };

  @override
  void initState() {
    super.initState();
    if (widget.brand != null) {
      nameController.text = widget.brand!["name"];
      isActive = widget.brand!["is_active"];
      selectedShopId = widget.brand!["shop"]?["id"];
    }
    _loadUserShopIdAndFetchShops();
  }

  // REUSABLE TOKEN REFRESH UTILITY
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

      // We rely on the parent (BrandScreen) to rebuild, but for immediate use,
      // the parent's token is passed and we must assume the request will work now.
      return true;
    } else {
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

  // LOAD SHOP ID AND AUTO-SELECT LOGIC
  Future<void> _loadUserShopIdAndFetchShops() async {
    // 1. Load User's Default Shop ID from Storage
    final prefs = await SharedPreferences.getInstance();
    _loggedInUserShopId = prefs.getInt('userShopId');

    // 2. Fetch all shops
    await fetchShops();

    // 3. Auto-Select Default Shop if Creating New Brand
    if (widget.brand == null && _loggedInUserShopId != null) {
      final isValidShop = shops.any((shop) => shop["id"] == _loggedInUserShopId);

      if (isValidShop) {
        setState(() {
          selectedShopId = _loggedInUserShopId;
        });
      }
    }
  }

  // FETCH SHOPS WITH REFRESH LOGIC
  Future<void> fetchShops() async {
    Future<http.Response> _makeCall() => http.get(Uri.parse(shopsUrl), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          shops = jsonDecode(response.body);
        });
      }
    } else if (response.statusCode != 401 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load shops: ${response.statusCode}")),
      );
    }
  }

  // SAVE BRAND WITH REFRESH LOGIC
  Future<void> saveBrand() async {
    if (!_formKey.currentState!.validate() || selectedShopId == null) {
      if (mounted && selectedShopId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a shop")),
        );
      }
      return;
    }

    final payload = {
      "name": nameController.text,
      "is_active": isActive,
      "shop_id": selectedShopId,
    };

    final url = widget.brand == null
        ? Uri.parse(brandsUrl)
        : Uri.parse("$brandsUrl${widget.brand!["id"]}/");

    Future<http.Response> _makeCall() => widget.brand == null
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
        SnackBar(content: Text("Failed to save brand: ${response.body}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand == null ? "Add Brand" : "Edit Brand")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // ... (TextFormField for Name)
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name"),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 10),
              // ... (DropdownButtonFormField for Shop)
              DropdownButtonFormField<int>(
                value: selectedShopId,
                items: shops.map<DropdownMenuItem<int>>((shop) {
                  return DropdownMenuItem(
                    value: shop["id"],
                    child: Text(shop["name"]),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedShopId = value),
                decoration: const InputDecoration(labelText: "Shop"),
                validator: (value) => value == null ? "Please select a shop" : null,
              ),
              const SizedBox(height: 10),
              // ... (SwitchListTile for Active)
              SwitchListTile(
                title: const Text("Active"),
                value: isActive,
                onChanged: (v) => setState(() => isActive = v),
              ),
              const SizedBox(height: 20),
              // ... (Save Button)
              ElevatedButton(onPressed: saveBrand, child: const Text("Save")),
            ],
          ),
        ),
      ),
    );
  }
}