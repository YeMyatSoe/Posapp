import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../models/adjustment.dart';
import '../../widgets/admin/sidebar.dart';
import '../../services/employee_service.dart';

// ============================
// CRITICAL: API Constants & Type Definition
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000/api';
const String _REFRESH_URL = 'http://10.0.2.2:8000/api/token/refresh/';
typedef RefreshTokenUtility = Future<bool> Function();

/// ====================================
/// Finance Main Screen with Module Tabs
/// ====================================
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  String _accessToken = ''; // CRITICAL: Renamed 'token' to '_accessToken' internally
  String _refreshToken = ''; // CRITICAL: Added state for refresh token
  bool _tokenLoaded = false;
  String selectedCategory = 'Payroll Analytics'; final int selectedShopId = 1;
  final List<String> categories = [
    'Expense Management',
    'Adjustment Management',
    'Revenue Reports',
    'Payroll Analytics',
    'Profit & Loss',

  ];

  @override
  void initState() {
    super.initState();
    _loadTokens(); // CRITICAL: Changed to load both tokens
  }

  // CRITICAL FIX: Load both access and refresh tokens
  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? '';
    _refreshToken = prefs.getString('refreshToken') ?? ''; // Load refresh token

    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      if (mounted) {
        // Clear tokens and force re-login if either is missing
        await prefs.clear();
        Navigator.pushReplacementNamed(context, '/login');
      }
    } else if (mounted) {
      setState(() {
        _tokenLoaded = true;
      });
    }
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
        Navigator.pushReplacementNamed(context, '/login');
      }
      return false;
    }
  }

  // Handler for when 401 is received, attempts refresh
  void _handleUnauthorized() async {
    // The utility already attempts refresh and navigates if it fails.
    await _refreshTokenUtility();
  }


  @override
  Widget build(BuildContext context) {
    // FIX: Show a loading indicator until the token is loaded
    if (!_tokenLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text("Finance Management")),
        drawer: const SideBar(selectedPage: 'FinanceManagement'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Existing content logic remains the same, but now it runs
    // only after _tokenLoaded is true and the 'token' variable is set.
    Widget content;

    // CRITICAL: Pass access token and the token utility to all screens
    switch (selectedCategory) {
      case 'Expense Management':
        content = ExpenseManagementScreen(
          token: _accessToken, // Use the correct local token state
          refreshTokenUtility: _refreshTokenUtility,
          handleUnauthorized: _handleUnauthorized,
        );
        break;
      case 'Revenue Reports':
        content = const RevenueReportsScreen();
        break;
      case 'Adjustment Management':
        content = AdjustmentManagementScreen(
          token: _accessToken, // Use the correct local token state
          shopId: selectedShopId,
          refreshTokenUtility: _refreshTokenUtility,
          handleUnauthorized: _handleUnauthorized,
        );
        break;
      case 'Payroll Analytics':
        content = PayrollScreen(
          token: _accessToken, // Use the correct local token state
          refreshTokenUtility: _refreshTokenUtility,
          handleUnauthorized: _handleUnauthorized,
        );
        break;
      case 'Profit & Loss':
        content = ProfitLossScreen(
          token: _accessToken, // Use the correct local token state
          refreshTokenUtility: _refreshTokenUtility,
          handleUnauthorized: _handleUnauthorized,
        );
        break;

      default:
        content = const SizedBox();
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Finance Management")),
      drawer: const SideBar(selectedPage: 'FinanceManagement'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((c) {
                  final isSelected = c == selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        isSelected ? Colors.blue : Colors.grey[300],
                        foregroundColor: isSelected ? Colors.white : Colors.black,
                      ),
                      onPressed: () => setState(() => selectedCategory = c),
                      child: Text(c),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// ====================================
/// Expense Management Screen with JWT
/// ====================================
// CRITICAL: Updated constructor to accept refresh logic
class ExpenseManagementScreen extends StatefulWidget {
  final String token;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback handleUnauthorized;

  const ExpenseManagementScreen({
    super.key,
    required this.token,
    required this.refreshTokenUtility,
    required this.handleUnauthorized,
  });

  @override
  State<ExpenseManagementScreen> createState() =>
      _ExpenseManagementScreenState();
}

class _ExpenseManagementScreenState extends State<ExpenseManagementScreen> {
  List<Map<String, dynamic>> expenses = [];
  List<Map<String, dynamic>> shops = [];
  double totalMonthlySalary = 0.0;
  bool loading = true;
  late String _currentAccessToken; // CRITICAL: Mutable token state

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token; // Initialize
    fetchData();
  }

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // CRITICAL FIX: Reusable API Call Helper with Token Refresh/Retry
  Future<http.Response> _makeApiCall(String method, String url, {Map<String, dynamic>? payload, int retryCount = 0}) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    try {
      final currentHeaders = headers;
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
      final success = await widget.refreshTokenUtility(); // Attempt refresh

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() { // Update local state
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        return _makeApiCall(method, url, payload: payload, retryCount: 1); // Retry
      }
    }
    return response;
  }

  Future<void> fetchData() async {
    if (_currentAccessToken.isEmpty) { // Use local token
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);
    try {
      // FIX: Use _makeApiCall for expense and shops data
      final resExp = await _makeApiCall('GET', '$_API_BASE_URL/expenses/');
      final resShops = await _makeApiCall('GET', '$_API_BASE_URL/shops/');

      // NOTE: ApiService.getTotalMonthlySalary needs token logic added internally
      // or to be refactored to use _makeApiCall as well. Assuming it works for now.
      totalMonthlySalary = await ApiService.getTotalMonthlySalary();

      if (resExp.statusCode == 401 || resShops.statusCode == 401) {
        widget.handleUnauthorized(); // Notify parent if refresh failed
        return;
      }

      if (resExp.statusCode == 200) {
        expenses = List<Map<String, dynamic>>.from(jsonDecode(resExp.body));
      }
      if (resShops.statusCode == 200) {
        shops = List<Map<String, dynamic>>.from(jsonDecode(resShops.body));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching data: $e")),
        );
      }
    } finally {
      setState(() => loading = false);
    }
  }

  void _handleUnauthorized() async {
    // FIX: The parent handles navigation, this just ensures local state cleanup if necessary
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _deleteExpense(int id) async {
    try {
      // FIX: Use _makeApiCall
      final res = await _makeApiCall('DELETE', '$_API_BASE_URL/expenses/$id/');

      if (res.statusCode == 401) return widget.handleUnauthorized();
      if (res.statusCode == 204) fetchData();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error deleting: $e")));
    }
  }

  Future<void> _navigateToForm({Map<String, dynamic>? expense}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          expense: expense,
          shops: shops,
          totalMonthlySalary: totalMonthlySalary,
          // No token needed here as form returns payload to this screen to save
        ),
      ),
    );
    if (result != null && result is Map<String, dynamic>) {
      // FIX: Use _makeApiCall to save the expense
      try {
        final url = expense == null
            ? '$_API_BASE_URL/expenses/'
            : '$_API_BASE_URL/expenses/${expense['id']}/';
        final method = expense == null ? 'POST' : 'PUT';

        final res = await _makeApiCall(method, url, payload: result);

        if (res.statusCode == 401) return widget.handleUnauthorized();
        fetchData();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Error saving: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Expenses")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _navigateToForm(),
              icon: const Icon(Icons.add),
              label: const Text("Add Expense"),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text("ID")),
                    DataColumn(label: Text("Shop")),
                    DataColumn(label: Text("Date")),
                    DataColumn(label: Text("Category")),
                    DataColumn(label: Text("Amount")),
                    DataColumn(label: Text("Actions")),
                  ],
                  rows: expenses.map((e) {
                    final shopName = e['shop'] is Map
                        ? (e['shop']['name'] ?? '')
                        : e['shop']?.toString() ?? '';
                    final amount = parseDouble(e['amount']);

                    return DataRow(cells: [
                      DataCell(Text(e['id'].toString())),
                      DataCell(Text(shopName)),
                      DataCell(Text(e['date'].toString())),
                      DataCell(Text(e['category'].toString())),
                      DataCell(Text("\$${amount.toStringAsFixed(2)}")),
                      DataCell(Row(
                        children: [
                          IconButton(
                            icon:
                            const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () =>
                                _navigateToForm(expense: e),
                          ),
                          IconButton(
                            icon:
                            const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteExpense(e['id']),
                          ),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// ====================================
/// Expense Form Screen (Unchanged - no API calls)
/// ====================================
class ExpenseFormScreen extends StatefulWidget {
  final Map<String, dynamic>? expense;
  final List<Map<String, dynamic>> shops;
  final double totalMonthlySalary;

  const ExpenseFormScreen({
    super.key,
    this.expense,
    required this.shops,
    this.totalMonthlySalary = 0.0,
  });

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController dateController;
  late TextEditingController amountController;
  late TextEditingController descriptionController;
  String? selectedCategory;
  int? selectedShopId;

  final List<String> categories = [
    "RENT",
    "UTILITY",
    "SALARY",
    "MARKETING",
    "SUPPLIES",
    "OTHER"
  ];

  @override
  void initState() {
    super.initState();
    dateController =
        TextEditingController(text: widget.expense?['date'] ?? "");
    amountController =
        TextEditingController(text: widget.expense?['amount']?.toString() ?? "");
    descriptionController =
        TextEditingController(text: widget.expense?['description'] ?? "");
    selectedCategory = widget.expense?['category'] ?? "OTHER";

    final shop = widget.expense?['shop'];
    if (shop is Map) {
      selectedShopId = shop['id'] as int?;
    } else if (shop is int) {
      selectedShopId = shop;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
      AppBar(title: Text(widget.expense == null ? "Add Expense" : "Edit Expense")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<int>(
                value: selectedShopId,
                decoration: const InputDecoration(labelText: "Shop"),
                items: widget.shops
                    .map((s) => DropdownMenuItem<int>(
                  value: s['id'],
                  child: Text(s['name']),
                ))
                    .toList(),
                onChanged: (v) => setState(() => selectedShopId = v),
                validator: (v) => v == null ? "Select a shop" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: dateController,
                decoration: const InputDecoration(labelText: "Date (YYYY-MM-DD)"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: "Category"),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    selectedCategory = v;

                    if (selectedCategory == 'SALARY' && widget.expense == null) {
                      final totalSalary = widget.totalMonthlySalary.toStringAsFixed(2);
                      amountController.text = totalSalary;
                    }
                    else if (selectedCategory != 'SALARY') {
                      if (amountController.text == widget.totalMonthlySalary.toStringAsFixed(2)) {
                        amountController.text = '';
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: amountController,
                decoration: const InputDecoration(labelText: "Amount"),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: "Description"),
                validator: (v) => v == null || v.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final newExpense = {
                      "shop": selectedShopId,
                      "date": dateController.text,
                      "category": selectedCategory,
                      "amount": double.tryParse(amountController.text) ?? 0,
                      "description": descriptionController.text,
                    };
                    Navigator.pop(context, newExpense);
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// ====================================
/// Revenue Reports (read-only)
/// ====================================
class RevenueReportsScreen extends StatelessWidget {
  const RevenueReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final revenues = [
      {"month": "August", "amount": 12000.0},
      {"month": "September", "amount": 15000.0},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: revenues
          .map((r) => Card(
        child: ListTile(
          title: Text("Month: ${r['month']}"),
          subtitle: Text("Revenue: \$${(r['amount'] as double).toStringAsFixed(2)}"),
        ),
      ))
          .toList(),
    );
  }
}
/// ====================================
/// Payroll Screen (Analytics)
/// ====================================
// CRITICAL: Updated constructor to accept refresh logic
class PayrollScreen extends StatefulWidget {
  final String token;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback handleUnauthorized;

  const PayrollScreen({
    super.key,
    required this.token,
    required this.refreshTokenUtility,
    required this.handleUnauthorized,
  });

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  List<Map<String, dynamic>> payrolls = [];
  bool loading = true;
  late String _currentAccessToken; // CRITICAL: Mutable token state

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token; // Initialize
    fetchPayrolls();
  }

  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // CRITICAL FIX: Reusable API Call Helper with Token Refresh/Retry
  Future<http.Response> _makeApiCall(String method, String url, {Map<String, dynamic>? payload, int retryCount = 0}) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    try {
      final currentHeaders = headers;
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
      final success = await widget.refreshTokenUtility(); // Attempt refresh

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() { // Update local state
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        return _makeApiCall(method, url, payload: payload, retryCount: 1); // Retry
      }
    }
    return response;
  }


  Future<void> fetchPayrolls() async {
    // Guard clause to prevent API call with an empty token
    if (_currentAccessToken.isEmpty) { // Use local token
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);
    try {
      // FIX: Use _makeApiCall
      final res = await _makeApiCall('GET', '$_API_BASE_URL/payrolls/');

      if (res.statusCode == 401) return widget.handleUnauthorized();

      if (res.statusCode == 200) {
        payrolls = List<Map<String, dynamic>>.from(jsonDecode(res.body));
      } else {
        throw Exception('Failed to fetch payrolls');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  void _navigateToForm({Map<String, dynamic>? payroll}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PayrollFormScreen(
          payroll: payroll,
          // CRITICAL: Pass token and refresh utility to the form
          accessToken: _currentAccessToken,
          refreshTokenUtility: widget.refreshTokenUtility,
        ),
      ),
    );

    if (result != null) {
      await fetchPayrolls();
    }
  }

  void _deletePayroll(int id) async {
    try {
      // FIX: Use _makeApiCall
      final res = await _makeApiCall('DELETE', '$_API_BASE_URL/payrolls/$id/');
      if (res.statusCode == 401) return widget.handleUnauthorized();
      if (res.statusCode == 204) fetchPayrolls();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    // Add a check to inform the user if the token is empty (which should be prevented by FinanceScreen fix)
    if (_currentAccessToken.isEmpty) {
      return const Center(child: Text("Authentication required. Please wait or relogin."));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToForm(),
            icon: const Icon(Icons.add),
            label: const Text("Add Payroll"),
          ),
          const SizedBox(height: 16),
          Expanded( // FIX: Added Expanded to prevent render overflow
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("ID")),
                  DataColumn(label: Text("Employee")),
                  DataColumn(label: Text("Month")),
                  DataColumn(label: Text("Basic Salary")),
                  DataColumn(label: Text("Bonus")),
                  DataColumn(label: Text("Deductions")),
                  DataColumn(label: Text("Net Pay")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: payrolls.map((p) {
                  final employeeName = p['employee']?['user']?['username'] ?? p['employeeName'] ?? '';

                  // Use safe parsing to prevent the 'String' is not a subtype of 'num' error
                  final salary = parseDouble(p['salary']);
                  final bonus = parseDouble(p['bonus']);
                  final deductions = parseDouble(p['deductions']);
                  final netPay = parseDouble(p['net_pay']);

                  return DataRow(cells: [
                    DataCell(Text(p['id'].toString())),
                    DataCell(Text(employeeName)),
                    DataCell(Text(p['month'] ?? '')),
                    // Use formatted safe numbers
                    DataCell(Text("\$${salary.toStringAsFixed(2)}")),
                    DataCell(Text("\$${bonus.toStringAsFixed(2)}")),
                    DataCell(Text("\$${deductions.toStringAsFixed(2)}")),
                    DataCell(Text("\$${netPay.toStringAsFixed(2)}")),
                    DataCell(Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(payroll: p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deletePayroll(p['id']),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//============ Payroll Form ============
// Ensure you have the necessary imports (e.g., flutter/material.dart, api_service.dart)

// Helper function (outside the State class)
double _calculateBonusAmount({required double salary, required String rating}) {
  final cleanRating = rating.toLowerCase().trim();
  double percentage;

  if (cleanRating == 'best') {
    percentage = 0.10; // 10% of salary
  } else if (cleanRating.contains('very good') || cleanRating == 'verygood') {
    percentage = 0.07; // 7% of salary
  } else if (cleanRating == 'good') {
    percentage = 0.05; // 5% of salary
  } else {
    percentage = 0.00; // Handles 'N/A' or other values
  }

  final bonus = salary * percentage;
  return double.parse(bonus.toStringAsFixed(2));
}

// ---------------- PAYROLL FORM SCREEN CLASS ----------------

class PayrollFormScreen extends StatefulWidget {
  final Map<String, dynamic>? payroll;
  const PayrollFormScreen({super.key, this.payroll, required String accessToken, required RefreshTokenUtility refreshTokenUtility});

  @override
  State<PayrollFormScreen> createState() => _PayrollFormScreenState();
}

class _PayrollFormScreenState extends State<PayrollFormScreen> {
  final _formKey = GlobalKey<FormState>();

  int? selectedEmployeeId;
  String? selectedMonth;
  DateTime? selectedDate;

  String _employeeRating = '...';

  // Stores the total days the employee was expected to work
  int _totalExpectedWorkingDays = 0;

  // Controllers for editable fields
  late TextEditingController basicSalaryController;
  late TextEditingController bonusController;
  late TextEditingController deductionsController;
  late TextEditingController overtimeController;

  // Controllers for read-only auto-fetched/calculated values (for display only)
  late TextEditingController performanceBonusController; // Holds auto-calculated bonus amount (before manual override)
  late TextEditingController absentDaysController;       // Holds auto-fetched absent days count

  // Controllers for the NEW manual money input fields
  late TextEditingController manualPerformanceBonusController;
  late TextEditingController manualAbsentDeductionController;

  List<Map<String, dynamic>> employees = [];
  final List<String> months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Helper to find an employee's data by ID
  Map<String, dynamic>? _findEmployee(int id) {
    if (employees.isEmpty) return null;

    final foundEmployee = employees.firstWhere(
          (emp) => emp['id'] == id,
      orElse: () => <String, dynamic>{},
    );

    return foundEmployee.isNotEmpty ? foundEmployee : null;
  }

// ---------------- FETCH PERFORMANCE RATING ----------------
  Future<void> _fetchEmployeeRating(int employeeId) async {
    try {
      // Replace ApiService.fetchEmployeePerformanceRating with your actual call
      final rating = await ApiService.fetchEmployeePerformanceRating(employeeId);

      if (mounted) {
        setState(() {
          _employeeRating = rating;
          _calculatePerformanceBonus(); // Trigger bonus calculation
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _employeeRating = 'N/A');
        _calculatePerformanceBonus(); // Calculate 0 bonus based on 'N/A'
      }
    }
  }

// ---------------- CALCULATE PERFORMANCE BONUS (Auto) ----------------
  void _calculatePerformanceBonus() {
    double currentSalary = double.tryParse(basicSalaryController.text) ?? 0.0;

    final calculatedBonus = _calculateBonusAmount(
        salary: currentSalary,
        rating: _employeeRating
    );

    // Update the READ-ONLY side of the split field
    if (performanceBonusController.text != calculatedBonus.toStringAsFixed(2)) {
      performanceBonusController.text = calculatedBonus.toStringAsFixed(2);
      setState(() {});
    }
  }

  Future<void> _fetchAbsentDays(int employeeId, String month) async {
    try {
      final year = selectedDate?.year ?? DateTime.now().year;

      // Replace ApiService.fetchAbsentAndWorkingDays with your actual call
      final absentData = await ApiService.fetchAbsentAndWorkingDays(
          employeeId, month, year: year);

      if (mounted) {
        setState(() {
          // Update the READ-ONLY side of the split field
          absentDaysController.text = absentData.absentDays.toString();
          // Update the Total Expected Working Days state
          _totalExpectedWorkingDays = absentData.totalWorkingDays;
        });
      }
    } catch (e) {
      if (mounted) {
        absentDaysController.text = '0';
        _totalExpectedWorkingDays = 0;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to fetch absent data."))
        );
        setState(() {});
      }
    }
  }

  // ------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Standard Controllers
    basicSalaryController = TextEditingController(text: widget.payroll?['salary']?.toString() ?? '0');
    bonusController = TextEditingController(text: widget.payroll?['bonus']?.toString() ?? '0');
    deductionsController = TextEditingController(text: widget.payroll?['deductions']?.toString() ?? '0');
    overtimeController = TextEditingController(text: widget.payroll?['overtime']?.toString() ?? '0');

    // Read-Only Controllers (for display of auto-calculated/fetched values)
    // We can use a default/placeholder value here, as the actual calculation happens later.
    performanceBonusController = TextEditingController(text: '0.00');
    absentDaysController = TextEditingController(text: widget.payroll?['absent_days']?.toString() ?? '0');

    // NEW Manual Money Input Controllers
    manualPerformanceBonusController =
        TextEditingController(text: widget.payroll?['performance_bonus']?.toString() ?? '0');
    // Assuming 'absent_deduction_amount' is the field for the manual deduction amount.
    // If your API uses 'absent_days' for the money, you must adjust the calculation.
    manualAbsentDeductionController =
        TextEditingController(text: widget.payroll?['absent_deduction_amount']?.toString() ?? '0');


    selectedEmployeeId = widget.payroll?['employee_id'] as int?;

    if (widget.payroll != null) {
      _employeeRating = 'Checking...';
    }

    selectedMonth = widget.payroll?['month'] as String?
        ?? months[DateTime.now().month - 1];

    selectedDate = widget.payroll?['date'] != null
        ? DateTime.tryParse(widget.payroll!['date'])
        : DateTime.now();

    fetchEmployees();
  }

  @override
  void dispose() {
    basicSalaryController.dispose();
    bonusController.dispose();
    deductionsController.dispose();
    overtimeController.dispose();
    performanceBonusController.dispose();
    absentDaysController.dispose();
    manualPerformanceBonusController.dispose();
    manualAbsentDeductionController.dispose();
    super.dispose();
  }


  Future<void> fetchEmployees() async {
    try {
      // Replace ApiService.getEmployees with your actual call
      final result = await ApiService.getEmployees();

      if (result is List) {
        employees = result
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      bool shouldAutoFetch = false;

      if (widget.payroll == null && selectedEmployeeId == null && employees.isNotEmpty) {
        selectedEmployeeId = employees.first['id'] as int?;
        shouldAutoFetch = true;

        final employee = _findEmployee(selectedEmployeeId!);
        if (employee != null && employee.containsKey('salary')) {
          basicSalaryController.text = employee['salary']?.toString() ?? '0';
        }
      }
      else if (selectedEmployeeId != null && selectedMonth != null) {
        shouldAutoFetch = true;
      }

      setState(() {
        if (shouldAutoFetch && selectedEmployeeId != null && selectedMonth != null) {
          _fetchAbsentDays(selectedEmployeeId!, selectedMonth!);
          _fetchEmployeeRating(selectedEmployeeId!);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Failed to load employees.")));
      }
    }
  }


  Future<void> savePayroll() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      "employee_id": selectedEmployeeId,
      "month": selectedMonth,
      "salary": double.tryParse(basicSalaryController.text) ?? 0.0,
      "bonus": double.tryParse(bonusController.text) ?? 0.0,
      "deductions": double.tryParse(deductionsController.text) ?? 0.0,
      "overtime": double.tryParse(overtimeController.text) ?? 0.0,

      // *** SAVE MANUAL MONEY INPUTS ***
      "performance_bonus": double.tryParse(manualPerformanceBonusController.text) ?? 0.0,
      "absent_deduction_amount": double.tryParse(manualAbsentDeductionController.text) ?? 0.0,

      // Save the absent days count as well, as it's separate from the deduction amount
      "absent_days": int.tryParse(absentDaysController.text) ?? 0,

      "date": selectedDate?.toIso8601String().split("T").first,
    };

    try {
      Map<String, dynamic> savedPayroll;
      // Replace ApiService.updatePayroll/addPayroll with your actual calls
      if (widget.payroll != null && widget.payroll!['id'] is int) {
        savedPayroll = await ApiService.updatePayroll(widget.payroll!['id'], data);
      } else {
        savedPayroll = await ApiService.addPayroll(data);
      }
      if (mounted) Navigator.pop(context, savedPayroll);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save payroll: $e')));
      }
    }
  }

  /// Calculates the Net Pay, incorporating manually input absent deduction and bonus.
  double calculateNetPay() {
    final basic = double.tryParse(basicSalaryController.text) ?? 0;
    final bonus = double.tryParse(bonusController.text) ?? 0;
    final overtime = double.tryParse(overtimeController.text) ?? 0;

    // *** USE MANUAL INPUT CONTROLLERS FOR MONETARY VALUES ***
    final perfBonus = double.tryParse(manualPerformanceBonusController.text) ?? 0;
    final absentDeduction = double.tryParse(manualAbsentDeductionController.text) ?? 0;

    final deductions = double.tryParse(deductionsController.text) ?? 0;

    return basic + bonus + overtime + perfBonus - deductions - absentDeduction;
  }

  Widget _buildNumberField(String label, TextEditingController controller,
      {bool isInt = false, bool readOnly = false}) {
    return Column(
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          readOnly: readOnly,
          validator: (v) => v == null || v.isEmpty || double.tryParse(v!) == null
              ? "Enter a valid number"
              : null,
          onChanged: (_) {
            setState(() {});
            // Recalculate auto bonus if basic salary changes (for the read-only display)
            if (controller == basicSalaryController) {
              _calculatePerformanceBonus();
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final netPay = calculateNetPay();
    final theme = Theme.of(context);

    // Set a maximum desirable width for the form content
    const double maxFormWidth = 600.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.payroll != null ? "Edit Payroll" : "Add Payroll")),
      body: Center( // Center the content horizontally
        child: ConstrainedBox( // Constrain the maximum width
          constraints: const BoxConstraints(maxWidth: maxFormWidth),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // --- Section: Employee & Pay Period ---
                  Text(
                    "Employee & Pay Period Details",
                    style: theme.textTheme.titleMedium,
                  ),
                  const Divider(height: 24),

                  // Employee Dropdown
                  DropdownButtonFormField<int>(
                    value: selectedEmployeeId,
                    decoration: InputDecoration(
                      labelText: "Employee",
                      helperText: "Performance Rating: $_employeeRating",
                      helperStyle: TextStyle(color: theme.colorScheme.primary),
                    ),
                    items: employees
                        .map((emp) => DropdownMenuItem<int>(
                      value: emp['id'],
                      child: Text(emp['user']?['username'] ?? 'No Name'),
                    ))
                        .toList(),
                    onChanged: (v) {
                      selectedEmployeeId = v;

                      if (v != null) {
                        final employee = _findEmployee(v);
                        basicSalaryController.text = employee?['salary']?.toString() ?? '0';

                        if (selectedMonth != null) {
                          _fetchAbsentDays(v, selectedMonth!);
                        }
                        _fetchEmployeeRating(v);
                      } else {
                        basicSalaryController.text = '0';
                        absentDaysController.text = '0';
                        _employeeRating = '...';
                        performanceBonusController.text = '0';
                      }
                      setState(() {});
                    },
                    validator: (v) => v == null ? "Select an employee" : null,
                  ),
                  const SizedBox(height: 16),

                  // Month Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedMonth,
                    decoration: const InputDecoration(labelText: "Month of Payroll"),
                    items: months.map((m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m),
                    )).toList(),
                    onChanged: (v) {
                      selectedMonth = v;

                      if (selectedEmployeeId != null && v != null) {
                        _fetchAbsentDays(selectedEmployeeId!, v);
                      } else {
                        absentDaysController.text = '0';
                      }
                      setState(() {});
                    },
                    validator: (v) => v == null ? "Select a month" : null,
                  ),
                  const SizedBox(height: 8),

                  // Date Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        "Payment Date: ${selectedDate != null ? selectedDate!.toLocal().toString().split(' ')[0] : 'Not Set'}"),
                    trailing: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Text("Pick Date"),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),

                  // --- Section: Earnings ---
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text("Earnings", style: theme.textTheme.titleMedium),
                  ),

                  _buildNumberField("Basic Salary", basicSalaryController),
                  _buildNumberField("Bonus (Other)", bonusController),
                  _buildNumberField("Overtime", overtimeController),
                  const SizedBox(height: 8),

                  // --- Section: Deductions & Adjustments ---
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text("Deductions & Adjustments", style: theme.textTheme.titleMedium),
                  ),

                  // Deductions (Editable)
                  _buildNumberField("Deductions", deductionsController),
                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 🎯 SPLIT FIELD: Performance Bonus (Auto Value vs. Manual Price)
                  // ----------------------------------------------------
                  Text("Performance Bonus", style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Read-Only (Rating/Auto-Calculated Amount)
                      Expanded(
                        child: TextFormField(
                          // We now use a dummy controller or a simplified one, as the value is now driven by _employeeRating
                          controller: TextEditingController(text: _employeeRating),
                          decoration: InputDecoration(
                            labelText: "Performance Status",
                            suffixIcon: const Icon(Icons.star, color: Colors.amber),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: const OutlineInputBorder(),
                            // Removed the helperText as the label/value now clearly shows the status
                          ),
                          readOnly: true, // READ ONLY
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: Manual Input (Monetary Value)
                      Expanded(
                        child: TextFormField(
                          controller: manualPerformanceBonusController,
                          decoration: const InputDecoration(
                            labelText: "Final Bonus Amount",
                            prefixText: "\$",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}), // Recalculate Net Pay
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 🎯 SPLIT FIELD: Absent Days (Auto Count vs. Manual Price)
                  // ----------------------------------------------------
                  Text("Absentee Deduction", style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Read-Only (Absent Days Count)
                      Expanded(
                        child: TextFormField(
                          controller: absentDaysController,
                          decoration: InputDecoration(
                            labelText: "Absent Days Count",
                            suffixText: " days",
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: const OutlineInputBorder(),
                          ),
                          readOnly: true,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: Manual Input (Deduction Amount)
                      Expanded(
                        child: TextFormField(
                          controller: manualAbsentDeductionController,
                          decoration: const InputDecoration(
                            labelText: "Final Deduction Amount",
                            prefixText: "\$",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}), // Recalculate Net Pay
                        ),
                      ),
                    ],
                  ),

                  // Daily Rate Base Info
                  if (_totalExpectedWorkingDays > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        "Daily Rate Base: $_totalExpectedWorkingDays expected working days.",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // --- Net Pay Summary ---
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.primary.withOpacity(0.05),
                    ),
                    child: Center(
                      child: Text("NET PAY: \$${netPay.toStringAsFixed(2)}",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- Save Button ---
                  ElevatedButton(
                    onPressed: savePayroll,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      elevation: 4,
                    ),
                    child: Text(widget.payroll != null ? "Update Payroll" : "Save Payroll"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
//////////////////  ProfitLossScreen  ///////////////////
class ProfitLossScreen extends StatefulWidget {
  final String token;
  // FIX 1: Add RefreshTokenUtility and handleUnauthorized
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback handleUnauthorized;

  const ProfitLossScreen({
    super.key,
    required this.token,
    required this.refreshTokenUtility, // REQUIRED
    required this.handleUnauthorized,  // REQUIRED
  });

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  String selectedPeriod = "Monthly";
  int selectedIndex = 0;
  int shopId = 1;
  List<Map<String, double>> monthlyData = [];
  List<Map<String, double>> yearlyData = [];
  bool loading = true;
  final NumberFormat currency = NumberFormat.currency(locale: 'en_US', symbol: '\$');

  // FIX 2: Use a mutable token state, initialized from the widget
  late String _currentAccessToken;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token;
    fetchFinancialData();
  }

  // Helper to get headers with the current token
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  double parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // FIX 3: Refactor the API call logic to support retry after token refresh
  Future<http.Response> _fetchReportApi({int retryCount = 0}) async {
    final url = '$_API_BASE_URL/shop_report/?shop_id=$shopId&period=monthly';

    final res = await http.get(Uri.parse(url), headers: headers);

    if (res.statusCode == 401 && retryCount == 0) {
      final success = await widget.refreshTokenUtility(); // Attempt refresh

      if (success) {
        // Update local token state with the new token
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() {
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        // Retry the request once with the new token
        return _fetchReportApi(retryCount: 1);
      }
    }
    return res;
  }

  Future<void> fetchFinancialData() async {
    if (_currentAccessToken.isEmpty) {
      setState(() => loading = false);
      return;
    }

    setState(() => loading = true);
    try {
      // FIX 4: Use the refactored API call helper
      final res = await _fetchReportApi();

      if (res.statusCode == 401) {
        // If it's still 401 after the retry attempt, handle unauthorized
        widget.handleUnauthorized();
        return;
      }

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch shop report: ${res.statusCode}');
      }

      final data = json.decode(res.body);

      Map<String, Map<String, double>> monthlyMap = {};

      for (var item in data['pl_details'] ?? []) {
        final dateStr = item['date'] ?? DateTime.now().toIso8601String();
        final month = dateStr.substring(5, 7);

        monthlyMap.putIfAbsent(month, () => {
          'Revenue': 0.0,
          'COGS': 0.0,
          'Waste Loss': 0.0,
          'Operating Expenses': 0.0,
          'Other Expenses': 0.0,
        });

        monthlyMap[month]!['Revenue'] =
            (monthlyMap[month]!['Revenue'] ?? 0) + parseDouble(item['revenue']);
        monthlyMap[month]!['COGS'] =
            (monthlyMap[month]!['COGS'] ?? 0) + parseDouble(item['cogs']);
        monthlyMap[month]!['Waste Loss'] =
            (monthlyMap[month]!['Waste Loss'] ?? 0) + parseDouble(item['waste_loss']);
      }

      final totalExpenses = parseDouble(data['total_expenses']);
      final totalAdjustments = parseDouble(data['total_adjustments']).abs();

      for (var month in monthlyMap.keys) {
        monthlyMap[month]!['Operating Expenses'] = totalExpenses;
        monthlyMap[month]!['Other Expenses'] = totalAdjustments;
      }

      monthlyData = monthlyMap.values
          .map((e) => e.map((k, v) => MapEntry(k, v.toDouble())))
          .toList();

      yearlyData = [
        {
          'Revenue': monthlyData.fold(0.0, (sum, e) => sum + (e['Revenue'] ?? 0.0)),
          'COGS': monthlyData.fold(0.0, (sum, e) => sum + (e['COGS'] ?? 0.0)),
          'Waste Loss':
          monthlyData.fold(0.0, (sum, e) => sum + (e['Waste Loss'] ?? 0.0)),
          'Operating Expenses': totalExpenses,
          'Other Expenses': totalAdjustments,
        }
      ];

      if (monthlyData.isEmpty) {
        yearlyData = [
          {
            'Revenue': 0.0, 'COGS': 0.0, 'Waste Loss': 0.0,
            'Operating Expenses': 0.0, 'Other Expenses': 0.0,
          }
        ];
      }

    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error fetching financial data: ${e.toString()}")));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final dataList = selectedPeriod == "Monthly" ? monthlyData : yearlyData;
    if (loading) return const Center(child: CircularProgressIndicator());

    final data = dataList.isNotEmpty ? dataList[selectedIndex] : null;
    if (data == null) return const Center(child: Text("No financial data available for this period."));

    final revenue = data["Revenue"] ?? 0.0;
    final cogs = data["COGS"] ?? 0.0;
    final wasteLoss = data["Waste Loss"] ?? 0.0;
    final operatingExpenses = data["Operating Expenses"] ?? 0.0;
    final otherExpenses = data["Other Expenses"] ?? 0.0;

    final grossProfit = revenue - cogs - wasteLoss;
    final operatingProfit = grossProfit - operatingExpenses;
    final netProfit = operatingProfit + otherExpenses;

    final rows = [
      {"label": "Revenue", "amount": revenue, "type": "income"},
      {"label": "Cost of Goods Sold", "amount": cogs, "type": "expense"},
      {"label": "Waste Loss", "amount": wasteLoss, "type": "expense"},
      {"label": "Gross Profit", "amount": grossProfit, "type": "profit"},
      {"label": "Operating Expenses", "amount": operatingExpenses, "type": "expense"},
      {"label": "Operating Profit", "amount": operatingProfit, "type": "profit"},
      {"label": "Other Adjustments/Income", "amount": otherExpenses, "type": "adjustment"},
      {"label": "Net Profit", "amount": netProfit, "type": "profit"},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Profit & Loss Report")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period Selection
            Row(
              children: [
                const Text("Report Type:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: selectedPeriod,
                  items: ["Monthly", "Yearly"]
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (p) => setState(() {
                    selectedPeriod = p!;
                    selectedIndex = 0;
                  }),
                ),
              ],
            ),

            // Monthly Navigation
            if (selectedPeriod == "Monthly" && monthlyData.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: selectedIndex > 0
                          ? () => setState(() => selectedIndex--)
                          : null,
                    ),
                    Text(
                      "Record ${selectedIndex + 1} of ${monthlyData.length}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: selectedIndex < monthlyData.length - 1
                          ? () => setState(() => selectedIndex++)
                          : null,
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // P&L Table/List
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final label = row['label'] as String;
                  final amount = row['amount'] as double;
                  final type = row['type'] as String;

                  final isProfitLine = type == 'profit';
                  final isLoss = amount < 0;

                  // For expense lines, we show the absolute value in red.
                  // For profit lines, we show the actual sign.
                  final displayAmount = isProfitLine || type == 'adjustment'
                      ? amount
                      : amount.abs();

                  final amountText = currency.format(displayAmount);

                  // Color logic:
                  // - Profit lines: Red for loss, Blue for profit.
                  // - Expense/Income lines: Red for expense, Black for income (Revenue).
                  Color amountColor;
                  if (isProfitLine) {
                    amountColor = isLoss ? Colors.red.shade700 : Colors.green.shade700;
                  } else if (type == 'expense') {
                    // Expenses are shown as positive figures but colored red to signify deduction
                    amountColor = Colors.red.shade700;
                  } else {
                    // Income/Adjustment
                    amountColor = Colors.black;
                  }


                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontWeight: isProfitLine ? FontWeight.bold : FontWeight.normal,
                                fontSize: isProfitLine ? 16 : 14,
                                color: isProfitLine ? Colors.blue.shade900 : Colors.black87,
                              ),
                            ),
                            Text(
                              // Only profit lines will show a negative sign for loss
                              // Other expense/income lines will be formatted naturally.
                              amountText,
                              style: TextStyle(
                                fontWeight: isProfitLine ? FontWeight.bold : FontWeight.normal,
                                color: amountColor,
                                // Add an underline for the final Net Profit line
                                decoration: index == rows.length - 1 ? TextDecoration.overline : null,
                                decorationColor: amountColor,
                                decorationThickness: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Add a divider for subtotal lines like Gross Profit
                      if (isProfitLine && index < rows.length - 1)
                        const Divider(height: 1, thickness: 1),
                      // Add extra spacing after Gross Profit
                      if (label == "Gross Profit")
                        const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/////////// ADJUSTMENT  /////////////////////////
// CRITICAL: Updated constructor to accept refresh logic
class AdjustmentManagementScreen extends StatefulWidget {
  final String token;
  final int shopId;
  final RefreshTokenUtility refreshTokenUtility;
  final VoidCallback handleUnauthorized;

  const AdjustmentManagementScreen({
    super.key,
    required this.token,
    required this.shopId,
    required this.refreshTokenUtility,
    required this.handleUnauthorized,
  });

  @override
  State<AdjustmentManagementScreen> createState() => _AdjustmentManagementScreenState();
}

class _AdjustmentManagementScreenState extends State<AdjustmentManagementScreen> {
  late Future<List<Adjustment>> _adjustmentsFuture;
  late String _currentAccessToken;

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token;
    _adjustmentsFuture = _fetchAdjustments();
  }

  // CRITICAL: Headers depend on the mutable token state
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  // CRITICAL FIX: Reusable API Call Helper with Token Refresh/Retry
  Future<http.Response> _makeApiCall(String method, String url, {Map<String, dynamic>? payload, int retryCount = 0}) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    try {
      final currentHeaders = headers;
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
      final success = await widget.refreshTokenUtility(); // Attempt refresh

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() { // Update local token state
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        return _makeApiCall(method, url, payload: payload, retryCount: 1); // Retry
      }
    }
    return response;
  }

  // R - READ: Fetch Adjustments (Refactored to use _makeApiCall)
  Future<List<Adjustment>> _fetchAdjustments() async {
    try {
      // Assuming ApiService.getAdjustments was essentially a GET request to '$_API_BASE_URL/adjustments/'
      final res = await _makeApiCall('GET', '$_API_BASE_URL/adjustments/');

      if (res.statusCode == 401) {
        widget.handleUnauthorized();
        return [];
      }
      if (res.statusCode != 200) throw Exception('Failed to load adjustments: ${res.statusCode}');

      final data = json.decode(res.body);
      final List<Map<String, dynamic>> dataList = List<Map<String, dynamic>>.from(data);

      final List<Adjustment> allAdjustments = dataList.map((json) => Adjustment.fromJson(json)).toList();
      return allAdjustments.where((adj) => adj.shop == widget.shopId).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load adjustments: ${e.toString()}')),
        );
      }
      return [];
    }
  }

  // C/U - CREATE/UPDATE: Navigation handler
  void _openAdjustmentForm({Adjustment? adjustment}) async {
    final bool? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateAdjustmentScreen(
          token: _currentAccessToken, // Pass current token
          shopId: widget.shopId,
          initialAdjustment: adjustment,
          refreshTokenUtility: widget.refreshTokenUtility, // Pass utility
        ),
      ),
    );

    // If the form screen returns true, refresh the list.
    if (result == true) {
      // Re-initialize token state after successful refresh in child screen
      final prefs = await SharedPreferences.getInstance();
      _currentAccessToken = prefs.getString('accessToken') ?? '';

      setState(() {
        _adjustmentsFuture = _fetchAdjustments();
      });
    }
  }

  // D - DELETE: Delete an Adjustment (Refactored to use _makeApiCall)
  void _deleteAdjustment(int id) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this adjustment?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      // Assuming ApiService.deleteAdjustment was essentially a DELETE request to '$_API_BASE_URL/adjustments/$id/'
      final res = await _makeApiCall('DELETE', '$_API_BASE_URL/adjustments/$id/');

      if (res.statusCode == 401) return widget.handleUnauthorized(); // Failed after retry
      if (res.statusCode != 204) throw Exception('Deletion failed with status: ${res.statusCode}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adjustment deleted successfully!')),
        );
        setState(() {
          _adjustmentsFuture = _fetchAdjustments(); // Refresh the list
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting adjustment: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (rest of the build method is unchanged)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjustments Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _adjustmentsFuture = _fetchAdjustments()),
          ),
        ],
      ),
      body: FutureBuilder<List<Adjustment>>(
        future: _adjustmentsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No adjustments found. Tap + to add one.'));
          }

          final adjustments = snapshot.data!;
          final NumberFormat currencyFormatter = NumberFormat.simpleCurrency();

          return ListView.builder(
            itemCount: adjustments.length,
            itemBuilder: (context, index) {
              final adj = adjustments[index];
              final isIncome = adj.adjustmentType == 'GAIN'; // Use GAIN as per new logic

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isIncome ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(
                    isIncome ? Icons.attach_money : Icons.money_off,
                    color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                title: Text(
                  adj.description,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Date: ${DateFormat('MMM d, yyyy').format(adj.date)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${isIncome ? '+' : '-'} ${currencyFormatter.format(adj.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    // U - UPDATE/EDIT
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _openAdjustmentForm(adjustment: adj),
                    ),
                    // D - DELETE
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                      onPressed: () => _deleteAdjustment(adj.id!),
                    ),
                  ],
                ),
                onTap: () => _openAdjustmentForm(adjustment: adj),
              );
            },
          );
        },
      ),
      // C - CREATE: Floating Action Button
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAdjustmentForm(),
        tooltip: 'Add Adjustment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
// CRITICAL: Updated constructor to accept refresh logic
class CreateAdjustmentScreen extends StatefulWidget {
  final String token;
  final int shopId;
  final Adjustment? initialAdjustment;
  final RefreshTokenUtility refreshTokenUtility; // CRITICAL: Added utility

  const CreateAdjustmentScreen({
    super.key,
    required this.token,
    required this.shopId,
    required this.refreshTokenUtility,
    this.initialAdjustment,
  });

  @override
  State<CreateAdjustmentScreen> createState() => _CreateAdjustmentScreenState();
}
class _CreateAdjustmentScreenState extends State<CreateAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();

  late Adjustment _adjustmentData;
  bool _isLoading = false;
  late String _currentAccessToken; // CRITICAL: Mutable token state

  final List<Map<String, String>> djangoAdjustmentChoices = const [
    {'value': 'GAIN', 'text': 'Gain / Income ⬆️'},
    {'value': 'LOSS', 'text': 'Loss / Write-off 🔻'},
    {'value': 'CORRECTION', 'text': 'Correction ✏️'},
  ];

  @override
  void initState() {
    super.initState();
    _currentAccessToken = widget.token; // Initialize local token
    _adjustmentData = widget.initialAdjustment ??
        Adjustment(
          shop: widget.shopId,
          date: DateTime.now(),
          amount: 0.0,
          description: '',
          adjustmentType: 'LOSS',
        );
  }

  // CRITICAL: Headers depend on the mutable token state
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_currentAccessToken',
  };

  // CRITICAL FIX: Reusable API Call Helper with Token Refresh/Retry
  Future<http.Response> _makeApiCall(String method, String url, {Map<String, dynamic>? payload, int retryCount = 0}) async {
    final uri = Uri.parse(url);
    final body = payload != null ? jsonEncode(payload) : null;
    http.Response response;

    try {
      final currentHeaders = headers;
      switch (method) {
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
      final success = await widget.refreshTokenUtility(); // Attempt refresh

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        if (mounted) {
          setState(() { // Update local token state
            _currentAccessToken = prefs.getString('accessToken') ?? '';
          });
        }
        return _makeApiCall(method, url, payload: payload, retryCount: 1); // Retry
      }
    }
    return response;
  }

  Future<void> _selectDate() async {
    if (!mounted) return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _adjustmentData.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null && picked != _adjustmentData.date) {
      setState(() {
        _adjustmentData = Adjustment(
          id: _adjustmentData.id,
          shop: _adjustmentData.shop,
          date: picked,
          amount: _adjustmentData.amount,
          description: _adjustmentData.description,
          adjustmentType: _adjustmentData.adjustmentType,
        );
      });
    }
  }

  Future<void> _submitAdjustment() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoading = true);
    final isEditing = _adjustmentData.id != null;
    final payload = _adjustmentData.toJsonForCreation();

    try {
      final url = isEditing
          ? '$_API_BASE_URL/adjustments/${_adjustmentData.id!}/'
          : '$_API_BASE_URL/adjustments/';
      final method = isEditing ? 'PUT' : 'POST';

      // CRITICAL FIX: Use _makeApiCall
      final res = await _makeApiCall(method, url, payload: payload);

      if (res.statusCode == 401) {
        // If it still fails after refresh, the refresh utility handles navigation.
        throw Exception('Authentication failed. Please try again.');
      }
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('API Error: ${res.statusCode}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Adjustment ${isEditing ? 'updated' : 'recorded'} successfully!')),
        );
        // Return true to signal the list screen to refresh and update its token state
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (rest of the build method is unchanged)
    final title = widget.initialAdjustment == null ? 'Add New Adjustment' : 'Edit Adjustment';
    final isEditing = widget.initialAdjustment != null;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Date Picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Adjustment Date: ${DateFormat('EEEE, MMM d, yyyy').format(_adjustmentData.date)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
              ),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Adjustment Type Dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Type of Adjustment',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.swap_vert),
                ),
                value: _adjustmentData.adjustmentType,
                items: djangoAdjustmentChoices.map((choice) {
                  return DropdownMenuItem(
                    value: choice['value']!,
                    child: Text(choice['text']!),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    _adjustmentData = Adjustment(
                      id: _adjustmentData.id,
                      shop: _adjustmentData.shop,
                      date: _adjustmentData.date,
                      amount: _adjustmentData.amount,
                      description: _adjustmentData.description,
                      adjustmentType: newValue,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              // Amount Field
              TextFormField(
                initialValue: _adjustmentData.amount > 0 ? _adjustmentData.amount.toString() : '',
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'e.g., 50.00',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                  prefixIcon: Icon(Icons.monetization_on),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter an amount.';
                  final amount = double.tryParse(value);
                  if (amount == null) return 'Amount must be a valid number.';
                  return null;
                },
                onSaved: (value) {
                  _adjustmentData = Adjustment(
                    id: _adjustmentData.id,
                    shop: _adjustmentData.shop,
                    date: _adjustmentData.date,
                    amount: double.tryParse(value ?? '0') ?? 0.0,
                    description: _adjustmentData.description,
                    adjustmentType: _adjustmentData.adjustmentType,
                  );
                },
              ),
              const SizedBox(height: 16),

              // Description Field
              TextFormField(
                initialValue: _adjustmentData.description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g., Inventory shortage found during monthly count',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please provide a description.';
                  return null;
                },
                onSaved: (value) {
                  _adjustmentData = Adjustment(
                    id: _adjustmentData.id,
                    shop: _adjustmentData.shop,
                    date: _adjustmentData.date,
                    amount: _adjustmentData.amount,
                    description: value ?? '',
                    adjustmentType: _adjustmentData.adjustmentType,
                  );
                },
              ),
              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitAdjustment,
                icon: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isEditing ? Icons.save : Icons.add_circle_outline),
                label: Text(_isLoading ? 'SAVING...' : isEditing ? 'SAVE CHANGES' : 'RECORD ADJUSTMENT'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}