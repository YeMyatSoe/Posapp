import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/admin/sidebar.dart'; // Ensure this path is correct

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final String ordersApiUrl = 'http://10.0.2.2:8000/api/orders/';
  final String refreshUrl = "http://10.0.2.2:8000/api/token/refresh/";

  List<dynamic> orders = [];
  bool loading = true;
  String? errorMessage;
  String accessToken = ''; // Renamed for clarity
  String refreshToken = ''; // Added to hold the Refresh Token

  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $accessToken", // Use accessToken
  };

  @override
  void initState() {
    super.initState();
    _loadTokensAndFetchOrders(); // Renamed method
  }

  Future<void> _loadTokensAndFetchOrders() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('accessToken') ?? '';
    refreshToken = prefs.getString('refreshToken') ?? ''; // Load Refresh Token

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      // Navigate to login if tokens not found
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    await _fetchOrders();
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
      // Refresh failed (Refresh Token expired). Force re-login.
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

  // FETCH ORDERS (Updated with Refresh Logic)
  Future<void> _fetchOrders() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    Future<http.Response> _makeCall() => http.get(Uri.parse(ordersApiUrl), headers: headers);

    http.Response response = await _makeCall();

    // Check for 401 and attempt refresh
    if (response.statusCode == 401 && await _refreshTokenUtility()) {
      response = await _makeCall(); // Retry call with new Access Token
    }

    // Process final response
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        orders = data;
        loading = false;
      });
    } else {
      // Handle failure after possible retry/redirect
      if (response.statusCode != 401) {
        setState(() {
          errorMessage = 'Failed to fetch orders: ${response.statusCode}';
          loading = false;
        });
      } else {
        // If we land here, the refresh failed and the user was redirected by _refreshTokenUtility
        setState(() => loading = false);
      }
    }
  }

  Widget _buildOrderTable(Map<String, dynamic> order) {
    final items = order['items'] as List<dynamic>? ?? [];

    return DataTable(
      columns: const [
        DataColumn(label: Text('Product')),
        DataColumn(label: Text('Qty')),
        DataColumn(label: Text('Color')),
        DataColumn(label: Text('Size')),
        DataColumn(label: Text('Price')),
        DataColumn(label: Text('Total')),
      ],
      rows: items.map((item) {
        final price = double.tryParse(item['price'].toString()) ?? 0.0;
        final quantity = item['quantity'] ?? 0;
        final total = price * quantity;

        final displayColor = (item['color_name'] == null || item['color_name'] == 'N/A')
            ? '-'
            : item['color_name'];
        final displaySize = (item['size_name'] == null || item['size_name'] == 'N/A')
            ? '-'
            : item['size_name'];

        return DataRow(cells: [
          DataCell(Text(item['product_name'] ?? 'Unknown')),
          DataCell(Text(quantity.toString())),
          DataCell(Text(displayColor)),
          DataCell(Text(displaySize)),
          DataCell(Text('\$${price.toStringAsFixed(2)}')),
          DataCell(Text('\$${total.toStringAsFixed(2)}')),
        ]);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(errorMessage!),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _fetchOrders,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (orders.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Orders')),
        body: const Center(child: Text('No orders found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
       drawer: const SideBar(selectedPage: 'Dashboard'), // Uncomment if SideBar is available
      body: RefreshIndicator(
        onRefresh: _fetchOrders,
        child: ListView.builder(
          itemCount: orders.length,
          itemBuilder: (ctx, index) {
            final order = orders[index];
            final totalPrice = double.tryParse(order['total_price'].toString()) ?? 0.0;
            final status = order['status'] ?? '-';
            final createdAt = order['created_at'] ?? '-';

            return Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order['id']}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Status: $status | Date: $createdAt'),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildOrderTable(order),
                    ),
                    const SizedBox(height: 8),
                    Text('Total Price: \$${totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}