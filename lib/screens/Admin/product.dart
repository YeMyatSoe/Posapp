import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Assuming you have this path correctly set up for the rest of your files
import '../../widgets/admin/sidebar.dart';

// ---------------- Product Model Classes (For Display) ----------------

// (Retained your Product model classes as they are generally fine for data parsing)
class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String category;
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.variants = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    List<ProductVariant> parseVariants(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((v) => ProductVariant.fromJson(v)).toList();
      }
      return [];
    }

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: parseDouble(json['sale_price']),
      imageUrl: json['image'] ?? 'https://picsum.photos/200/300',
      category: json['category']?['name'] ?? 'Uncategorized',
      variants: parseVariants(json['variants']),
    );
  }
}

class ProductVariant {
  final String? id;
  final String? colorName;
  final String? sizeName;
  final int stockQuantity;

  ProductVariant({
    this.id,
    this.colorName,
    this.sizeName,
    this.stockQuantity = 0,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id']?.toString(),
      colorName: json['color']?['name'] ?? json['color_name'],
      sizeName: json['size']?['name'] ?? json['size_name'],
      stockQuantity: json['stock_quantity'] ?? 0,
    );
  }
}

// ---------------- Product Listing Screen (FIXED) ----------------

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final String apiUrl = "http://10.0.2.2:8000/api/products/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  String accessToken = ''; // Renamed for clarity
  String refreshToken = ''; // Added to hold the Refresh Token
  List products = [];
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

  // FETCH PRODUCTS (Updated with Refresh Logic)
  Future<void> fetchProducts() async {
    setState(() => isLoading = true);
    Future<http.Response> _makeCall() => http.get(Uri.parse(apiUrl), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 200) {
      setState(() {
        products = jsonDecode(response.body);
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load products: ${response.statusCode}")),
        );
      }
    }
  }

  // DELETE PRODUCT (Updated with Refresh Logic)
  Future<void> deleteProduct(int id) async {
    Future<http.Response> _makeCall() => http.delete(Uri.parse("$apiUrl$id/"), headers: headers);

    http.Response response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    if (response.statusCode == 204) {
      fetchProducts();
    } else {
      if (response.statusCode != 401 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete product: ${response.body}")),
        );
      }
    }
  }

  void goToEditScreen(Map product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProductScreen(
          product: product,
          accessToken: accessToken, // Pass access token
          refreshToken: refreshToken, // Pass refresh token
          onSaved: fetchProducts,
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Product Management")),
      drawer: const SideBar(selectedPage: 'Product'), // Uncomment if SideBar is available
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 50,
          dataRowHeight: 70, // fixed row height
          columns: List.generate(8, (index) {
            const columnNames = [
              "ID",
              "Name",
              "Category",
              "Shop",
              "Variants",
              "Purchase Price",
              "Sale Price",
              "Actions"
            ];
            return DataColumn(
              label: SizedBox(
                width: 100,
                child: Text(
                  columnNames[index],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }),
          rows: products.map((product) {
            final List variants = product["variants"] ?? [];
            final int totalStock = variants.fold(0, (sum, v) => sum + ((v["stock_quantity"] ?? 0) as int));
            final String variantSummary = variants.isEmpty
                ? "N/A"
                : "${variants.length} types, Stock: $totalStock";
            final purchasePrice = product["purchase_price"] ?? 0;

            return DataRow(cells: [
              DataCell(SizedBox(
                width: 100,
                child: Text(product["id"].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(product["name"] ?? "-", maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(product["category"]?["name"] ?? "-", maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(product["shop"]?["name"] ?? "-", maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(variantSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(purchasePrice.toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(SizedBox(
                width: 100,
                child: Text(product["sale_price"].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
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
                        onTap: () => goToEditScreen(product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Row(
                            children: const [
                              Icon(Icons.edit, size: 16, color: Colors.white),
                              SizedBox(width: 2),
                              Text("Edit", style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        )
                      ),
                      // Divider
                      Container(width: 1, color: Colors.white.withOpacity(0.5), height: 20),
                      // Dropdown for delete
                      PopupMenuButton(
                        color: Colors.red[300],
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            height: 10,
                            value: 'delete',
                            child: Row(
                              children: const [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 2),
                                Text("Delete"),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'delete') deleteProduct(product["id"]);
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
        floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (accessToken.isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddProductScreen(
                  accessToken: accessToken,
                  refreshToken: refreshToken,
                  onSaved: fetchProducts),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------- Edit Product Screen (FIXED) ----------------

class EditProductScreen extends StatefulWidget {
  final Map product;
  final String accessToken; // Renamed prop
  final String refreshToken; // Added prop
  final VoidCallback onSaved;

  const EditProductScreen(
      {super.key, required this.product, required this.accessToken, required this.refreshToken, required this.onSaved});

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

  Map<String, TextEditingController> variantStockControllers = {};

  final String apiUrl = "http://10.0.2.2:8000/api/products/";
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

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
  List initialVariants = [];

  Map<String, String> get headers => {
    "Authorization": "Bearer ${widget.accessToken}",
  };

  @override
  void initState() {
    super.initState();
    nameController.text = widget.product["name"] ?? "";
    purchasePriceController.text = widget.product["purchase_price"].toString();
    salePriceController.text = widget.product["sale_price"].toString();

    categoryId = widget.product["category"]?["id"];
    brandId = widget.product["brand"]?["id"];
    supplierId = widget.product["supplier"]?["id"];
    shopId = widget.product["shop"]?["id"];

    // FIX: Ensure initial values for MultiSelect are correctly typed Lists of Maps
    selectedColors = (widget.product["colors"] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    selectedSizes = (widget.product["sizes"] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];

    initialVariants = widget.product["variants"] ?? [];

    // FIX: Add check for tokens before fetching dropdowns
    if (widget.accessToken.isEmpty || widget.refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    fetchDropdowns();
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


// Helper to find initial stock for an edit product variant (Retained the fix)
  int _getInitialStock(int colorId, int sizeId) {
    if (initialVariants.isEmpty) return 0;

    final variant = initialVariants.firstWhere(
          (v) {
        final vColor = v['color'];
        int? vColorId;
        if (vColor is Map) {
          vColorId = vColor['id'] as int?;
        } else if (vColor is int) {
          vColorId = vColor;
        }

        final vSize = v['size'];
        int? vSizeId;
        if (vSize is Map) {
          vSizeId = vSize['id'] as int?;
        } else if (vSize is int) {
          vSizeId = vSize;
        }

        final colorMatch = (colorId == 0 && vColorId == null) ||
            (colorId > 0 && vColorId == colorId);

        final sizeMatch = (sizeId == 0 && vSizeId == null) ||
            (sizeId > 0 && vSizeId == sizeId);

        return colorMatch && sizeMatch;
      },
      orElse: () => null,
    );

    return variant?['stock_quantity'] ?? 0;
  }

  // Build Dynamic Variant Stock Fields (Retained your dynamic logic)
  List<Widget> _buildVariantStockFields() {
    List<Widget> variantFields = [];

    final List colorList = selectedColors.isNotEmpty ? selectedColors : [{"id": 0, "name": "N/A Color"}];
    final List sizeList = selectedSizes.isNotEmpty ? selectedSizes : [{"id": 0, "name": "N/A Size"}];

    // Clear controllers if selections changed to prevent memory leak
    final Set<String> currentKeys = colorList.expand((c) => sizeList.map((s) => "${c["id"]}_${s["id"]}")).toSet();
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

        if (!variantStockControllers.containsKey(key)) {
          final initialStock = _getInitialStock(colorId, sizeId);
          variantStockControllers[key] = TextEditingController(text: initialStock.toString());
        }

        final label = selectedColors.isEmpty && selectedSizes.isEmpty
            ? "Stock Quantity (Total)"
            : "Stock for: ${color["name"]} / ${size["name"]}";

        variantFields.add(Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: TextFormField(
            controller: variantStockControllers[key],
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty || int.tryParse(v) == null ? "Valid number required" : null,
          ),
        ));
      }
    }
    return variantFields;
  }

  // FETCH DROPDOWNS (Updated with Refresh Logic)
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

    // Initial fetch attempt
    for (var url in urls) {
      final response = await http.get(Uri.parse(url), headers: headers);
      responses.add(response);
      if (response.statusCode == 401) retryNeeded = true;
    }

    // Refresh and retry if 401 was encountered
    if (retryNeeded && await _refreshTokenUtility()) {
      responses.clear();
      for (var url in urls) {
        responses.add(await http.get(Uri.parse(url), headers: headers));
      }
    }

    if (mounted) {
      setState(() {
        if (responses.isNotEmpty && responses[0].statusCode == 200) categories = jsonDecode(responses[0].body);
        if (responses.isNotEmpty && responses[1].statusCode == 200) brands = jsonDecode(responses[1].body);
        if (responses.isNotEmpty && responses[2].statusCode == 200) colors = jsonDecode(responses[2].body);
        if (responses.isNotEmpty && responses[3].statusCode == 200) sizes = jsonDecode(responses[3].body);
        if (responses.isNotEmpty && responses[4].statusCode == 200) suppliers = jsonDecode(responses[4].body);
        if (responses.isNotEmpty && responses[5].statusCode == 200) shops = jsonDecode(responses[5].body);
      });
    }
  }

  // SAVE PRODUCT (Updated with Refresh and Multipart Logic)
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

    // 1️⃣ Construct variants list
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

    // 2️⃣ Parse numeric fields properly
    final purchasePrice = purchasePriceController.text.replaceAll(',', '');
    final salePrice = salePriceController.text.replaceAll(',', '');
    final paidAmount = paidAmountController.text.isEmpty ? '0' : paidAmountController.text.replaceAll(',', '');

    Map<String, String> simpleFields = {
      'name': nameController.text.trim(),
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'category_id': categoryId.toString(),
      'shop_id': shopId.toString(),
      'paid_amount': paidAmount,
      if (brandId != null) 'brand_id': brandId.toString(),
      if (supplierId != null) 'supplier_id': supplierId.toString(),
    };

    final url = Uri.parse("$apiUrl${widget.product['id']}/"); // PATCH

    // 3️⃣ Function to perform API call
    Future<http.StreamedResponse> _makeCall() async {
      var request = http.MultipartRequest('PATCH', url);
      request.headers['Authorization'] = "Bearer ${widget.accessToken}";
      request.headers['Accept'] = 'application/json';

      // Add fields
      simpleFields.forEach((key, value) => request.fields[key] = value);

      // Add variants JSON
      request.fields['variants_json'] = jsonEncode(variantsData);

      // Add image if selected
      if (selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
      }

      return request.send();
    }

    // 4️⃣ Perform request with token refresh
    http.StreamedResponse response = await _makeCall();

    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      await response.stream.bytesToString(); // clear stream
      response = await _makeCall();
    }

    // 5️⃣ Parse response
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

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => selectedImage = File(image.path));
  }

  // Cleanup controllers
  @override
  void dispose() {
    variantStockControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isShopLocked = shopId != null;
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Product")),
      body: categories.isEmpty && shopId == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
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
                controller: purchasePriceController,
                decoration: const InputDecoration(labelText: "Purchase Price"),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: salePriceController,
                decoration: const InputDecoration(labelText: "Sale Price"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),

              // INSERT DYNAMIC STOCK FIELDS HERE
              ..._buildVariantStockFields(),
              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: categoryId,
                items: categories
                    .map<DropdownMenuItem<int>>(
                        (c) => DropdownMenuItem(value: c["id"], child: Text(c["name"])))
                    .toList(),
                onChanged: (v) => setState(() => categoryId = v),
                decoration: const InputDecoration(labelText: "Category"),
              ),
              DropdownButtonFormField<int>(
                value: brandId,
                items: brands
                    .map<DropdownMenuItem<int>>(
                        (b) => DropdownMenuItem(value: b["id"], child: Text(b["name"])))
                    .toList(),
                onChanged: (v) => setState(() => brandId = v),
                decoration: const InputDecoration(labelText: "Brand"),
              ),
              DropdownButtonFormField<int>(
                value: supplierId,
                items: suppliers
                    .map<DropdownMenuItem<int>>(
                        (s) => DropdownMenuItem(value: s["id"], child: Text(s["name"])))
                    .toList(),
                onChanged: (v) => setState(() => supplierId = v),
                decoration: const InputDecoration(labelText: "Supplier"),
              ),
              DropdownButtonFormField<int>(
                value: shopId,
                items: shops
                    .map<DropdownMenuItem<int>>(
                        (s) => DropdownMenuItem(value: s["id"], child: Text(s["name"])))
                    .toList(),
                onChanged: (v) => setState(() => shopId = v),
                decoration: InputDecoration(
                  labelText: "Shop",
                  filled: isShopLocked,
                  fillColor: isShopLocked ? Colors.grey.shade200 : null,
                ),
                validator: (value) => value == null ? "Shop must be selected" : null,
              ),
              const SizedBox(height: 10),
              MultiSelectDialogField(
                items: colors.map((c) => MultiSelectItem(c, c["name"])).toList(),
                title: const Text("Select Colors"),
                buttonText: const Text("Colors"),
                // Initial value must contain the Maps, not just the IDs
                initialValue: selectedColors,
                onConfirm: (values) => setState(() {
                  selectedColors = values;
                  // Clear controllers to regenerate them for the new combination
                  variantStockControllers.clear();
                }),
              ),
              MultiSelectDialogField(
                items: sizes.map((s) => MultiSelectItem(s, s["name"])).toList(),
                title: const Text("Select Sizes"),
                buttonText: const Text("Sizes"),
                initialValue: selectedSizes,
                onConfirm: (values) => setState(() {
                  selectedSizes = values;
                  variantStockControllers.clear();
                }),
              ),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: pickImage, child: const Text("Select Image")),
              if (selectedImage != null)
                Image.file(selectedImage!, height: 100, width: 100, fit: BoxFit.cover)
              else if (widget.product['image'] != null && widget.product['image'].isNotEmpty)
                Image.network(widget.product['image'], height: 100, width: 100, fit: BoxFit.cover),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveProduct, child: const Text("Save Product")),
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

    Future<http.Response> _makeCall(String url) => http.get(Uri.parse(url), headers: headers);

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
    final List colorList = selectedColors.isNotEmpty ? selectedColors : [{"id": 0, "name": "N/A Color"}];
    final List sizeList = selectedSizes.isNotEmpty ? selectedSizes : [{"id": 0, "name": "N/A Size"}];

    final Set<String> currentKeys = colorList.expand((c) => sizeList.map((s) => "${c["id"]}_${s["id"]}")).toSet();

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

        variantStockControllers.putIfAbsent(key, () => TextEditingController(text: '0'));

        final label = selectedColors.isEmpty && selectedSizes.isEmpty
            ? "Stock Quantity (Total)"
            : "Stock for: ${color["name"]} / ${size["name"]}";

        variantFields.add(Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: TextFormField(
            controller: variantStockControllers[key],
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (v) => v!.isEmpty || int.tryParse(v) == null ? "Valid number required" : null,
            onChanged: (v) => _recalculateTotals(),
          ),
        ));
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
      final stock = int.tryParse(controller.text) ?? 0;
      totalQuantity += stock;
      variantsData.add({
        'color_id': colorId == 0 ? null : colorId,
        'size_id': sizeId == 0 ? null : sizeId,
        'stock_quantity': stock,
      });
    });

    final double salePrice = double.tryParse(salePriceController.text) ?? 0.0;
    final double purchasePrice = double.tryParse(purchasePriceController.text) ?? 0.0;
    final double paidAmount = double.tryParse(paidAmountController.text.isEmpty ? "0" : paidAmountController.text) ?? 0.0;

    final double totalAmount = salePrice * totalQuantity;
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

    Future<http.StreamedResponse> _makeCall() async {
      var request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = "Bearer ${widget.accessToken}";
      request.headers['Accept'] = 'application/json';

      request.fields.addAll(simpleFields);
      request.fields['variants_json'] = jsonEncode(variantsData);

      if (selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));
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
      appBar: AppBar(title: const Text("Add Product")),
      body: categories.isEmpty && shopId == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
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
              TextFormField(
                controller: purchasePriceController,
                decoration: const InputDecoration(labelText: "Purchase Price"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: paidAmountController,
                decoration: const InputDecoration(labelText: "Paid Amount (optional)"),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                    return "Enter a valid number";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: totalAmountController,
                decoration: const InputDecoration(
                  labelText: "Total Amount",
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: remainingAmountController,
                decoration: const InputDecoration(
                  labelText: "Remaining Amount",
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: salePriceController,
                decoration: const InputDecoration(labelText: "Sale Price"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              ..._buildVariantStockFields(),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: categoryId,
                items: categories.map<DropdownMenuItem<int>>(
                      (c) => DropdownMenuItem<int>(
                    value: c["id"] as int, // ensure it's int
                    child: Text(c["name"] as String),
                  ),
                ).toList(),
                onChanged: (v) => setState(() => categoryId = v),
                decoration: const InputDecoration(labelText: "Category"),
              ),

              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: brandId,
                items: brands.map<DropdownMenuItem<int>>(
                      (b) => DropdownMenuItem<int>(
                    value: b["id"] as int,
                    child: Text(b["name"] as String),
                  ),
                ).toList(),
                onChanged: (v) => setState(() => brandId = v),
                decoration: const InputDecoration(labelText: "Brand"),
              ),

              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: supplierId,
                items: suppliers.map<DropdownMenuItem<int>>(
                      (s) => DropdownMenuItem<int>(
                    value: s["id"] as int,
                    child: Text(s["name"] as String),
                  ),
                ).toList(),
                onChanged: (v) => setState(() => supplierId = v),
                decoration: const InputDecoration(labelText: "Supplier"),
              ),

              const SizedBox(height: 10),
              isShopLocked && shops.isNotEmpty
                  ? TextFormField(
                readOnly: true,
                initialValue: shops.firstWhere(
                        (s) => s["id"] == shopId,
                    orElse: () => {"name": "Shop ID $shopId (Name not found)"})["name"],
                decoration: const InputDecoration(
                  labelText: "Shop (Auto-Selected)",
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFE0E0E0),
                ),
              )
                  : DropdownButtonFormField<int>(
                value: shopId,
                items: shops.map<DropdownMenuItem<int>>(
                      (s) => DropdownMenuItem<int>(
                    value: s["id"] as int,
                    child: Text(s["name"] as String),
                  ),
                ).toList(),
                onChanged: (v) => setState(() => shopId = v),
                decoration: const InputDecoration(labelText: "Shop"),
              ),

              const SizedBox(height: 10),
              MultiSelectDialogField(
                items: colors.map((c) => MultiSelectItem(c, c["name"])).toList(),
                title: const Text("Select Colors"),
                buttonText: const Text("Colors"),
                onConfirm: (values) => setState(() {
                  selectedColors = values;
                }),
              ),
              const SizedBox(height: 10),
              MultiSelectDialogField(
                items: sizes.map((s) => MultiSelectItem(s, s["name"])).toList(),
                title: const Text("Select Sizes"),
                buttonText: const Text("Sizes"),
                onConfirm: (values) => setState(() {
                  selectedSizes = values;
                }),
              ),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: pickImage, child: const Text("Select Image")),
              if (selectedImage != null)
                Image.file(selectedImage!, height: 100, width: 100, fit: BoxFit.cover),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: saveProduct, child: const Text("Add Product")),
            ],
          ),
        ),
      ),
    );
  }
}
