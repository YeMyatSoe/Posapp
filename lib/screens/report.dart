import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// Assuming the following are imported/defined elsewhere
// import 'package:intl/intl.dart';
// import 'package:your_app/utils/refresh_token_utility.dart'; // RefreshTokenUtility type
// const String _API_BASE_URL = 'http://10.0.2.2:8000';

// Define the required types/constants as placeholders if they don't exist
typedef RefreshTokenUtility = Future<bool> Function();
const String _API_BASE_URL = 'http://10.0.2.2:8000';

class ReportScreen extends StatefulWidget {
  // FIX 1: Add JWT and refresh utility properties
  final String token;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback handleUnauthorized;

  const ReportScreen({
    super.key,
    required this.token,
    required this.refreshTokenUtility,
    required this.handleUnauthorized,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // FIX 2: Replace static data with a mutable list
  List<Map<String, dynamic>> reportData = [];

  String selectedReport = 'Item';
  String selectedDate = 'All';
  String selectedProduct = 'All';
  int topN = 5;
  bool isLoading = true; // FIX 3: Loading state for API fetch
  late String _currentAccessToken; // FIX 4: Mutable token state

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token;
    _fetchReports(); // FIX 5: Start fetching data immediately
  }

  // --- API Call Helper (for token refresh/retry) ---
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  Future<http.Response> _makeApiCall(String method, String url, {int retryCount = 0}) async {
    final uri = Uri.parse(url);
    http.Response response;

    try {
      final currentHeaders = headers;
      response = await http.get(uri, headers: currentHeaders);
    } catch (e) {
      rethrow;
    }

    if (response.statusCode == 401 && retryCount == 0) {
      final success = await widget.refreshTokenUtility();

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        return _makeApiCall(method, url, retryCount: 1); // Retry
      }
    }
    return response;
  }

  // --- New Data Fetching Logic ---
  Future<void> _fetchReports() async {
    if (_currentAccessToken.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    setState(() {
      isLoading = true;
      // Reset filters when fetching new data
      selectedDate = 'All';
      selectedProduct = 'All';
    });

    try {
      // NOTE: Replace with your actual report API endpoint
      final url = '$_API_BASE_URL/reports/sales_data/';
      final res = await _makeApiCall('GET', url);

      if (res.statusCode == 401) {
        widget.handleUnauthorized(); // Redirect to login if refresh fails
        return;
      }
      if (res.statusCode != 200) {
        throw Exception('Failed to fetch reports: ${res.statusCode}');
      }

      final data = json.decode(res.body);
      // Assuming API returns a list of maps, e.g., [{'date': '...', 'product': '...', ...}]
      final List<Map<String, dynamic>> fetchedData = List<Map<String, dynamic>>.from(data['sales'] ?? []);

      if (mounted) {
        setState(() {
          reportData = fetchedData;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reports: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- Existing Filter/Calculation Logic (Unchanged) ---
  List<String> get uniqueDates => ['All', ...reportData.map((e) => e['date'].toString()).toSet()];
  List<String> get uniqueProducts => ['All', ...reportData.map((e) => e['product'].toString()).toSet()];

  List<Map<String, dynamic>> get filteredData {
    List<Map<String, dynamic>> data = reportData;

    if (selectedDate != 'All') {
      data = data.where((e) => e['date'] == selectedDate).toList();
    }

    if (selectedProduct != 'All') {
      data = data.where((e) => e['product'] == selectedProduct).toList();
    }

    return data;
  }

  List<Map<String, dynamic>> get topSales {
    var totals = <String, int>{};
    for (var item in reportData) {
      // Ensure quantity is treated as an int, as per your original logic
      final quantity = item['quantity'] is int ? item['quantity'] as int : (item['quantity'] as num).toInt();
      totals[item['product']] = (totals[item['product']] ?? 0) + quantity;
    }
    var sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(topN).map((e) => {'product': e.key, 'quantity': e.value}).toList();
  }

  double get averageSale {
    if (reportData.isEmpty) return 0;
    // Ensure all numeric types are cast correctly before calculation
    double total = reportData.fold(0.0, (sum, e) {
      final quantity = e['quantity'] is int ? e['quantity'].toDouble() : e['quantity'] as double;
      final price = e['price'] is int ? e['price'].toDouble() : e['price'] as double;
      return sum + (quantity * price);
    });
    return total / reportData.length;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReports,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Report Type Dropdown
            Row(
              children: [
                const Text('Report Type: '),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: selectedReport,
                  items: ['Item', 'Date', 'Average', 'Top Sales']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedReport = val!),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Filters
            if (selectedReport != 'Average')
              Row(
                children: [
                  const Text('Filter Date: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedDate,
                    items: uniqueDates
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedDate = val!),
                  ),
                  const SizedBox(width: 16),
                  const Text('Filter Product: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedProduct,
                    items: uniqueProducts
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) => setState(() => selectedProduct = val!),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Top N Filter
            if (selectedReport == 'Top Sales')
              Row(
                children: [
                  const Text('Show Top N: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: topN,
                    items: List.generate(10, (i) => i + 1)
                        .map((n) => DropdownMenuItem(value: n, child: Text(n.toString())))
                        .toList(),
                    onChanged: (val) => setState(() => topN = val!),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Data Display
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Builder(
                  builder: (context) {
                    if (reportData.isEmpty) {
                      return const Center(child: Text("No sales data available."));
                    }

                    if (selectedReport == 'Average') {
                      return Text(
                        'Average Sale: \$${averageSale.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      );
                    } else if (selectedReport == 'Top Sales') {
                      return DataTable(
                        columns: const [
                          DataColumn(label: Text('Product')),
                          DataColumn(label: Text('Quantity Sold')),
                        ],
                        rows: topSales
                            .map((item) => DataRow(cells: [
                          DataCell(Text(item['product'])),
                          DataCell(Text(item['quantity'].toString())),
                        ]))
                            .toList(),
                      );
                    } else {
                      return DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Product')),
                          DataColumn(label: Text('Quantity')),
                          DataColumn(label: Text('Price')),
                          DataColumn(label: Text('Total')),
                        ],
                        rows: filteredData
                            .map(
                              (item) => DataRow(cells: [
                            DataCell(Text(item['date'])),
                            DataCell(Text(item['product'])),
                            DataCell(Text(item['quantity'].toString())),
                            DataCell(Text('\$${item['price']}')),
                            DataCell(Text('\$${((item['quantity'] as num) * (item['price'] as num)).toStringAsFixed(2)}')),
                          ]),
                        )
                            .toList(),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}