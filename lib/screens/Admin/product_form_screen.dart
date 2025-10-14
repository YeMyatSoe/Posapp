// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import '../../widgets/admin/sidebar.dart';
//
// class Product {
//   String id;
//   String name;
//   String category;
//   double price;
//   int stock;
//   bool isActive;
//   String imageUrl;
//   String description;
//   String supplier;
//
//   Product({
//     required this.id,
//     required this.name,
//     required this.category,
//     required this.price,
//     required this.stock,
//     required this.isActive,
//     required this.imageUrl,
//     required this.description,
//     required this.supplier,
//   });
//
//   factory Product.fromJson(Map<String, dynamic> json) {
//     return Product(
//       id: json['id'].toString(),
//       name: json['name'] ?? '',
//       category: json['category']?['name'] ?? '',
//       price: double.tryParse(json['sale_price'].toString()) ?? 0,
//       stock: json['stock_quantity'] ?? 0,
//       isActive: json['is_active'] ?? true,
//       imageUrl: json['image'] ?? '',
//       description: json['description'] ?? '',
//       supplier: json['supplier']?['name'] ?? '',
//     );
//   }
//
//   Map<String, dynamic> toJson() => {
//     'name': name,
//     'category': category,
//     'sale_price': price,
//     'stock_quantity': stock,
//     'is_active': isActive,
//     'image': imageUrl,
//     'description': description,
//     'supplier': supplier,
//   };
// }
//
// class ProductTableScreen extends StatefulWidget {
//   final Product? product;
//   final Function(Product)? onSave;
//
//   const ProductTableScreen({super.key, this.product, this.onSave});
//
//   @override
//   State<ProductTableScreen> createState() => _ProductTableScreenState();
// }
//
// class _ProductTableScreenState extends State<ProductTableScreen> {
//   List<Product> products = [];
//   bool isLoading = true;
//
//   // Temporary fields for new product
//   late String newName;
//   late String newCategory;
//   late double newPrice;
//   late int newStock;
//   late bool newIsActive;
//   late String newImageUrl;
//   late String newDescription;
//   late String newSupplier;
//
//   final String baseUrl = 'http://10.0.2.2:8000/api';
//
//   @override
//   void initState() {
//     super.initState();
//     newName = widget.product?.name ?? '';
//     newCategory = widget.product?.category ?? '';
//     newPrice = widget.product?.price ?? 0;
//     newStock = widget.product?.stock ?? 0;
//     newIsActive = widget.product?.isActive ?? true;
//     newImageUrl = widget.product?.imageUrl ?? '';
//     newDescription = widget.product?.description ?? '';
//     newSupplier = widget.product?.supplier ?? '';
//     _fetchProducts();
//   }
//
//   Future<void> _fetchProducts() async {
//     try {
//       final response = await http.get(Uri.parse('$baseUrl/products/'));
//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body) as List<dynamic>;
//         setState(() {
//           products = data.map((e) => Product.fromJson(e)).toList();
//           isLoading = false;
//         });
//       }
//     } catch (e) {
//       debugPrint('Error fetching products: $e');
//     }
//   }
//
//   Future<void> _saveProduct() async {
//     final productToSave = Product(
//       id: widget.product?.id ?? '',
//       name: newName,
//       category: newCategory, // should be an int ID
//       price: newPrice,
//       stock: newStock,
//       isActive: newIsActive,
//       imageUrl: newImageUrl,
//       description: newDescription,
//       supplier: newSupplier, // should be an int ID or null
//     );
//
//     // Build JSON matching DRF serializer
//     final productJson = {
//       'name': productToSave.name,
//       'category': productToSave.category, // send ID
//       'supplier': productToSave.supplier, // send ID or null
//       'sale_price': productToSave.price,
//       'stock_quantity': productToSave.stock,
//       'is_active': productToSave.isActive,
//       'image': productToSave.imageUrl,
//       'description': productToSave.description,
//       // add optional fields if needed: brand, color, size
//     };
//
//     if (widget.product == null) {
//       // Add new product
//       final response = await http.post(
//         Uri.parse('$baseUrl/products/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode(productJson),
//       );
//       if (response.statusCode == 201) {
//         widget.onSave?.call(Product.fromJson(jsonDecode(response.body)));
//       }
//     } else {
//       // Update existing product
//       final response = await http.put(
//         Uri.parse('$baseUrl/products/${productToSave.id}/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode(productJson),
//       );
//       if (response.statusCode == 200) {
//         widget.onSave?.call(Product.fromJson(jsonDecode(response.body)));
//       }
//     }
//
//     Navigator.pop(context);
//   }
//
//
//   Widget _buildStatusBadge(bool isActive) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: BoxDecoration(
//         color: isActive ? Colors.green.shade100 : Colors.red.shade100,
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Text(
//         isActive ? 'Active' : 'Inactive',
//         style: TextStyle(
//           color: isActive ? Colors.green.shade800 : Colors.red.shade800,
//           fontWeight: FontWeight.bold,
//         ),
//       ),
//     );
//   }
//
//   Widget _buildImage(String url) {
//     return url.isNotEmpty
//         ? Image.network(url, width: 50, height: 50, fit: BoxFit.cover)
//         : const SizedBox(width: 50, height: 50);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text(widget.product == null ? 'Add Product' : 'Edit Product')),
//       drawer: const SideBar(selectedPage: 'Products'),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: SingleChildScrollView(
//           scrollDirection: Axis.horizontal,
//           child: DataTable(
//             columnSpacing: 16,
//             headingRowColor: MaterialStateColor.resolveWith(
//                     (states) => Colors.blueGrey.shade100),
//             columns: const [
//               DataColumn(label: Text('ID')),
//               DataColumn(label: Text('Image')),
//               DataColumn(label: Text('Name')),
//               DataColumn(label: Text('Category')),
//               DataColumn(label: Text('Price')),
//               DataColumn(label: Text('Stock')),
//               DataColumn(label: Text('Status')),
//               DataColumn(label: Text('Supplier')),
//               DataColumn(label: Text('Actions')),
//             ],
//             rows: [
//               // Single editable row for this product
//               DataRow(cells: [
//                 DataCell(Text(widget.product?.id ?? '-')),
//                 DataCell(TextFormField(
//                   initialValue: newImageUrl,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newImageUrl = val,
//                 )),
//                 DataCell(TextFormField(
//                   initialValue: newName,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newName = val,
//                 )),
//                 DataCell(TextFormField(
//                   initialValue: newCategory,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newCategory = val,
//                 )),
//                 DataCell(TextFormField(
//                   initialValue: newPrice.toString(),
//                   keyboardType: TextInputType.number,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newPrice = double.tryParse(val) ?? 0,
//                 )),
//                 DataCell(TextFormField(
//                   initialValue: newStock.toString(),
//                   keyboardType: TextInputType.number,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newStock = int.tryParse(val) ?? 0,
//                 )),
//                 DataCell(DropdownButton<String>(
//                   value: newIsActive ? 'Active' : 'Inactive',
//                   items: const [
//                     DropdownMenuItem(value: 'Active', child: Text('Active')),
//                     DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
//                   ],
//                   onChanged: (val) {
//                     setState(() {
//                       newIsActive = val == 'Active';
//                     });
//                   },
//                 )),
//                 DataCell(TextFormField(
//                   initialValue: newSupplier,
//                   decoration: const InputDecoration(border: InputBorder.none),
//                   onChanged: (val) => newSupplier = val,
//                 )),
//                 DataCell(
//                   IconButton(
//                     icon: const Icon(Icons.save, color: Colors.blue),
//                     onPressed: _saveProduct,
//                   ),
//                 ),
//               ]),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
