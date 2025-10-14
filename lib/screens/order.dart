// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
//
// class CheckoutScreen extends StatefulWidget {
//   final String token;
//   final int shopId;
//   final List<Map<String, dynamic>> cartItems; // product + color + size + quantity
//
//   const CheckoutScreen({
//     super.key,
//     required this.token,
//     required this.shopId,
//     required this.cartItems,
//   });
//
//   @override
//   State<CheckoutScreen> createState() => _CheckoutScreenState();
// }
//
// class _CheckoutScreenState extends State<CheckoutScreen> {
//   bool isLoading = false;
//
//   Future<void> placeOrder() async {
//     setState(() => isLoading = true);
//
//     final url = Uri.parse("http://10.0.2.2:8000/api/orders/");
//     final headers = {
//       "Content-Type": "application/json",
//       "Authorization": "Token ${widget.token}",
//     };
//
//     final items = widget.cartItems.map((item) {
//       return {
//         "product": item["id"],
//         if (item["color"] != null) "color": item["color"]["id"],
//         if (item["size"] != null) "size": item["size"]["id"],
//         "quantity": item["quantity"],
//       };
//     }).toList();
//
//     final body = jsonEncode({
//       "shop": widget.shopId,
//       "user": null, // optional, backend can use request.user
//       "items": items,
//     });
//
//     final response = await http.post(url, headers: headers, body: body);
//
//     setState(() => isLoading = false);
//
//     if (response.statusCode == 201 || response.statusCode == 200) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text("Order placed successfully!")),
//       );
//       Navigator.pop(context); // go back to previous screen
//     } else {
//       final error = response.body;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text("Failed to place order: $error")),
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Checkout")),
//       body: isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : Padding(
//         padding: const EdgeInsets.all(12.0),
//         child: Column(
//           children: [
//             Expanded(
//               child: ListView.builder(
//                 itemCount: widget.cartItems.length,
//                 itemBuilder: (context, index) {
//                   final item = widget.cartItems[index];
//                   return ListTile(
//                     title: Text(item["name"]),
//                     subtitle: Text(
//                         "Qty: ${item["quantity"]}  Color: ${item["color"]?["name"] ?? "-"}  Size: ${item["size"]?["name"] ?? "-"}"),
//                     trailing: Text("\$${item["sale_price"]}"),
//                   );
//                 },
//               ),
//             ),
//             ElevatedButton(
//               onPressed: placeOrder,
//               child: const Text("Place Order"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
