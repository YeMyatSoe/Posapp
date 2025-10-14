import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../widgets/menu_bar.dart';
import 'package:http/http.dart' as http;

// CRITICAL FIX: API Constants & Type Definition
const String _BASE_URL = 'http://10.0.2.2:8000/api';
const String _REFRESH_URL = 'http://10.0.2.2:8000/api/token/refresh/';

class HomeScreen extends StatefulWidget {
  final String role;    // 🔹 define fields
  final int? shopId;
  final String token;  // ✅ define this
  const HomeScreen({
    super.key,
    required this.role,
    required this.shopId, required this.token,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> allProducts = [];
  String selectedCategory = "All";
  String searchQuery = "";
  bool isLoading = true;

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

  // CRITICAL FIX: Load both access and refresh tokens
  Future<void> _loadTokenAndFetchProducts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accessToken = prefs.getString('accessToken') ?? widget.token; // Use widget.token as fallback
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
              SnackBar(content: Text("Failed to load products: ${response.statusCode}"))
          );
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error fetching products: $e"))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final screenWidth = MediaQuery.of(context).size.width;

    int crossAxisCount = screenWidth >= 1200
        ? 8
        : screenWidth >= 800
        ? 6
        : 4;
    double finalChildAspectRatio = screenWidth >= 1200
        ? 0.55 // Desktop (8 columns, needs a low ratio to stay tall)
        : screenWidth >= 800
        ? 0.83 // Tablet (6 columns)
        : 0.49; // Mobile (4 columns, shortest card height relative to width)

    // Filtered products
    final filtered = allProducts.where((p) {
      final matchesCategory = selectedCategory == "All" || p.category == selectedCategory;
      final matchesSearch = searchQuery.isEmpty || p.name.toLowerCase().contains(searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: POSMenuBar(
        role: widget.role,
        totalAmount: cart.totalAmount,
        userRole: widget.role,
        userShopId: widget.shopId,
        token: _accessToken, // CRITICAL FIX: Use the state's updated access token
      ),

      body: Column(
        children: [
          // Filter + Search
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                DropdownButton<String>(
                  value: selectedCategory,
                  items: const [
                    DropdownMenuItem(value: "All", child: Text("All")),
                    DropdownMenuItem(value: "Drinks", child: Text("Drinks")),
                    DropdownMenuItem(value: "Food", child: Text("Food")),
                    DropdownMenuItem(value: "Clothes", child: Text("Clothes")),
                  ],
                  onChanged: (value) => setState(() => selectedCategory = value!),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search products...",
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (value) => setState(() => searchQuery = value),
                  ),
                ),
              ],
            ),
          ),

          // Product Grid
          isLoading
              ? const Expanded(child: Center(child: CircularProgressIndicator()))
              : Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
                childAspectRatio: finalChildAspectRatio,
              ),
              itemBuilder: (ctx, i) => _buildProductCard(context, filtered[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    // Read cart provider but don't watch it (no rebuild needed for price change)
    final cart = context.read<CartProvider>();

    return GestureDetector(
      onTap: () => _showAddToCartDialog(context, product),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                product.imageUrl,
                height: 75,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  // const SizedBox(height: 3),
                  // Text('\$${product.price.toStringAsFixed(2)}',
                  //     style: const TextStyle(color: Colors.green)),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                ),
                onPressed: () => _showAddToCartDialog(context, product),
                label: const Text(""),
                icon: const Icon(Icons.add_shopping_cart, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToCartDialog(BuildContext context, Product product) {
    final cart = context.read<CartProvider>();
    final qtyController = TextEditingController(text: '1');

    // Default selected variant
    ProductVariant? selectedVariant =
    product.variants.isNotEmpty ? product.variants[0] : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Add ${product.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (product.variants.isNotEmpty)
                DropdownButtonFormField<ProductVariant>(
                  value: selectedVariant,
                  items: product.variants
                      .map(
                        (v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                          '${v.colorName ?? "N/A"} / ${v.sizeName ?? "N/A"} (Stock: ${v.stockQuantity})'),
                    ),
                  )
                      .toList(),
                  onChanged: (v) => setState(() => selectedVariant = v),
                  decoration: const InputDecoration(labelText: 'Select Variant'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(qtyController.text) ?? 1;

                if (selectedVariant == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a variant')),
                  );
                  return;
                }

                final availableStock = selectedVariant!.stockQuantity;

                if (qty > availableStock) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Only $availableStock items in stock!')),
                  );
                  return;
                }

                // Add to cart with correct quantity
                // NOTE: CartItem must be the one imported from cart_provider.dart
                final cartItem = CartItem(
                  product: product,
                  variantId: int.tryParse(selectedVariant?.id ?? '0') ?? 0,
                  colorName: selectedVariant?.colorName ?? "N/A",
                  sizeName: selectedVariant?.sizeName ?? "N/A",
                  quantity: qty,
                );

                cart.addToCart(cartItem, availableStock: availableStock);

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$qty × ${product.name} '
                          '${selectedVariant!.colorName ?? ""} '
                          '${selectedVariant!.sizeName ?? ""} added to cart',
                    ),
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