import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/admin/sidebar.dart';

const String _BASE_URL = 'http://10.0.2.2:8000/api';

class CustomerListScreen extends StatefulWidget {
  final int shopId;
  final String accessToken;

  const CustomerListScreen({super.key, required this.shopId, required this.accessToken});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  List<dynamic> _customers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
  }

  Future<void> _fetchCustomers() async {
    setState(() => _isLoading = true);
    final uri = Uri.parse('$_BASE_URL/customers/?shop=${widget.shopId}');
    final response = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.accessToken}',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _customers = data;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load customers')));
    }
  }
  Future<void> _payCustomerDebt(int customerId, double amount) async {
    final uri = Uri.parse('$_BASE_URL/customers/$customerId/pay/');
    final payload = {"amount": amount};

    final response = await http.post(
      uri,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.accessToken}",
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Payment recorded successfully')));
      _fetchCustomers(); // refresh list
    } else {
      final error = jsonDecode(response.body);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to record payment: $error')));
    }
  }

  void _navigateToAddCustomer() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          shopId: widget.shopId,
          accessToken: widget.accessToken,
        ),
      ),
    );

    // Refresh list if a customer was added
    if (result == true) _fetchCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideBar(selectedPage: 'Dashboard'), // Uncomment if SideBar is available
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _navigateToAddCustomer,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
          ? const Center(child: Text('No customers yet.'))
          : ListView.builder(
        itemCount: _customers.length,
        itemBuilder: (ctx, index) {
          final customer = _customers[index];
          final totalDebt = double.tryParse(customer['total_debt'].toString()) ?? 0.0;
          final paidAmount = double.tryParse(customer['paid_amount']?.toString() ?? '0') ?? 0.0;
          final remaining = totalDebt - paidAmount;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Name & Phone
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          customer['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        customer['phone'] ?? '-',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Debt info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Debt: \$${totalDebt.toStringAsFixed(2)}'),
                      Text('Remaining: \$${remaining.toStringAsFixed(2)}'),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Pay button
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: remaining <= 0
                          ? null
                          : () {
                        final amountController = TextEditingController();
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Pay Debt'),
                            content: TextField(
                              controller: amountController,
                              decoration: InputDecoration(
                                labelText:
                                'Amount (max \$${remaining.toStringAsFixed(2)})',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                  onPressed: () {
                                    final amount = double.tryParse(
                                        amountController.text.trim()) ??
                                        0.0;
                                    if (amount <= 0 || amount > remaining) return;
                                    _payCustomerDebt(customer['id'], amount);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('Pay')),
                            ],
                          ),
                        );
                      },
                      child: const Text('Pay'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CustomerFormScreen extends StatefulWidget {
  final int shopId;
  final String accessToken;

  const CustomerFormScreen({super.key, required this.shopId, required this.accessToken});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;

  String name = '';
  String phone = '';
  String email = '';
  String address = '';

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();
    setState(() => isLoading = true);

    final payload = {
      "shop": widget.shopId,
      "name": name,
      "phone": phone,
      "email": email,
      "address": address,
    };

    try {
      final response = await http.post(
        Uri.parse('$_BASE_URL/customers/'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.accessToken}"
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer created successfully!')));
          Navigator.pop(context, true); // Signal success
        }
      } else {
        final error = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to create customer: $error')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Customer')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.isEmpty ? 'Enter name' : null,
                onSaved: (value) => name = value!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.isEmpty ? 'Enter phone' : null,
                onSaved: (value) => phone = value!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value != null && value.isNotEmpty && !value.contains('@') ? 'Enter valid email' : null,
                onSaved: (value) => email = value!.trim(),
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
                onSaved: (value) => address = value!.trim(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitForm,
                child: const Text('Create Customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
