import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../widgets/menu_bar.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

// CRITICAL FIX: API Constants & Type Definition
const String _BASE_URL = 'http://10.0.2.2:8000/api';
const String _REFRESH_URL = 'http://10.0.2.2:8000/api/token/refresh/';

class HomeScreen extends StatefulWidget {
  final String role; // 🔹 define fields
  final int? shopId;
  final String token; // ✅ define this

  const HomeScreen({
    super.key,
    required this.role,
    required this.shopId,
    required this.token,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> allProducts = [];
  String selectedCategory = "All";
  String searchQuery = "";
  bool isLoading = true;
  List<String> categories = ["All"];
  bool isCategoryLoading = true;

  // CRITICAL FIX: State variables for tokens (updated from local 'token' field)
  String _accessToken = '';
  String _refreshToken = '';

  final String apiUrl = "$_BASE_URL/products/"; // Use constant base URL

  // CRITICAL FIX: Headers now rely on the private state variable
  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $_accessToken",
  };

  @override
  void initState() {
    super.initState();
    _loadTokenAndFetchProducts();
  }

  Future<void> fetchCategories() async {
    try {
      final response = await _makeApiCall('GET', '$_BASE_URL/categories/');
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        setState(() {
          categories = ["All"]; // Always keep "All" first
          categories.addAll(data.map((cat) => cat['name'].toString()).toList());
          isCategoryLoading = false;
        });
      } else {
        setState(() => isCategoryLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load categories: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      setState(() => isCategoryLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading categories: $e')));
    }
  }

  // CRITICAL FIX: Load both access and refresh tokens
  Future<void> _loadTokenAndFetchProducts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accessToken =
          prefs.getString('accessToken') ??
          widget.token; // Use widget.token as fallback
      _refreshToken = prefs.getString('refreshToken') ?? '';
      // We don't set isLoading=false here; we let fetchProducts handle it.
    });

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      // Force re-login if critical tokens are missing
      await prefs.clear();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    fetchProducts();
    fetchCategories(); // 🔹 Fetch dynamic categories too
  }

  // CRITICAL FIX: Reusable token refresh utility
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, '/login');
        });
      }
      return false;
    }
  }

  // CRITICAL FIX: Define the common API call wrapper
  Future<http.Response> _makeApiCall(
    String method,
    String url, {
    Map<String, dynamic>? payload,
    int retryCount = 0,
  }) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    // Use the current access token for headers
    Map<String, String> currentHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };

    try {
      // We only use GET for this screen, but use a switch for generality
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: currentHeaders);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: currentHeaders);
          break;
        case 'POST':
          response = await http.post(uri, headers: currentHeaders, body: body);
          break;
        case 'PUT':
          response = await http.put(uri, headers: currentHeaders, body: body);
          break;
        default:
          throw Exception("Invalid HTTP method");
      }
    } catch (e) {
      rethrow;
    }

    if (response.statusCode == 401 && retryCount == 0) {
      final success = await _refreshTokenUtility(); // Attempt refresh

      if (success && mounted) {
        // Retry the call with the newly updated access token
        return _makeApiCall(
          method,
          url,
          payload: payload,
          retryCount: 1, // Only retry once
        );
      }
    }
    return response;
  }

  // CRITICAL FIX: Update fetchProducts to use _makeApiCall
  Future<void> fetchProducts() async {
    if (_accessToken.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await _makeApiCall('GET', apiUrl);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          allProducts = data.map((e) => Product.fromJson(e)).toList();
          isLoading = false;
        });
      } else if (response.statusCode != 401) {
        // 401 is handled by the utility, show others as failure
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to load products: ${response.statusCode}"),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error fetching products: $e")));
      }
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        searchQuery = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = theme.brightness == Brightness.dark;

    int crossAxisCount = screenWidth >= 1200
        ? 6
        : screenWidth >= 800
        ? 4
        : 2;
    double finalChildAspectRatio = screenWidth >= 800
        ? 0.8
        : 0.7; // Better balanced for all devices

    final filtered = allProducts.where((p) {
      final matchesCategory =
          selectedCategory == "All" || p.category == selectedCategory;
      final matchesSearch =
          searchQuery.isEmpty ||
          p.name.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: POSMenuBar(
        role: widget.role,
        totalAmount: cart.totalAmount,
        userRole: widget.role,
        userShopId: widget.shopId,
        token: _accessToken,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // 🔹 Filter + Search Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.cardColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    isCategoryLoading
                        ? const SizedBox(
                            height: 40,
                            width: 40,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedCategory,
                              dropdownColor: theme.colorScheme.surface
                                  .withOpacity(0.98),
                              items: categories
                                  .map(
                                    (cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Text(
                                        cat,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => selectedCategory = value!),
                            ),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: isDark
                              ? Colors.grey[850]
                              : Colors.grey[100], // Soft contrast
                          hintText: "Search products...",
                          hintStyle: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _scanBarcode,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) =>
                            setState(() => searchQuery = value),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 🔹 Product Grid
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: Colors.grey),
                          itemBuilder: (ctx, i) =>
                              _buildProductRow(context, filtered[i]),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductRow(BuildContext context, Product product) {
    final cart = context.read<CartProvider>();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          product.imageUrl,
          width: 45,
          height: 45,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.image_not_supported,
            size: 40,
            color: Colors.grey,
          ),
        ),
      ),
      title: Text(
        product.name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        product.category ?? '',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "\$${product.price.toStringAsFixed(2)}",
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_shopping_cart, color: Colors.blueAccent),
            onPressed: () => _showAddToCartDialog(context, product),
            tooltip: "Add to Cart",
          ),
        ],
      ),
      onTap: () => _showAddToCartDialog(context, product),
    );
  }
  void _showAddToCartDialog(BuildContext context, Product product) {
    final cart = context.read<CartProvider>();
    final qtyController = TextEditingController(text: '1');

    // Declare variables BEFORE using them
    ProductVariant? selectedVariant =
    product.variants.isNotEmpty ? product.variants[0] : null;

    bool isPackSelected = false;

    // Helper to compute real price
    double getPrice(ProductVariant? v) {
      if (v == null) return 0.0;
      return isPackSelected
          ? v.packSalePrice ?? v.salePrice
          : v.singleSalePrice ?? v.salePrice;
    }

    double price = getPrice(selectedVariant);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Add ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Variant Dropdown
              if (product.variants.isNotEmpty)
                DropdownButtonFormField<ProductVariant>(
                  value: selectedVariant,
                  items: product.variants.map((v) {
                    return DropdownMenuItem(
                      value: v,
                      child: Text(
                          '${v.colorName ?? "N/A"} / ${v.sizeName ?? "N/A"} (Stock: ${v.stockQuantity})'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      selectedVariant = v;
                      price = getPrice(selectedVariant);
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Select Variant'),
                ),

              const SizedBox(height: 12),

              // Pack / Single Toggle
              if (selectedVariant != null &&
                  (selectedVariant!.singleSalePrice != null ||
                      selectedVariant!.packSalePrice != null))
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Single'),
                      selected: !isPackSelected,
                      onSelected: (_) {
                        setState(() {
                          isPackSelected = false;
                          price = getPrice(selectedVariant);
                        });
                      },
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Pack'),
                      selected: isPackSelected,
                      onSelected: (_) {
                        setState(() {
                          isPackSelected = true;
                          price = getPrice(selectedVariant);
                        });
                      },
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              // Quantity
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),

              const SizedBox(height: 8),

              // Price
              Text(
                "Price: \$${price.toStringAsFixed(2)}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(qtyController.text) ?? 1;

                if (selectedVariant == null || selectedVariant!.id == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a variant')),
                  );
                  return;
                }

                final variantId = selectedVariant!.id; // already int

                final availableStock = selectedVariant!.stockQuantity;

                // Apply pack multiplier
                final unitsPerPack =
                isPackSelected ? (selectedVariant!.unitsPerPack ?? 1) : 1;

                final requiredUnits = qty * unitsPerPack;

                if (requiredUnits > availableStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Only $availableStock units available. You need $requiredUnits!',
                      ),
                    ),
                  );
                  return;
                }

                final cartItem = CartItem(
                  product: product,
                  variantId: variantId,
                  colorName: selectedVariant!.colorName ?? "N/A",
                  sizeName: selectedVariant!.sizeName ?? "N/A",
                  quantity: qty, // 🔹 this is number of packs if pack selected, else number of singles
                  price: price,
                  unitsPerPack: isPackSelected ? (selectedVariant!.unitsPerPack ?? 1) : 1,
                );

                cart.addToCart(
                  cartItem,
                  availableStock: availableStock,
                );

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '$qty × ${product.name} added to cart'),
                  ),
                );
              },
              child: const Text('Add to Cart'),
            ),
          ],
        ),
      ),
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Barcode")),
      body: MobileScanner(
        onDetect: (capture) {
          if (_isScanned) return;
          final barcode = capture.barcodes.first;
          final value = barcode.rawValue;
          if (value != null) {
            _isScanned = true;
            Navigator.pop(context, value); // ✅ Return scanned value
          }
        },
      ),
    );
  }
}
