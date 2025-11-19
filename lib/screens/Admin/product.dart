import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:multi_select_flutter/dialog/multi_select_dialog_field.dart';
import 'package:multi_select_flutter/util/multi_select_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart';

class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String category;
  final String? barcode; // ✅ Added barcode field
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.barcode, // ✅ optional
    this.variants = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    List<ProductVariant> parseVariants(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((v) => ProductVariant.fromJson(v)).toList();
      }
      return [];
    }

    final variants = parseVariants(json['variants']);

    double price = variants.isNotEmpty
        ? variants.map((v) => v.effectivePrice).reduce((a, b) => a < b ? a : b)
        : 0.0;

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: price,
      imageUrl: json['image'] ?? 'https://picsum.photos/200/300',
      category: json['category']?.toString() ?? 'Uncategorized',
      barcode: json['barcode']?.toString(),
      variants: variants,
    );
  }
}
class ProductVariant {
  final int id;
  final int? color;
  final int? size;
  final String? colorName;
  final String? sizeName;
  final int stockQuantity;
  final double salePrice;
  final double? singleSalePrice;
  final double? packSalePrice;
  final bool isPack;
  final int unitsPerPack;

  ProductVariant({
    required this.id,
    this.color,
    this.size,
    this.colorName,
    this.sizeName,
    this.stockQuantity = 0,
    required this.salePrice,
    this.singleSalePrice,
    this.packSalePrice,
    this.isPack = false,
    this.unitsPerPack = 1,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ProductVariant(
      id: parseInt(json['id']),
      color: json['color'] != null ? parseInt(json['color']) : null,
      size: json['size'] != null ? parseInt(json['size']) : null,
      colorName: json['color_name'],
      sizeName: json['size_name'],
      stockQuantity: parseInt(json['stock_quantity']),
      salePrice: parseDouble(json['sale_price']),
      singleSalePrice: json['single_sale_price'] != null
          ? parseDouble(json['single_sale_price'])
          : null,
      packSalePrice: json['pack_sale_price'] != null
          ? parseDouble(json['pack_sale_price'])
          : null,
      isPack: json['is_pack'] ?? false,
      unitsPerPack: parseInt(json['units_per_pack'] ?? 1),
    );
  }

  double get effectivePrice {
    if (isPack) return packSalePrice ?? salePrice;
    return singleSalePrice ?? salePrice;
  }
}



// ---------------- Product Screen ----------------

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final String apiUrl = "http://10.0.2.2:8000/api/products/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";
  final int lowStockThreshold = 5;

  String accessToken = '';
  String refreshToken = '';
  List<Product> products = [];

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

    await fetchProducts();
    await checkLowStock();
  }

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
      setState(() => accessToken = newAccessToken);
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

  Future<void> fetchProducts() async {
    setState(() => isLoading = true);
    Future<http.Response> _makeCall() => http.get(Uri.parse(apiUrl), headers: headers);
    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall();
    }

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);

      List<Product> parsedProducts = data.map((json) => Product.fromJson(json)).toList();

      // Sort by total stock
      parsedProducts.sort((a, b) {
        final totalA = a.variants.fold(0, (sum, v) => sum + v.stockQuantity);
        final totalB = b.variants.fold(0, (sum, v) => sum + v.stockQuantity);
        return totalA.compareTo(totalB);
      });

      setState(() {
        products = parsedProducts;
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load products: ${response.statusCode}")),
        );
      }
    }
  }


  Future<void> deleteProduct(int id) async {
    Future<http.Response> _makeCall() =>
        http.delete(Uri.parse("$apiUrl$id/"), headers: headers);
    http.Response response = await _makeCall();
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall();
    }
    if (response.statusCode == 204) {
      fetchProducts();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete product: ${response.body}")),
        );
      }
    }
  }

  Future<void> checkLowStock() async {
    final String lowStockUrl =
        "http://10.0.2.2:8000/api/low-stock/?threshold=$lowStockThreshold";

    try {
      final response = await http.get(Uri.parse(lowStockUrl), headers: headers);
      if (response.statusCode == 401 && await _refreshTokenUtility()) {
        return checkLowStock();
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.orange[700],
              content: Text(
                "⚠️ ${data.length} product variants are running low (≤ $lowStockThreshold stock).",
                style: const TextStyle(color: Colors.white),
              ),
              action: SnackBarAction(
                label: "View",
                textColor: Colors.white,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Low Stock Alerts"),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: data.length,
                          itemBuilder: (context, index) {
                            final item = data[index];
                            return ListTile(
                              title: Text(item["product_name"]),
                              subtitle: Text(
                                "Color: ${item["color_name"] ?? "-"}, Size: ${item["size_name"] ?? "-"}",
                              ),
                              trailing: Text(
                                "Qty: ${item["stock_quantity"]}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Close"),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking low stock: $e");
    }
  }

  void goToEditScreen(Map product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProductScreen(
          product: product,
          accessToken: accessToken,
          refreshToken: refreshToken,
          onSaved: fetchProducts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Product Management")),
      drawer: const SideBar(selectedPage: 'Product'),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowHeight: 50,
                  dataRowHeight: 70,
                  columns: const [
                    DataColumn(label: Text("ID")),
                    DataColumn(label: Text("Name")),
                    DataColumn(label: Text("Category")),
                    DataColumn(label: Text("Shop")),
                    DataColumn(label: Text("Variants")),
                    DataColumn(label: Text("Purchase Price")),
                    DataColumn(label: Text("Sale Price")),
                    DataColumn(label: Text("Actions")),
                  ],
                  rows: products.map((product) {
                    final totalStock = product.variants.fold(0, (sum, v) => sum + v.stockQuantity);
                    final isLowStock = totalStock <= lowStockThreshold;

                    return DataRow(
                      color: MaterialStateProperty.resolveWith<Color?>(
                            (states) => isLowStock ? Colors.red.withOpacity(0.15) : null,
                      ),
                      cells: [
                        DataCell(Text(product.id)),
                        DataCell(Text(product.name)),
                        DataCell(Text(product.category)),
                        DataCell(Text("-")), // Replace with product.shopName if available
                        DataCell(Text("${product.variants.length} types, Stock: $totalStock")),
                        DataCell(Text(product.price.toString())), // purchasePrice not in Product? Add if needed
                        DataCell(Text(product.price.toString())), // salePrice
                        DataCell(Row(
                          children: [
                            InkWell(
                              onTap: () => goToEditScreen(product as Map),
                              child: const Icon(Icons.edit, color: Colors.green),
                            ),
                            const SizedBox(width: 5),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => deleteProduct(int.parse(product.id)),
                            ),
                          ],
                        )),
                      ],
                    );
                  }).toList(),

                ),
              ),
            ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "checkStock",
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text("Check Stock"),
            backgroundColor: Colors.orangeAccent,
            onPressed: checkLowStock,
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "addProduct",
            onPressed: () {
              if (accessToken.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddProductScreen(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    onSaved: fetchProducts,
                  ),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

// ---------------- Edit Product Screen (FIXED) ----------------
class EditProductScreen extends StatefulWidget {
  final Map product;
  final String accessToken;
  final String refreshToken;
  final VoidCallback onSaved;

  const EditProductScreen({
    super.key,
    required this.product,
    required this.accessToken,
    required this.refreshToken,
    required this.onSaved,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  File? selectedImage;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController purchasePriceController = TextEditingController();
  final TextEditingController salePriceController = TextEditingController();
  final TextEditingController paidAmountController = TextEditingController();
  final TextEditingController totalAmountController = TextEditingController();
  final TextEditingController remainingAmountController =
      TextEditingController();

  Map<String, TextEditingController> variantStockControllers = {};
  List initialVariants = [];

  int? categoryId;
  int? brandId;
  int? supplierId;
  int? shopId;

  List categories = [];
  List brands = [];
  List colors = [];
  List sizes = [];
  List suppliers = [];
  List shops = [];

  List selectedColors = [];
  List selectedSizes = [];

  final String apiUrl = "http://10.0.2.2:8000/api/products/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  Map<String, String> get headers => {
    "Authorization": "Bearer ${widget.accessToken}",
  };

  @override
  void initState() {
    super.initState();
    shopId = widget.product["shop"]?["id"];
    // Initialize controllers
    nameController.text = widget.product["name"] ?? "";
    purchasePriceController.text =
        widget.product["purchase_price"]?.toString() ?? "0";
    salePriceController.text = widget.product["sale_price"]?.toString() ?? "0";
    paidAmountController.text =
        widget.product["paid_amount"]?.toString() ?? "0";
    totalAmountController.text =
        widget.product["total_amount"]?.toString() ?? "0";
    remainingAmountController.text =
        widget.product["remaining_amount"]?.toString() ?? "0";

    categoryId = widget.product["category"]?["id"];
    brandId = widget.product["brand"]?["id"];
    supplierId = widget.product["supplier"]?["id"];
    // shopId = widget.product["shop"]?["id"];

    selectedColors = (widget.product["colors"] as List? ?? [])
        .cast<Map<String, dynamic>>();
    selectedSizes = (widget.product["sizes"] as List? ?? [])
        .cast<Map<String, dynamic>>();
    initialVariants = widget.product["variants"] ?? [];

    // Listen to price / paid changes
    purchasePriceController.addListener(_recalculateTotals);
    salePriceController.addListener(_recalculateTotals);
    paidAmountController.addListener(_recalculateTotals);

    fetchDropdowns();
  }

  @override
  void dispose() {
    variantStockControllers.values.forEach((c) => c.dispose());
    nameController.dispose();
    purchasePriceController.dispose();
    salePriceController.dispose();
    paidAmountController.dispose();
    totalAmountController.dispose();
    remainingAmountController.dispose();
    super.dispose();
  }

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

      setState(() {}); // Update headers
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

  void _recalculateTotals() {
    int totalStock = variantStockControllers.values
        .map((c) => int.tryParse(c.text) ?? 0)
        .fold(0, (a, b) => a + b);

    double salePrice = double.tryParse(salePriceController.text) ?? 0.0;
    double paidAmount = double.tryParse(paidAmountController.text) ?? 0.0;

    double totalAmount = salePrice * totalStock;
    double remainingAmount = totalAmount - paidAmount;

    totalAmountController.text = totalAmount.toStringAsFixed(2);
    remainingAmountController.text = remainingAmount.toStringAsFixed(2);
  }

  int _getInitialStock(int colorId, int sizeId) {
    final variant = initialVariants.firstWhere((v) {
      final vColorId = v['color'] is Map ? v['color']['id'] : v['color'];
      final vSizeId = v['size'] is Map ? v['size']['id'] : v['size'];
      return vColorId == colorId && vSizeId == sizeId;
    }, orElse: () => null);
    return variant?['stock_quantity'] ?? 0;
  }

  void _onColorsSelected(List newColors) {
    setState(() {
      // Add new colors to selectedColors
      for (var c in newColors) {
        if (!selectedColors.any((sc) => sc['id'] == c['id'])) {
          selectedColors.add(c);
        }
      }
      _updateVariantControllers();
    });
  }

  void _onSizesSelected(List newSizes) {
    setState(() {
      for (var s in newSizes) {
        if (!selectedSizes.any((ss) => ss['id'] == s['id'])) {
          selectedSizes.add(s);
        }
      }
      _updateVariantControllers();
    });
  }

  void _mapSelectedVariantsToDropdowns() {
    selectedColors = (widget.product["colors"] as List? ?? [])
        .map<Map<String, dynamic>>(
          (c) => colors.firstWhere(
            (color) => color['id'] == (c['id'] ?? c),
            orElse: () => {'id': c['id'], 'name': c['name'] ?? 'Unknown'},
          ),
        )
        .toList();

    selectedSizes = (widget.product["sizes"] as List? ?? [])
        .map<Map<String, dynamic>>(
          (s) => sizes.firstWhere(
            (size) => size['id'] == (s['id'] ?? s),
            orElse: () => {'id': s['id'], 'name': s['name'] ?? 'Unknown'},
          ),
        )
        .toList();
  }

  // Initialize stock controllers for all combinations (existing or new)
  void _updateVariantControllers() {
    final colorList = selectedColors.isNotEmpty
        ? selectedColors
        : [
            {'id': 0, 'name': 'N/A Color'},
          ];
    final sizeList = selectedSizes.isNotEmpty
        ? selectedSizes
        : [
            {'id': 0, 'name': 'N/A Size'},
          ];

    final keysNeeded = colorList
        .expand((c) => sizeList.map((s) => "${c['id']}_${s['id']}"))
        .toSet();

    // Remove controllers not needed
    variantStockControllers.keys.toList().forEach((key) {
      if (!keysNeeded.contains(key)) {
        variantStockControllers.remove(key)?.dispose();
      }
    });

    // Add controllers for all needed combinations
    for (var color in colorList) {
      for (var size in sizeList) {
        final key = "${color['id']}_${size['id']}";
        variantStockControllers.putIfAbsent(key, () {
          // Check if it's an existing variant
          int stock = _getInitialStock(color['id'], size['id']);
          return TextEditingController(text: stock.toString());
        });
      }
    }
  }

  List<Widget> _buildVariantStockFields() {
    List<Widget> variantFields = [];
    final List colorList = selectedColors.isNotEmpty
        ? selectedColors
        : [
            {"id": 0, "name": "N/A Color"},
          ];
    final List sizeList = selectedSizes.isNotEmpty
        ? selectedSizes
        : [
            {"id": 0, "name": "N/A Size"},
          ];

    final Set<String> currentKeys = colorList
        .expand((c) => sizeList.map((s) => "${c["id"]}_${s["id"]}"))
        .toSet();

    variantStockControllers.keys.toList().forEach((key) {
      if (!currentKeys.contains(key)) {
        variantStockControllers.remove(key)?.dispose();
      }
    });

    for (var color in colorList) {
      for (var size in sizeList) {
        final colorId = color["id"] as int;
        final sizeId = size["id"] as int;
        final key = "${colorId}_${sizeId}";

        variantStockControllers.putIfAbsent(
          key,
          () => TextEditingController(
            text: _getInitialStock(colorId, sizeId).toString(),
          ),
        );

        final label = selectedColors.isEmpty && selectedSizes.isEmpty
            ? "Stock Quantity (Total)"
            : "Stock for: ${color["name"]} / ${size["name"]}";

        variantFields.add(
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: TextFormField(
              controller: variantStockControllers[key],
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty || int.tryParse(v) == null
                  ? "Valid number required"
                  : null,
              onChanged: (v) => _recalculateTotals(),
            ),
          ),
        );
      }
    }

    return variantFields;
  }

  Future<void> fetchDropdowns() async {
    final urls = [
      "http://10.0.2.2:8000/api/categories/",
      "http://10.0.2.2:8000/api/brands/",
      "http://10.0.2.2:8000/api/colors/",
      "http://10.0.2.2:8000/api/sizes/",
      "http://10.0.2.2:8000/api/suppliers/",
      "http://10.0.2.2:8000/api/shops/",
    ];

    List<http.Response> responses = [];
    bool retryNeeded = false;

    for (var url in urls) {
      final response = await http.get(Uri.parse(url), headers: headers);
      responses.add(response);
      if (response.statusCode == 401) retryNeeded = true;
    }

    if (retryNeeded && await _refreshTokenUtility()) {
      responses.clear();
      for (var url in urls) {
        responses.add(await http.get(Uri.parse(url), headers: headers));
      }
    }

    if (mounted) {
      setState(() {
        if (responses[0].statusCode == 200)
          categories = jsonDecode(responses[0].body);
        if (responses[1].statusCode == 200)
          brands = jsonDecode(responses[1].body);
        if (responses[2].statusCode == 200)
          colors = jsonDecode(responses[2].body);
        if (responses[3].statusCode == 200)
          sizes = jsonDecode(responses[3].body);
        if (responses[4].statusCode == 200)
          suppliers = jsonDecode(responses[4].body);
        shops = jsonDecode(responses[5].body);
        // ensure shopId matches a real shop
        if (shopId != null && !shops.any((s) => s['id'] == shopId)) {
          shopId = shops.first['id']; // fallback
        }
        // map existing product variants to dropdown items
        _mapSelectedVariantsToDropdowns();

        // populate stock controllers for existing variants
        _updateVariantControllers();
      });
    }
  }

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => selectedImage = File(image.path));
  }

  Future<void> saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (categoryId == null || shopId == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select category and shop")),
        );
      return;
    }

    List<Map<String, dynamic>> variantsData = [];
    variantStockControllers.forEach((key, controller) {
      final parts = key.split('_');
      final colorId = int.tryParse(parts[0]);
      final sizeId = int.tryParse(parts[1]);
      final stock = int.tryParse(controller.text) ?? 0;
      variantsData.add({
        'color_id': colorId == 0 ? null : colorId,
        'size_id': sizeId == 0 ? null : sizeId,
        'stock_quantity': stock,
      });
    });

    Map<String, String> fields = {
      'name': nameController.text.trim(),
      'purchase_price': purchasePriceController.text,
      'sale_price': salePriceController.text,
      'paid_amount': paidAmountController.text,
      'total_amount': totalAmountController.text,
      'remaining_amount': remainingAmountController.text,
      'category_id': categoryId.toString(),
      'shop_id': shopId.toString(),
      if (brandId != null) 'brand_id': brandId.toString(),
      if (supplierId != null) 'supplier_id': supplierId.toString(),
      'variants_json': jsonEncode(variantsData),
    };

    Future<http.StreamedResponse> _makeCall() async {
      var request = http.MultipartRequest(
        'PATCH',
        Uri.parse("$apiUrl${widget.product['id']}/"),
      );
      request.headers['Authorization'] = "Bearer ${widget.accessToken}";
      request.headers['Accept'] = 'application/json';
      request.fields.addAll(fields);

      if (selectedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', selectedImage!.path),
        );
      }

      return request.send();
    }

    http.StreamedResponse response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      await response.stream.bytesToString();
      response = await _makeCall();
    }

    final respStr = await response.stream.bytesToString();

    if ([200, 201, 204].contains(response.statusCode)) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } else if (response.statusCode != 401 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save product: $respStr")),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final bool isShopLocked = shopId != null;

    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ Keeps form visible when keyboard opens
      appBar: AppBar(title: const Text("ပြင်ဆင်မည် Edit Product")),
      body: categories.isEmpty && shopId == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            key: const PageStorageKey('edit_product_form'), // ✅ Avoids rebuild issues
            children: [
              TextFormField(
                controller: nameController,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'.*')), // ✅ Allow Unicode (Myanmar)
                ],
                decoration: const InputDecoration(
                  labelText: "နာမည် (Name)",
                ),
                validator: (v) => v!.isEmpty ? "Required / လိုအပ်ပါတယ်" : null,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: purchasePriceController,
                decoration: const InputDecoration(
                  labelText: "ဝယ်ဈေး (Purchase Price)",
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: paidAmountController,
                decoration: const InputDecoration(
                  labelText: "ပေးငွေ (optional)",
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return "Enter a valid number / နံပါတ်ဖြစ်ရမည်";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: totalAmountController,
                decoration: const InputDecoration(
                  labelText: "စုစုပေါင်း (Total Amount)",
                ),
                readOnly: true,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: remainingAmountController,
                decoration: const InputDecoration(
                  labelText: "ကျန်ငွေ (Remaining Amount)",
                ),
                readOnly: true,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: salePriceController,
                decoration: const InputDecoration(
                  labelText: "ရောင်းဈေး (Sale Price)",
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),

              ..._buildVariantStockFields(),
              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: categoryId,
                items: categories
                    .map<DropdownMenuItem<int>>(
                      (c) => DropdownMenuItem<int>(
                    value: c["id"] as int,
                    child: Text(c["name"] as String),
                  ),
                )
                    .toList(),
                onChanged: (v) => setState(() => categoryId = v),
                decoration: const InputDecoration(labelText: "အမျိုးအစား (Category)"),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: brandId,
                items: brands
                    .map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem<int>(
                    value: b["id"] as int,
                    child: Text(b["name"] as String),
                  ),
                )
                    .toList(),
                onChanged: (v) => setState(() => brandId = v),
                decoration: const InputDecoration(labelText: "အမှတ်တံဆိပ် (Brand)"),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: supplierId,
                items: suppliers
                    .map<DropdownMenuItem<int>>(
                      (s) => DropdownMenuItem<int>(
                    value: s["id"] as int,
                    child: Text(s["name"] as String),
                  ),
                )
                    .toList(),
                onChanged: (v) => setState(() => supplierId = v),
                decoration: const InputDecoration(labelText: "ပေးသွင်းသူ (Supplier)"),
              ),

              const SizedBox(height: 10),

              isShopLocked && shops.isNotEmpty && shopId != null
                  ? TextFormField(
                readOnly: true,
                initialValue: shops.firstWhere(
                      (s) => s["id"] == shopId,
                  orElse: () => {"name": "Shop ID $shopId (Name not found)"},
                )["name"],
                decoration: const InputDecoration(
                  labelText: "ဆိုင် (Auto-Selected)",
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFE0E0E0),
                ),
              )
                  : DropdownButtonFormField<int>(
                value: shopId,
                items: shops.map((s) => DropdownMenuItem<int>(
                  value: s["id"] as int,
                  child: Text(s["name"] as String),
                )).toList(),
                onChanged: (v) => setState(() => shopId = v),
                decoration: const InputDecoration(labelText: "ဆိုင် (Shop)"),
              ),


              const SizedBox(height: 10),

              MultiSelectDialogField(
                items: colors.map((c) => MultiSelectItem(c, c['name'])).toList(),
                initialValue: selectedColors,
                title: const Text("အရောင်များ (Colors)"),
                buttonText: const Text("Colors"),
                onConfirm: _onColorsSelected,
              ),

              MultiSelectDialogField(
                items: sizes.map((s) => MultiSelectItem(s, s['name'])).toList(),
                initialValue: selectedSizes,
                title: const Text("အရွယ်အစားများ (Sizes)"),
                buttonText: const Text("Sizes"),
                onConfirm: _onSizesSelected,
              ),

              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: pickImage,
                child: const Text("ပုံရွေးပါ (Select Image)"),
              ),

              if (selectedImage != null)
                Image.file(
                  selectedImage!,
                  height: 100,
                  width: 100,
                  fit: BoxFit.cover,
                )
              else if (widget.product['image'] != null &&
                  widget.product['image'].isNotEmpty)
                Image.network(
                  widget.product['image'],
                  height: 100,
                  width: 100,
                  fit: BoxFit.cover,
                ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: saveProduct,
                child: const Text("သိမ်းမည် (Save Product)"),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ---------------- Add Product Screen (FIXED) ----------------
class AddProductScreen extends StatefulWidget {
  final String accessToken;
  final String refreshToken;
  final VoidCallback onSaved;

  const AddProductScreen({
    super.key,
    required this.accessToken,
    required this.refreshToken,
    required this.onSaved,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  File? selectedImage;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController purchasePriceController = TextEditingController();
  final TextEditingController salePriceController = TextEditingController();
  final TextEditingController paidAmountController = TextEditingController();
  final TextEditingController totalAmountController = TextEditingController();
  final TextEditingController remainingAmountController = TextEditingController();

  Map<String, TextEditingController> variantStockControllers = {};
  Map<String, TextEditingController> packControllers = {};
  Map<String, TextEditingController> unitsPerPackControllers = {};
  Map<String, TextEditingController> packPriceControllers = {};
  Map<String, TextEditingController> singlePriceControllers = {};

  int? categoryId;
  int? brandId;
  int? supplierId;
  int? shopId;

  List categories = [];
  List brands = [];
  List colors = [];
  List sizes = [];
  List suppliers = [];
  List shops = [];

  List selectedColors = [];
  List selectedSizes = [];
  int? _loggedInUserShopId;

  final String apiUrl = "http://10.0.2.2:8000/api/products/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  Map<String, String> get headers => {
    "Authorization": "Bearer ${widget.accessToken}",
  };

  @override
  void initState() {
    super.initState();
    purchasePriceController.addListener(_recalculateTotals);
    paidAmountController.addListener(_recalculateTotals);
    _loadUserShopIdAndFetchDropdowns();
  }

  @override
  void dispose() {
    variantStockControllers.values.forEach((c) => c.dispose());
    packControllers.values.forEach((c) => c.dispose());
    unitsPerPackControllers.values.forEach((c) => c.dispose());
    packPriceControllers.values.forEach((c) => c.dispose());
    singlePriceControllers.values.forEach((c) => c.dispose());

    nameController.dispose();
    purchasePriceController.dispose();
    salePriceController.dispose();
    paidAmountController.dispose();
    totalAmountController.dispose();
    remainingAmountController.dispose();
    super.dispose();
  }

  void _recalculateTotals() {
    int totalStock = variantStockControllers.values
        .map((c) => int.tryParse(c.text) ?? 0)
        .fold(0, (a, b) => a + b);

    double purchasePrice = double.tryParse(purchasePriceController.text) ?? 0.0;
    double paidAmount = double.tryParse(paidAmountController.text) ?? 0.0;

    double totalAmount = purchasePrice * totalStock;
    double remainingAmount = totalAmount - paidAmount;

    totalAmountController.text = totalAmount.toStringAsFixed(2);
    remainingAmountController.text = remainingAmount.toStringAsFixed(2);
  }

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

  Future<void> _loadUserShopIdAndFetchDropdowns() async {
    final prefs = await SharedPreferences.getInstance();
    _loggedInUserShopId = prefs.getInt('userShopId');
    await fetchDropdowns();

    if (_loggedInUserShopId != null && mounted) {
      final isValidShop = shops.any((shop) => shop["id"] == _loggedInUserShopId);
      if (isValidShop) {
        setState(() {
          shopId = _loggedInUserShopId;
        });
      }
    }
  }

  Future<void> fetchDropdowns() async {
    final urls = [
      "http://10.0.2.2:8000/api/categories/",
      "http://10.0.2.2:8000/api/brands/",
      "http://10.0.2.2:8000/api/colors/",
      "http://10.0.2.2:8000/api/sizes/",
      "http://10.0.2.2:8000/api/suppliers/",
      "http://10.0.2.2:8000/api/shops/",
    ];

    List<http.Response> responses = [];
    bool retryNeeded = false;

    Future<http.Response> _makeCall(String url) =>
        http.get(Uri.parse(url), headers: headers);

    for (var url in urls) {
      final response = await _makeCall(url);
      responses.add(response);
      if (response.statusCode == 401) retryNeeded = true;
    }

    if (retryNeeded && await _refreshTokenUtility()) {
      responses.clear();
      for (var url in urls) {
        responses.add(await _makeCall(url));
      }
    }

    if (mounted) {
      setState(() {
        if (responses[0].statusCode == 200) categories = jsonDecode(responses[0].body);
        if (responses[1].statusCode == 200) brands = jsonDecode(responses[1].body);
        if (responses[2].statusCode == 200) colors = jsonDecode(responses[2].body);
        if (responses[3].statusCode == 200) sizes = jsonDecode(responses[3].body);
        if (responses[4].statusCode == 200) suppliers = jsonDecode(responses[4].body);
        if (responses[5].statusCode == 200) shops = jsonDecode(responses[5].body);
      });
    }
  }

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => selectedImage = File(image.path));
  }

  List<Widget> _buildVariantStockFields() {
    List<Widget> variantFields = [];

    // Only fallback if nothing is selected
    final List colorList = selectedColors.isNotEmpty
        ? selectedColors
        : [{"id": 0, "name": "N/A Color"}];
    final List sizeList = selectedSizes.isNotEmpty
        ? selectedSizes
        : [{"id": 0, "name": "N/A Size"}];

    // Generate valid keys, skip "0_0" if real selections exist
    final Set<String> currentKeys = colorList
        .expand((c) => sizeList.map((s) => "${c["id"]}_${s["id"]}"))
        .where((key) {
      if (key == "0_0" && (selectedColors.isNotEmpty || selectedSizes.isNotEmpty)) {
        return false;
      }
      return true;
    })
        .toSet();

    // Remove obsolete controllers
    variantStockControllers.keys.toList().forEach((key) {
      if (!currentKeys.contains(key)) {
        variantStockControllers.remove(key)?.dispose();
        packControllers.remove(key)?.dispose();
        unitsPerPackControllers.remove(key)?.dispose();
        packPriceControllers.remove(key)?.dispose();
        singlePriceControllers.remove(key)?.dispose();
      }
    });

    for (var color in colorList) {
      for (var size in sizeList) {
        final colorId = color["id"] as int;
        final sizeId = size["id"] as int;

        // Skip "0_0" if real selections exist
        if (colorId == 0 && sizeId == 0 && (selectedColors.isNotEmpty || selectedSizes.isNotEmpty)) continue;

        final key = "${colorId}_${sizeId}";

        variantStockControllers.putIfAbsent(key, () => TextEditingController(text: '0'));
        packControllers.putIfAbsent(key, () => TextEditingController(text: '0'));
        unitsPerPackControllers.putIfAbsent(key, () => TextEditingController(text: '1'));
        packPriceControllers.putIfAbsent(key, () => TextEditingController(text: salePriceController.text));
        singlePriceControllers.putIfAbsent(key, () => TextEditingController(text: salePriceController.text));

        void updateTotalStock() {
          final packs = int.tryParse(packControllers[key]?.text ?? '0') ?? 0;
          final units = int.tryParse(unitsPerPackControllers[key]?.text ?? '1') ?? 1;
          final total = packs * units;
          variantStockControllers[key]!.text = total.toString();
          _recalculateTotals();
        }

        packControllers[key]!.addListener(updateTotalStock);
        unitsPerPackControllers[key]!.addListener(updateTotalStock);

        final label = selectedColors.isEmpty && selectedSizes.isEmpty
            ? "Stock Quantity (Total)"
            : "Variant: ${color["name"]} / ${size["name"]}";

        variantFields.add(
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: packControllers[key],
                        decoration: const InputDecoration(
                          labelText: "No. of Packs",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: unitsPerPackControllers[key],
                        decoration: const InputDecoration(
                          labelText: "Units per Pack",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: packPriceControllers[key],
                        decoration: const InputDecoration(
                          labelText: "Pack Price",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: singlePriceControllers[key],
                        decoration: const InputDecoration(
                          labelText: "Single Price",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: variantStockControllers[key],
                        decoration: const InputDecoration(
                          labelText: "Total Units",
                          border: OutlineInputBorder(),
                        ),
                        readOnly: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    return variantFields;
  }

  Future<void> saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (categoryId == null || shopId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select category and shop")),
        );
      }
      return;
    }

    List<Map<String, dynamic>> variantsData = [];
    int totalQuantity = 0;

    variantStockControllers.forEach((key, controller) {
      final parts = key.split('_');
      final colorId = int.tryParse(parts[0]);
      final sizeId = int.tryParse(parts[1]);

      // Skip placeholder if real selections exist
      if (colorId == 0 && sizeId == 0 && (selectedColors.isNotEmpty || selectedSizes.isNotEmpty)) return;

      final packs = int.tryParse(packControllers[key]?.text ?? '0') ?? 0;
      final unitsPerPack = int.tryParse(unitsPerPackControllers[key]?.text ?? '1') ?? 1;
      final totalStock = packs > 0 ? packs * unitsPerPack : int.tryParse(controller.text) ?? 0;

      variantsData.add({
        'color_id': colorId == 0 ? null : colorId,
        'size_id': sizeId == 0 ? null : sizeId,
        'stock_quantity': totalStock,
        'is_pack': packs > 0,
        'units_per_pack': unitsPerPack,
        'pack_sale_price': double.tryParse(packPriceControllers[key]?.text ?? '0') ?? 0.0,
        'single_sale_price': double.tryParse(singlePriceControllers[key]?.text ?? '0') ?? 0.0,
      });

      totalQuantity += totalStock;
    });


    final double salePrice = double.tryParse(salePriceController.text) ?? 0.0;
    final double purchasePrice = double.tryParse(purchasePriceController.text) ?? 0.0;
    final double paidAmount = double.tryParse(paidAmountController.text.isEmpty ? "0" : paidAmountController.text) ?? 0.0;
    final double totalAmount = purchasePrice * totalQuantity;
    final double remainingAmount = totalAmount - paidAmount;

    Map<String, String> simpleFields = {
      'name': nameController.text.trim(),
      'purchase_price': purchasePrice.toString(),
      'sale_price': salePrice.toString(),
      'total_amount': totalAmount.toString(),
      'paid_amount': paidAmount.toString(),
      'remaining_amount': remainingAmount.toString(),
      'category_id': categoryId.toString(),
      'shop_id': shopId.toString(),
      if (brandId != null) 'brand_id': brandId.toString(),
      if (supplierId != null) 'supplier_id': supplierId.toString(),
    };

    final Uri url = Uri.parse(apiUrl);
    var request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = "Bearer ${widget.accessToken}";
    request.headers['Accept'] = 'application/json';
    request.fields.addAll(simpleFields);
    request.fields['variants_json'] = jsonEncode(variantsData);

    if (selectedImage != null) {
      request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
    }

    http.StreamedResponse response = await request.send();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      await response.stream.bytesToString();
      response = await request.send();
    }

    final respStr = await response.stream.bytesToString();

    if ([200, 201, 204].contains(response.statusCode)) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } else if (response.statusCode != 401) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save product: $respStr")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isShopLocked = shopId != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text("ထပ်ထည့်မည် Add Product")),
      body: categories.isEmpty && shopId == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: ListView(
            key: const PageStorageKey('add_product_form'),
            children: [
              // Name
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "နာမည် (Name)"),
                validator: (v) => v!.isEmpty ? "Required / လိုအပ်ပါတယ်" : null,
              ),
              const SizedBox(height: 10),
              // Purchase Price
              TextFormField(
                controller: purchasePriceController,
                decoration: const InputDecoration(labelText: "ဝယ်ဈေး (Purchase Price)"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              // Paid Amount
              TextFormField(
                controller: paidAmountController,
                decoration: const InputDecoration(labelText: "ပေးငွေ (optional)"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              // Total & Remaining
              TextFormField(controller: totalAmountController, decoration: const InputDecoration(labelText: "စုစုပေါင်း (Total Amount)"), readOnly: true),
              const SizedBox(height: 10),
              TextFormField(controller: remainingAmountController, decoration: const InputDecoration(labelText: "ကျန်ငွေ (Remaining Amount)"), readOnly: true),
              const SizedBox(height: 10),
              // Sale Price
              TextFormField(controller: salePriceController, decoration: const InputDecoration(labelText: "ရောင်းဈေး (Sale Price)"), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              // Variant Fields
              ..._buildVariantStockFields(),
              const SizedBox(height: 10),
              // Dropdowns
              DropdownButtonFormField<int>(
                value: categories.isNotEmpty ? categoryId : null,
                items: categories.isNotEmpty
                    ? categories
                    .map((c) => DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['name'] as String),
                ))
                    .toList()
                    : [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text("No categories available"),
                  )
                ],
                onChanged: (v) => setState(() => categoryId = v),
                decoration: const InputDecoration(labelText: "အမျိုးအစား (Category)"),
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: brands.isNotEmpty ? brandId : null,
                items: brands.isNotEmpty
                    ? brands
                    .map((b) => DropdownMenuItem<int>(
                  value: b['id'] as int,
                  child: Text(b['name'] as String),
                ))
                    .toList()
                    : [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text("No brands available"),
                  )
                ],
                onChanged: (v) => setState(() => brandId = v),
                decoration: const InputDecoration(labelText: "အမှတ်တံဆိပ် (Brand)"),
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: suppliers.isNotEmpty ? supplierId : null,
                items: suppliers.isNotEmpty
                    ? suppliers
                    .map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(s['name'] as String),
                ))
                    .toList()
                    : [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text("No suppliers available"),
                  )
                ],
                onChanged: (v) => setState(() => supplierId = v),
                decoration: const InputDecoration(labelText: "ပေးသွင်းသူ (Supplier)"),
              ),
              const SizedBox(height: 10),

              isShopLocked
                  ? Text(
                shops.isNotEmpty
                    ? "Shop locked to ${shops.firstWhere((s) => s['id'] == shopId, orElse: () => {'name': 'Unknown'})['name']}"
                    : "Shop locked",
              )
                  : DropdownButtonFormField<int>(
                value: shops.isNotEmpty ? shopId : null,
                items: shops.isNotEmpty
                    ? shops
                    .map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(s['name'] as String),
                ))
                    .toList()
                    : [
                  const DropdownMenuItem<int>(
                    value: 0,
                    child: Text("No shops available"),
                  )
                ],
                onChanged: (v) => setState(() => shopId = v),
                decoration: const InputDecoration(labelText: "Shop"),
              ),

              const SizedBox(height: 10),
              // MultiSelect Colors
              MultiSelectDialogField(
                items: colors.map((c) => MultiSelectItem(c, c['name'])).toList(),
                title: const Text("Colors"),
                selectedColor: Colors.blue,
                buttonText: const Text("Select Colors"),
                onConfirm: (values) => setState(() => selectedColors = values),
              ),
              const SizedBox(height: 10),
              // MultiSelect Sizes
              MultiSelectDialogField(
                items: sizes.map((s) => MultiSelectItem(s, s['name'])).toList(),
                title: const Text("Sizes"),
                selectedColor: Colors.blue,
                buttonText: const Text("Select Sizes"),
                onConfirm: (values) => setState(() => selectedSizes = values),
              ),
              const SizedBox(height: 10),
              // Image picker
              selectedImage != null
                  ? Image.file(selectedImage!, height: 150)
                  : Container(height: 150, color: Colors.grey[200], child: const Center(child: Text("No Image"))),
              TextButton.icon(
                icon: const Icon(Icons.image),
                label: const Text("Pick Image"),
                onPressed: pickImage,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: saveProduct,
                child: const Text("Add Product"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

