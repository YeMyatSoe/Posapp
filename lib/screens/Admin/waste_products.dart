import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/admin/sidebar.dart';

// ============================
// 1. API Constants
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000';
const String _WASTE_API_URL = '$_API_BASE_URL/api/waste-products/';
const String _SHOPS_API_URL = '$_API_BASE_URL/api/shops/';
const String _PRODUCTS_API_URL = '$_API_BASE_URL/api/products/';
const String _VARIANTS_API_URL = '$_API_BASE_URL/api/product-variants/';
const String _REFRESH_URL = '$_API_BASE_URL/api/token/refresh/';

// ============================
// 2. WasteScreen Widget
// ============================
class WasteScreen extends StatefulWidget {
  const WasteScreen({super.key});

  @override
  State<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends State<WasteScreen> {
  List wasteList = [];
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
    _loadTokensAndFetch();
  }

  // REUSABLE TOKEN REFRESH UTILITY
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
          _accessToken = newAccessToken; // Update local state
        });
      }
      return true;
    } else {
      // Refresh failed. Force re-login.
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
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      setState(() => isLoading = false);
      return;
    }

    await fetchWasteProducts();
  }

  // FETCH WASTE PRODUCTS (Updated with Refresh Logic)
  Future<void> fetchWasteProducts() async {
    if (_accessToken.isEmpty) return;

    setState(() => isLoading = true);
    http.Response response = await http.get(Uri.parse(_WASTE_API_URL), headers: headers);

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await http.get(Uri.parse(_WASTE_API_URL), headers: headers);
    }

    if (response.statusCode == 200) {
      if (mounted) {
        setState(() {
          wasteList = jsonDecode(response.body);
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
          SnackBar(content: Text("Failed to load waste products: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE WASTE PRODUCT (Updated with Refresh Logic)
  Future<void> deleteWasteProduct(int id) async {
    if (_accessToken.isEmpty) return;

    http.Response response = await http.delete(Uri.parse("$_WASTE_API_URL$id/"), headers: headers);

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await http.delete(Uri.parse("$_WASTE_API_URL$id/"), headers: headers);
    }

    if (response.statusCode == 204) {
      fetchWasteProducts();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete waste product: ${response.body}")),
        );
      }
    }
  }

  void goToFormScreen(Map? waste) {
    if (_accessToken.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WasteFormScreen(
          waste: waste,
          accessToken: _accessToken,
          refreshTokenUtility: _refreshTokenUtility,
          onSaved: fetchWasteProducts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accessToken.isEmpty && !isLoading) {
      return const Center(child: Text("Authentication Failed. Redirecting..."));
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Waste Management")),
      drawer: const SideBar(selectedPage: 'WasteProduct'),
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
            DataColumn(label: Text("Shop")),
            DataColumn(label: Text("Product")),
            DataColumn(label: Text("Variant")),
            DataColumn(label: Text("Quantity")),
            DataColumn(label: Text("Unit COGS")),
            DataColumn(label: Text("Loss Value")),
            DataColumn(label: Text("Reason")),
            DataColumn(label: Text("Date")),
            DataColumn(label: Text("Actions")),
          ],
          rows: wasteList.map((waste) {
            final quantity = waste["quantity"] ?? 0;
            final unitCogs = double.tryParse(
                waste["unit_purchase_price"]?.toString() ?? '0') ??
                0.0;
            final lossValue = double.tryParse(
                waste["total_loss_value"]?.toString() ?? '0') ??
                0.0;

            final variantText =
                "${waste["color_name"] ?? "-"} / ${waste["size_name"] ?? "-"}";

            return DataRow(cells: [
              DataCell(Text(waste["id"].toString())),
              DataCell(Text(waste["shop_name"]?.toString() ?? "-")),
              DataCell(Text(waste["product_name"]?.toString() ?? "-")),
              DataCell(Text(variantText)),
              DataCell(Text(quantity.toString())),
              DataCell(Text("\$${unitCogs.toStringAsFixed(2)}")),
              DataCell(Text("\$${lossValue.toStringAsFixed(2)}")),
              DataCell(Text(waste["reason"] ?? "-")),
              DataCell(
                  Text(waste["recorded_at"]?.split("T").first ?? "-")),
              DataCell(Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => goToFormScreen(waste),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => deleteWasteProduct(waste["id"]),
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
// 3. WasteFormScreen Widget (MODIFIED for Read-Only Shop)
// ============================
typedef RefreshTokenUtility = Future<bool> Function();

class WasteFormScreen extends StatefulWidget {
  final Map? waste;
  final String accessToken;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback onSaved;

  const WasteFormScreen({
    super.key,
    this.waste,
    required this.accessToken,
    required this.refreshTokenUtility,
    required this.onSaved,
  });

  @override
  State<WasteFormScreen> createState() => _WasteFormScreenState();
}

class _WasteFormScreenState extends State<WasteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();

  List shops = [];
  int? selectedShopId;
  int? _loggedInUserShopId;

  List products = [];
  int? selectedProductId;

  List variants = [];
  int? selectedVariantId;
  double unitCogs = 0.0;
  late String _currentAccessToken;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.accessToken;

    if (widget.waste != null) {
      quantityController.text = widget.waste!["quantity"].toString();
      reasonController.text = widget.waste!["reason"] ?? "";
      selectedShopId = widget.waste!["shop_id"];
      selectedProductId = widget.waste!["product_id"];
      selectedVariantId = widget.waste!["variant_id"];
      unitCogs = double.tryParse(
          widget.waste!["unit_purchase_price"]?.toString() ?? '0') ??
          0.0;
    }

    _loadUserShopIdAndFetchData();
  }

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_currentAccessToken",
  };

  // Helper function to make API calls (GET, POST, PUT)
  Future<http.Response> _makeApiCall(String method, Uri url, {Map<String, dynamic>? payload}) async {
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

  Future<void> _loadUserShopIdAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedInUserShopId = prefs.getInt('userShopId');

    debugPrint('DEBUG: WasteForm loaded userShopId: $_loggedInUserShopId');

    await fetchShops();
    await fetchProducts();

    if (widget.waste == null && _loggedInUserShopId != null) {
      final isValidShop = shops.any((shop) => shop["id"] == _loggedInUserShopId);

      if (isValidShop) {
        setState(() {
          selectedShopId = _loggedInUserShopId;
          debugPrint('DEBUG: WasteForm Auto-selected shop ID: $selectedShopId');
        });
      } else {
        debugPrint('DEBUG: WasteForm Auto-select failed. Shop ID $_loggedInUserShopId not found in fetched list.');
      }
    } else {
      debugPrint('DEBUG: WasteForm Auto-select skipped. Existing waste: ${widget.waste != null}. ID present: ${_loggedInUserShopId != null}');
    }
  }


  Future<void> fetchShops() async {
    http.Response response = await _makeApiCall('GET', Uri.parse(_SHOPS_API_URL));

    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';
        response = await _makeApiCall('GET', Uri.parse(_SHOPS_API_URL));
      }
    }

    if (response.statusCode == 200) {
      if (mounted) setState(() => shops = jsonDecode(response.body));
    } else if (response.statusCode != 401) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load shops: ${response.statusCode}")),
        );
      }
    }
  }

  Future<void> fetchProducts() async {
    http.Response response = await _makeApiCall('GET', Uri.parse(_PRODUCTS_API_URL));

    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';
        response = await _makeApiCall('GET', Uri.parse(_PRODUCTS_API_URL));
      }
    }

    if (response.statusCode == 200) {
      if (mounted) setState(() => products = jsonDecode(response.body));
      if (selectedProductId != null) {
        fetchVariants(selectedProductId!);
      }
    } else if (response.statusCode != 401) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load products: ${response.statusCode}")),
        );
      }
    }
  }

  Future<void> fetchVariants(int productId) async {
    final url = Uri.parse("$_VARIANTS_API_URL?product=$productId");
    http.Response response = await _makeApiCall('GET', url);

    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';
        response = await _makeApiCall('GET', url);
      }
    }

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      if (mounted) setState(() => variants = data);
    } else {
      if (mounted) setState(() => variants = []);
      if (mounted && response.statusCode != 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load variants: ${response.statusCode}")),
        );
      }
    }
  }

  Future<void> saveWaste() async {
    if (!_formKey.currentState!.validate()) return;

    final isNew = widget.waste == null;
    final payload = {
      "shop_id": selectedShopId,
      "variant_id": selectedVariantId,
      "quantity": int.tryParse(quantityController.text) ?? 0,
      "reason": reasonController.text,
    };

    final url = isNew
        ? Uri.parse(_WASTE_API_URL)
        : Uri.parse("$_WASTE_API_URL${widget.waste!["id"]}/");

    final method = isNew ? 'POST' : 'PUT';

    http.Response response = await _makeApiCall(method, url, payload: payload);

    if (response.statusCode == 401) {
      final success = await widget.refreshTokenUtility();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        _currentAccessToken = prefs.getString('accessToken') ?? '';
        response = await _makeApiCall(method, url, payload: payload);
      }
    }

    if ([200, 201, 204].contains(response.statusCode)) {
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
          SnackBar(content: Text("Failed to save waste: ${response.body}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine read-only state: if it's a new form AND we have a shop ID for the user
    final bool isShopReadOnly = widget.waste == null && _loggedInUserShopId != null;

    return Scaffold(
      appBar:
      AppBar(title: Text(widget.waste == null ? "Add Waste" : "Edit Waste")),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Shop Dropdown - Modified to be read-only based on logic
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
              DropdownButtonFormField<int>(
                value: selectedProductId,
                items: products.map<DropdownMenuItem<int>>((product) {
                  return DropdownMenuItem(
                    value: product["id"],
                    child: Text(product["name"] ?? "-"),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    selectedProductId = v;
                    selectedVariantId = null;
                    unitCogs = 0.0;
                    if (v != null) fetchVariants(v);
                  });
                },
                decoration: const InputDecoration(labelText: "Product"),
                validator: (v) => v == null ? "Please select a product" : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: selectedVariantId,
                items: variants.map<DropdownMenuItem<int>>((variant) {
                  return DropdownMenuItem(
                    value: variant["id"],
                    child: Text(
                        "${variant["color_name"] ?? "-"} / ${variant["size_name"] ?? "-"}"),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    selectedVariantId = v;
                    if (v != null) {
                      final variant = variants.firstWhere((e) => e["id"] == v);
                      unitCogs =
                          double.tryParse(variant["unit_purchase_price"].toString()) ?? 0.0;
                    } else {
                      unitCogs = 0.0;
                    }
                  });
                },
                decoration: const InputDecoration(labelText: "Variant"),
                validator: (v) => v == null ? "Please select a variant" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Quantity"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: "Reason"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 20),
              Text(
                "Unit COGS: \$${unitCogs.toStringAsFixed(2)}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveWaste, child: const Text("Save")),
            ],
          ),
        ),
      ),
    );
  }
}
