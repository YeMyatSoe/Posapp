import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as pos_utils;
import 'package:http/http.dart' as http;

import '../providers/cart_provider.dart';
import '../widgets/menu_bar.dart';

// CRITICAL FIX: API Constants & Type Definition
const String _BASE_URL = 'http://10.0.2.2:8000/api';
const String _REFRESH_URL = 'http://10.0.2.2:8000/api/token/refresh/';
typedef ApiCallFunction = Future<http.Response> Function(String method, String url, {Map<String, dynamic>? payload});

class Customer {
  final int id;
  final String name;
  Customer({required this.id, required this.name});
}

class CartScreen extends StatefulWidget {
  final String role;
  final int? shopId;

  const CartScreen({super.key, required this.role, required this.shopId});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _accessToken = '';
  String _refreshToken = '';
  String? _savedPrinterAddress;
  bool isLoadingToken = true;

  // NEW: Fields for customer, paid amount, payment method
  int? _selectedCustomerId;
  double _paidAmount = 0;
  String _paymentMethod = 'CASH';
  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadTokenAndPrinter();
    _fetchCustomers(); // Load customers
  }

  Future<void> _fetchCustomers() async {
    if (widget.shopId == null) return;

    final url = '$_BASE_URL/customers/?shop=${widget.shopId}';
    try {
      final response = await _makeApiCall('GET', url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          _customers = data.map((c) => Customer(
            id: c['id'],
            name: c['name'],
          )).toList();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch customers: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching customers: $e')),
        );
      }
    }
  }


  Future<void> _loadTokenAndPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accessToken = prefs.getString('accessToken') ?? '';
      _refreshToken = prefs.getString('refreshToken') ?? '';
      _savedPrinterAddress = prefs.getString('printerAddress');
      isLoadingToken = false;
    });

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      await prefs.clear();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

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
          _accessToken = newAccessToken;
        });
      }
      return true;
    } else {
      await (await SharedPreferences.getInstance()).clear();

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, '/login');
        });
      }
      return false;
    }
  }

  Future<http.Response> _makeApiCall(
      String method,
      String url, {
        Map<String, dynamic>? payload,
        int retryCount = 0,
      }) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_accessToken',
    };

    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: body);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body);
          break;
        default:
          throw Exception("Invalid HTTP method");
      }
    } catch (e) {
      rethrow;
    }

    if (response.statusCode == 401 && retryCount == 0) {
      final success = await _refreshTokenUtility();

      if (success && mounted) {
        return _makeApiCall(
          method,
          url,
          payload: payload,
          retryCount: 1,
        );
      }
    }
    return response;
  }

  Future<void> _savePrinterAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printerAddress', address);
    setState(() => _savedPrinterAddress = address);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer saved successfully for future use.')),
      );
    }
  }
// In class _CartScreenState extends State<CartScreen> {
// ...

  Future<void> _checkout(CartProvider cart) async {
    if (cart.items.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The cart is empty.')),
      );
      return;
    }

    final double totalAmount = cart.totalAmount;

    // --- 💥 FIX: Validation to prevent debt without a customer 💥 ---
    if (_paidAmount < totalAmount && _selectedCustomerId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot create debt. Please select a customer or pay the full amount.')),
      );
      return;
    }
    // -----------------------------------------------------------------

    final Map<dynamic, dynamic> itemsToPrint = Map.from(cart.items);
    final double totalAmountToPrint = totalAmount; // Use local variable

    final payload = {
      "shop": widget.shopId,
      "user": 1, // TODO: replace with real user ID
      "items": cart.checkoutItems,
      "payment_method": _paymentMethod,
      "paid_amount": _paidAmount,
      // Only include customer_id if one is selected
      if (_selectedCustomerId != null) "customer_id": _selectedCustomerId,
    };

    try {
      final response = await _makeApiCall(
        'POST',
        '$_BASE_URL/orders/',
        payload: payload,
      );
// ... rest of the function remains the same

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order placed successfully!')),
        );

        cart.clearCart();

        _printPdfReceipt(itemsToPrint, totalAmountToPrint);
        _printBluetoothReceipt(itemsToPrint, totalAmountToPrint);
      } else if (response.statusCode != 401) {
        final error = jsonDecode(response.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: ${error.toString()}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e')),
      );
    }
  }

  void _printPdfReceipt(Map items, double totalAmount) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('RECEIPT', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: ['Name', 'Color', 'Size', 'Qty', 'Total'],
              data: items.values.map((item) {
                final total = item.product.price * item.quantity;
                return [
                  item.product.name,
                  item.colorName == "N/A" ? '-' : item.colorName,
                  item.sizeName == "N/A" ? '-' : item.sizeName,
                  item.quantity.toString(),
                  '\$${total.toStringAsFixed(2)}'
                ];
              }).toList(),
            ),
            pw.Divider(),
            pw.Text('Subtotal: \$${totalAmount.toStringAsFixed(2)}'),
            pw.Text('TOTAL: \$${totalAmount.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<List<int>> _generateBluetoothReceiptBytes(Map items, double totalAmount, pos_utils.PaperSize paper) async {
    final profile = await pos_utils.CapabilityProfile.load();
    final generator = pos_utils.Generator(paper, profile);
    final now = DateTime.now();
    List<int> bytes = [];

    bytes += generator.text('My Awesome Store',
        styles: const pos_utils.PosStyles(
            align: pos_utils.PosAlign.center,
            height: pos_utils.PosTextSize.size2,
            width: pos_utils.PosTextSize.size2,
            bold: true));
    bytes += generator.text('123 Main St, Flutterland', styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center));
    bytes += generator.hr();

    bytes += generator.row([
      pos_utils.PosColumn(text: 'Date:', width: 6),
      pos_utils.PosColumn(text: now.toString().substring(0, 16), width: 6, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right)),
    ]);
    bytes += generator.text('SALES RECEIPT', styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center, bold: true));
    bytes += generator.emptyLines(1);

    bytes += generator.row([
      pos_utils.PosColumn(text: 'Item', width: 4, styles: const pos_utils.PosStyles(bold: true)),
      pos_utils.PosColumn(text: 'Qty', width: 2, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center, bold: true)),
      pos_utils.PosColumn(text: 'Total', width: 6, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right, bold: true)),
    ]);
    bytes += generator.hr(ch: '-');

    for (var item in items.values) {
      final total = item.product.price * item.quantity;

      bytes += generator.row([
        pos_utils.PosColumn(text: item.product.name, width: 4),
        pos_utils.PosColumn(text: item.quantity.toString(), width: 2, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center)),
        pos_utils.PosColumn(text: total.toStringAsFixed(2), width: 6, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right)),
      ]);

      if (item.colorName != "N/A" || item.sizeName != "N/A") {
        final colorDetail = item.colorName != "N/A" ? 'Color: ${item.colorName}' : '';
        final sizeDetail = item.sizeName != "N/A" ? 'Size: ${item.sizeName}' : '';
        final details = (colorDetail.isNotEmpty && sizeDetail.isNotEmpty)
            ? '  ($colorDetail | $sizeDetail)'
            : '  ($colorDetail$sizeDetail)';

        bytes += generator.text(details, styles: const pos_utils.PosStyles(
          fontType: pos_utils.PosFontType.fontB,
          align: pos_utils.PosAlign.left,
        ));
      }
    }
    bytes += generator.hr();

    final subtotal = totalAmount;
    final total = subtotal;

    bytes += generator.row([
      pos_utils.PosColumn(text: 'Subtotal:', width: 6, styles: const pos_utils.PosStyles(bold: true)),
      pos_utils.PosColumn(text: '\$${subtotal.toStringAsFixed(2)}', width: 6, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right, bold: true)),
    ]);
    bytes += generator.row([
      pos_utils.PosColumn(text: 'TOTAL:', width: 6, styles: const pos_utils.PosStyles(bold: true, height: pos_utils.PosTextSize.size2, width: pos_utils.PosTextSize.size2)),
      pos_utils.PosColumn(text: '\$${total.toStringAsFixed(2)}', width: 6, styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right, bold: true, height: pos_utils.PosTextSize.size2, width: pos_utils.PosTextSize.size2)),
    ]);

    bytes += generator.emptyLines(1);
    bytes += generator.text('Thank you!', styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center, bold: true));
    bytes += generator.cut();

    return bytes;
  }

  void _printBluetoothReceipt(Map items, double totalAmount, {bool forceSelection = false}) async {
    final receiptData = await _generateBluetoothReceiptBytes(items, totalAmount, pos_utils.PaperSize.mm80);
    final Uint8List bytesToPrint = Uint8List.fromList(receiptData);

    String? targetAddress = _savedPrinterAddress;

    if (forceSelection || targetAddress == null) {
      final device = await FlutterBluetoothPrinter.selectDevice(context);
      if (device == null) return;
      await _savePrinterAddress(device.address);
      targetAddress = device.address;
    }

    if (targetAddress != null) {
      try {
        await FlutterBluetoothPrinter.printBytes(data: bytesToPrint, address: targetAddress, keepConnected: false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Printing initiated successfully!')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Printing failed. Please select printer again.')));
        _printBluetoothReceipt(items, totalAmount, forceSelection: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final total = cart.totalAmount;

    if (isLoadingToken) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: POSMenuBar(
        totalAmount: cart.totalAmount,
        userShopId: widget.shopId,
        token: _accessToken,
        role: widget.role,
        userRole: widget.role,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: cart.items.isEmpty
                  ? const Center(child: Text("Your cart is empty"))
                  : ListView.builder(
                itemCount: cart.items.length,
                itemBuilder: (ctx, index) {
                  final item = cart.items.entries.toList()[index].value;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: SizedBox(
                        width: 60,
                        height: 60,
                        child: Image.network(
                          item.product.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.shopping_bag, size: 40, color: Colors.blueGrey)),
                        ),
                      ),
                      title: Text(item.product.name),
                      subtitle: Text(
                          'Color: ${item.colorName == "N/A" ? "-" : item.colorName} | Size: ${item.sizeName == "N/A" ? "-" : item.sizeName}'),
                      trailing: SizedBox(
                        width: 160,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () => cart.decrementItem(item),
                            ),
                            Text(item.quantity.toString()),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green),
                              onPressed: () => cart.incrementItem(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => cart.removeItem(item),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // NEW UI: Customer selection & Paid amount & Payment method
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'Select Customer'),
                  items: _customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  value: _selectedCustomerId,
                  onChanged: (value) => setState(() => _selectedCustomerId = value),
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Paid Amount'),
                  keyboardType: TextInputType.number,
                  initialValue: total.toStringAsFixed(2),
                  onChanged: (value) => _paidAmount = double.tryParse(value) ?? total,
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Payment Method'),
                  value: _paymentMethod,
                  items: ['CASH', 'CARD'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (value) => setState(() => _paymentMethod = value ?? 'CASH'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Total : ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(width: 16),
                Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Printer Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(_savedPrinterAddress == null ? 'None Selected' : 'Saved (${_savedPrinterAddress!.substring(0, 10)}...)'),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _printBluetoothReceipt(cart.items, cart.totalAmount, forceSelection: true),
                    icon: const Icon(Icons.settings_bluetooth),
                    label: Text(_savedPrinterAddress == null ? 'Select Printer' : 'Change/Reselect'),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                onPressed: () async {
                  await _checkout(cart);
                },
                child: const Text('Checkout', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class POSMenuBar extends StatelessWidget implements PreferredSizeWidget {
  final double totalAmount;
  final int? userShopId;
  final String token;
  final String role;
  final String userRole;
  const POSMenuBar({
    super.key,
    required this.totalAmount,
    this.userShopId,
    required this.token,
    required this.role,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(title: Text("Cart Total: \$$totalAmount"));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
