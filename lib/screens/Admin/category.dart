import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart'; // Ensure this path is correct

// --------------------------------------------------------------------------
// --- 1. CategoryScreen (List View) ---
// --------------------------------------------------------------------------

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  // API Endpoints
  final String apiUrl = "http://10.0.2.2:8000/api/categories/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  String accessToken = '';
  String refreshToken = '';
  List categories = [];
  bool isLoading = true;

  Map<String, String> get headers =>
      {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetch();
  }

  // Load tokens from storage and start data fetch
  Future<void> _loadTokensAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken') ?? '';
    refreshToken = prefs.getString('refreshToken') ?? '';

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    fetchCategories();
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
      // Refresh failed. Force re-login.
      await (await SharedPreferences.getInstance()).clear();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Session expired. Please log in again.")),
        );
      }
      return false;
    }
  }

  // FETCH CATEGORIES (with Refresh Logic)
  Future<void> fetchCategories() async {
    setState(() => isLoading = true);
    Future<http.Response> _makeCall() =>
        http.get(Uri.parse(apiUrl), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200) {
      setState(() {
        categories = jsonDecode(response.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "Failed to load categories: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE CATEGORY (with Refresh Logic)
  Future<void> deleteCategory(int id) async {
    Future<http.Response> _makeCall() =>
        http.delete(Uri.parse("$apiUrl$id/"), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 204) {
      fetchCategories();
    } else {
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Failed to delete category: ${response.body}")),
        );
      }
    }
  }

  void goToFormScreen(Map? category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CategoryFormScreen(
              category: category,
              accessToken: accessToken,
              refreshToken: refreshToken,
              onSaved: fetchCategories,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Category Management")),
      drawer: const SideBar(selectedPage: 'Category'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => goToFormScreen(null),
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 50,
          dataRowHeight: 70,
          columns: const [
            DataColumn(label: SizedBox(width: 100,
                child: Text(
                    "ID", maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataColumn(label: SizedBox(width: 100,
                child: Text(
                    "Name", maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataColumn(label: SizedBox(width: 100,
                child: Text(
                    "Shop", maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataColumn(label: SizedBox(width: 100,
                child: Text(
                    "Active", maxLines: 2, overflow: TextOverflow.ellipsis))),
            DataColumn(label: SizedBox(width: 100,
                child: Text(
                    "Actions", maxLines: 2, overflow: TextOverflow.ellipsis))),
          ],
          rows: categories.map((category) {
            return DataRow(cells: [
              DataCell(SizedBox(
                width: 100,
                child: Text(category["id"].toString(), maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(category["name"] ?? "-", maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(category["shop"]?["name"] ?? "-", maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(category["is_active"].toString(), maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit
                      InkWell(
                        onTap: () => goToFormScreen(category),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: const [
                              Icon(Icons.edit, size: 16, color: Colors.white),
                              SizedBox(width: 2),
                              Text("Edit", style: TextStyle(
                                  color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                      // Divider
                      Container(width: 1,
                          color: Colors.white.withOpacity(0.5),
                          height:20),
                      // Delete
                      PopupMenuButton(
                        color: Colors.red[300],

                        icon: const Icon(
                            Icons.arrow_drop_down, color: Colors.white),
                        itemBuilder: (context) =>
                        [
                          PopupMenuItem(
                            height: 10,
                            value: 'delete',
                            child: Row(
                              children: const [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 4),
                                Text("Delete"),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'delete') deleteCategory(category["id"]);
                        },
                      ),
                    ],
                  ),
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
// --------------------------------------------------------------------------
// --- 2. CategoryFormScreen (Form View) ---
// --------------------------------------------------------------------------

class CategoryFormScreen extends StatefulWidget {
  final Map? category;
  final String accessToken;
  final String refreshToken;
  final VoidCallback onSaved;

  const CategoryFormScreen({
    super.key,
    this.category,
    required this.accessToken,
    required this.refreshToken,
    required this.onSaved,
  });

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  bool isActive = true;

  List shops = [];
  int? selectedShopId;
  int? _loggedInUserShopId; // Used for auto-select shop

  // API Endpoints
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";
  final String shopsUrl = "http://10.0.2.2:8000/api/shops/";
  final String categoriesUrl = "http://10.0.2.2:8000/api/categories/";

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer ${widget.accessToken}",
  };

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      nameController.text = widget.category!["name"];
      isActive = widget.category!["is_active"];
      // selectedShopId = widget.category!["shop"]?["id"];
    }
    _loadUserShopIdAndFetchShops();
  }

  // REUSABLE TOKEN REFRESH UTILITY (Uses token from the widget)
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

      // Note: We don't update widget.accessToken directly,
      // but the retried API call in saveCategory or fetchShops
      // will use the new token from SharedPreferences/reloaded headers.
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
// CategoryFormScreen: _loadUserShopIdAndFetchShops method

  Future<void> _loadUserShopIdAndFetchShops() async {
    // ... (token check)

    final prefs = await SharedPreferences.getInstance();
    _loggedInUserShopId = prefs.getInt('userShopId'); // Load user's default shop ID

    // 🎯 DEBUG PRINT 1: Check the ID loaded from storage
    debugPrint('DEBUG: Shop ID loaded from SharedPreferences: $_loggedInUserShopId');

    await fetchShops();

    // Auto-Select Default Shop if Creating New Category
    if (widget.category == null && _loggedInUserShopId != null) {
      final isValidShop = shops.any((shop) => shop["id"] == _loggedInUserShopId);

      if (isValidShop) {
        setState(() {
          selectedShopId = _loggedInUserShopId;
        });
        // 🎯 DEBUG PRINT 2: Check if auto-selection was successful
        debugPrint('DEBUG: Auto-selected Shop ID: $selectedShopId');
      } else {
        // 🎯 DEBUG PRINT 3: Check if shop ID failed validation
        debugPrint('DEBUG: Loaded Shop ID $_loggedInUserShopId is not in the fetched shops list.');
      }
    } else {
      // 🎯 DEBUG PRINT 4: Explain why auto-select didn't run
      debugPrint('DEBUG: Auto-select skipped. New Category: ${widget.category == null}. Logged-in Shop ID present: ${_loggedInUserShopId != null}.');
    }
  }
  // FETCH SHOPS (with Refresh Logic)
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

  // SAVE CATEGORY (with Refresh Logic)
  Future<void> saveCategory() async {
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

    final url = widget.category == null
        ? Uri.parse(categoriesUrl)
        : Uri.parse("$categoriesUrl${widget.category!["id"]}/");

    Future<http.Response> _makeCall() => widget.category == null
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
        SnackBar(content: Text("Failed to save category: ${response.body}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isShopReadOnly = widget.category == null && _loggedInUserShopId != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category == null ? "Add Category" : "Edit Category")),
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
              const SizedBox(height: 10),
              // Shop Dropdown with Auto-Select
              DropdownButtonFormField<int>(
                value: selectedShopId,
                items: shops.map<DropdownMenuItem<int>>((shop) {
                  return DropdownMenuItem(
                    value: shop["id"],
                    // Use a slightly different text color for disabled state
                    child: Text(
                      shop["name"] ?? "-",
                      style: TextStyle(
                        color: isShopReadOnly ? Colors.grey[700] : Colors.black,
                      ),
                    ),
                  );
                }).toList(),

                // 🎯 KEY CHANGE: Set onChanged to null if it should be read-only
                onChanged: isShopReadOnly
                    ? null
                    : (value) => setState(() => selectedShopId = value),

                decoration: InputDecoration(
                  labelText: "Shop",
                  // Visual cue for read-only state
                  filled: isShopReadOnly,
                  fillColor: isShopReadOnly ? Colors.grey[200] : null,
                  // Disable the suffix arrow when read-only
                  suffixIcon: isShopReadOnly ? const Icon(Icons.lock_outline, size: 20) : null,
                ),
                validator: (value) => value == null ? "Please select a shop" : null,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: const Text("Active"),
                value: isActive,
                onChanged: (v) => setState(() => isActive = v),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveCategory, child: const Text("Save")),
            ],
          ),
        ),
      ),
    );
  }
}