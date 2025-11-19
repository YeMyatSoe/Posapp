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

const String _BASE_URL = 'http://10.0.2.2:8000/api';
const String _REFRESH_URL = 'http://10.0.2.2:8000/api/token/refresh/';

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

  int? _selectedCustomerId;
  double _paidAmount = 0;
  String _paymentMethod = 'CASH';
  List<Customer> _customers = [];
  late TextEditingController _paidAmountController;

  @override
  void initState() {
    super.initState();
    _paidAmountController = TextEditingController();
    _loadTokenAndPrinter();
    _fetchCustomers();
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers() async {
    if (widget.shopId == null) return;

    final url = '$_BASE_URL/customers/?shop=${widget.shopId}';
    try {
      final response = await _makeApiCall('GET', url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          _customers = data
              .map((c) => Customer(id: c['id'], name: c['name']))
              .toList();
        });
      } else {
        _showMessage('Failed to fetch customers: ${response.statusCode}');
      }
    } catch (e) {
      _showMessage('Error fetching customers: $e');
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
        setState(() => _accessToken = newAccessToken);
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

    final headers = {
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
        return _makeApiCall(method, url, payload: payload, retryCount: 1);
      }
    }

    return response;
  }

  void _showMessage(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _checkout(CartProvider cart) async {
    if (cart.items.isEmpty) {
      _showMessage('The cart is empty.');
      return;
    }

    final double totalAmount = cart.totalAmount;

    // Prevent invalid debt
    if (_paidAmount < totalAmount && _selectedCustomerId == null) {
      _showMessage(
        'Cannot create debt. Please select a customer or pay the full amount.',
      );
      return;
    }

    final Map<dynamic, dynamic> itemsToPrint = Map.from(cart.items);

    final payload = {
      "shop": widget.shopId,
      "user": 1,
      "items": cart.checkoutItems,
      "payment_method": _paymentMethod,
      "paid_amount": _paidAmount,
      if (_selectedCustomerId != null) "customer_id": _selectedCustomerId,
    };

    try {
      final response = await _makeApiCall(
        'POST',
        '$_BASE_URL/orders/',
        payload: payload,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showMessage('Order placed successfully!');
        cart.clearCart();
        _printPdfReceipt(itemsToPrint, totalAmount);
        _printBluetoothReceipt(itemsToPrint, totalAmount);
      } else {
        final error = jsonDecode(response.body);
        _showMessage('Checkout failed: ${error.toString()}');
      }
    } catch (e) {
      _showMessage('Checkout failed: $e');
    }
  }

  void _printPdfReceipt(Map items, double totalAmount) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final customerName = _customers
        .firstWhere(
          (c) => c.id == _selectedCustomerId,
          orElse: () => Customer(id: 0, name: 'Guest'),
        )
        .name;

    final balance = _paidAmount - totalAmount;
    final changeOrDebt = balance >= 0
        ? 'Change: \$${balance.toStringAsFixed(2)}'
        : 'Debt: \$${(balance.abs()).toStringAsFixed(2)}';

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                '🛍️ My Awesome Store',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                '123 Main Street, Springfield\nPhone: +1 555-555-5555',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Date: ${now.toString().substring(0, 16)}'),
            pw.Text('Customer: $customerName'),
            pw.Text('Payment: $_paymentMethod'),
            pw.Divider(),

            pw.Table.fromTextArray(
              headers: ['Item', 'Qty', 'Unit', 'Total'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              data: items.values.map((item) {
                final total = item.price * item.quantity;          // ✅
                return [
                  item.product.name,
                  item.quantity.toString(),
                  '\$${item.price.toStringAsFixed(2)}',           // ✅
                  '\$${total.toStringAsFixed(2)}',               // ✅
                ];
              }).toList(),
            ),

            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Subtotal: \$${totalAmount.toStringAsFixed(2)}'),
                  pw.Text('Paid: \$${_paidAmount.toStringAsFixed(2)}'),
                  pw.Text(
                    changeOrDebt,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            pw.Divider(),
            pw.Center(
              child: pw.Text(
                'Thank you for shopping with us!',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Visit again 💖',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  void _printBluetoothReceipt(
    Map items,
    double totalAmount, {
    bool forceSelection = false,
  }) async {
    final profile = await pos_utils.CapabilityProfile.load();
    final generator = pos_utils.Generator(pos_utils.PaperSize.mm80, profile);
    final now = DateTime.now();

    List<int> bytes = [];
    final customerName = _customers
        .firstWhere(
          (c) => c.id == _selectedCustomerId,
          orElse: () => Customer(id: 0, name: 'Guest'),
        )
        .name;
    final balance = _paidAmount - totalAmount;

    bytes += generator.text(
      'My Awesome Store',
      styles: const pos_utils.PosStyles(
        align: pos_utils.PosAlign.center,
        bold: true,
        height: pos_utils.PosTextSize.size2,
        width: pos_utils.PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      '123 Main Street\nPhone: +1 555-555-5555',
      styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center),
    );
    bytes += generator.hr();
    bytes += generator.text('Date: ${now.toString().substring(0, 16)}');
    bytes += generator.text('Customer: $customerName');
    bytes += generator.text('Payment: $_paymentMethod');
    bytes += generator.hr();

    // Print each item
    for (var item in items.values) {
      final total = item.price * item.quantity;         // ✅
      bytes += generator.row([
        pos_utils.PosColumn(text: item.product.name, width: 6),
        pos_utils.PosColumn(text: '${item.quantity}', width: 2),
        pos_utils.PosColumn(
          text: total.toStringAsFixed(2),
          width: 4,
          styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();
    bytes += generator.text('Subtotal: \$${totalAmount.toStringAsFixed(2)}');
    bytes += generator.text('Paid: \$${_paidAmount.toStringAsFixed(2)}');
    if (balance >= 0) {
      bytes += generator.text('Change: \$${balance.toStringAsFixed(2)}');
    } else {
      bytes += generator.text('Debt: \$${(balance.abs()).toStringAsFixed(2)}');
    }
    bytes += generator.hr();

    bytes += generator.text(
      'Thank you for shopping with us!',
      styles: const pos_utils.PosStyles(
        align: pos_utils.PosAlign.center,
        bold: true,
      ),
    );
    bytes += generator.text(
      'Visit again 💖',
      styles: const pos_utils.PosStyles(align: pos_utils.PosAlign.center),
    );
    bytes += generator.cut();

    // Bluetooth print logic
    final Uint8List bytesToPrint = Uint8List.fromList(bytes);
    String? targetAddress = _savedPrinterAddress;

    if (forceSelection || targetAddress == null) {
      final device = await FlutterBluetoothPrinter.selectDevice(context);
      if (device == null) return;
      await _savePrinterAddress(device.address);
      targetAddress = device.address;
    }

    if (targetAddress != null) {
      try {
        await FlutterBluetoothPrinter.printBytes(
          data: bytesToPrint,
          address: targetAddress,
          keepConnected: false,
        );
        _showMessage('Receipt printed successfully!');
      } catch (e) {
        _showMessage('Printing failed. Reselect printer.');
        _printBluetoothReceipt(items, totalAmount, forceSelection: true);
      }
    }
  }

  Future<void> _savePrinterAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printerAddress', address);
    setState(() => _savedPrinterAddress = address);
    _showMessage('Printer saved successfully.');
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final total = cart.totalAmount;

    // Only set default paid amount if it's 0 or cart changed to empty
    if (_paidAmount == 0 && total > 0) {
      _paidAmount = total;
      _paidAmountController.text = total.toStringAsFixed(2);
    } else if (total == 0) {
      _paidAmount = 0;
      _paidAmountController.text = '';
    }
    if (isLoadingToken) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: POSMenuBar(
        totalAmount: total,
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
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(
                              item.product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Qty: ${item.quantity} ${item.unitsPerPack > 1 ? "(Pack)" : "(Single)"} • \$${item.totalAmount.toStringAsFixed(2)}',

                            ),

                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => cart.decrementItem(item),
                                ),
                                Text('${item.quantity}'),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: Colors.green,
                                  ),
                                  onPressed: () => cart.incrementItem(
                                    item,
                                    availableStock: item.product.variants
                                        .firstWhere((v) => v.id == item.variantId.toString())
                                        .stockQuantity,
                                  ),

                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => cart.removeItem(item),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),

            // Customer & Payment Section
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: 'Select Customer'),
              items: _customers
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              value: _selectedCustomerId,
              onChanged: (value) => setState(() => _selectedCustomerId = value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _paidAmountController,
              decoration: const InputDecoration(labelText: 'Paid Amount'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                // Only update if it's a valid number
                final parsed = double.tryParse(value);
                if (parsed != null) {
                  _paidAmount = parsed;
                }
                // If invalid, don't change _paidAmount (keep previous value)
              },
            ),

            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Payment Method'),
              value: _paymentMethod,
              items: [
                'CASH',
                'CARD',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (value) =>
                  setState(() => _paymentMethod = value ?? 'CASH'),
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: \$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton(
                  onPressed: () async => await _checkout(cart),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Checkout', style: TextStyle(fontSize: 16)),
                ),
              ],
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
    return AppBar(
      title: Text("Cart Total: \$${totalAmount.toStringAsFixed(2)}"),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
