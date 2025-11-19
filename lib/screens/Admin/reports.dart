import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
// ADDED ICON IMPORT: font_awesome_flutter for more expressive icons
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../widgets/admin/sidebar.dart';
import '../../widgets/chart_widget.dart';
import '../home_screen.dart';
import 'emoloyee.dart'; // Assuming this is used or required elsewhere in your project
import 'package:fl_chart/fl_chart.dart';
// ============================
// 1. API Constants
// ============================
const String _API_BASE_URL = 'http://10.0.2.2:8000';
const String _REFRESH_URL = '$_API_BASE_URL/api/token/refresh/';

// ============================
// 2. Data Models (Kept as is - no changes needed here)
// ============================
class PLDetail {
  final String productName;
  final int sku;
  final int quantitySold;
  final double unitSalePrice;
  final double unitCogs;
  final int stockQuantity;
  final double revenue;
  final double avgMonthlySold;
  final String variantName;
  final int currentStock;
  final int totalSoldLast2Months;
  final int suggestedRestock;

  PLDetail({
    required this.productName,
    required this.sku,
    required this.quantitySold,
    required this.unitSalePrice,
    required this.unitCogs,
    required this.stockQuantity,
    required this.revenue,
    required this.avgMonthlySold,
    required this.variantName,
    required this.currentStock,
    required this.totalSoldLast2Months,
    required this.suggestedRestock,
  });

  factory PLDetail.fromJson(Map<String, dynamic> json) => PLDetail(
    productName: json['product_name'] ?? 'N/A',
    sku: json['sku'] != null ? int.tryParse(json['sku'].toString()) ?? 0 : 0,
    quantitySold: json['quantity_sold'] != null
        ? int.tryParse(json['quantity_sold'].toString()) ?? 0
        : 0,
    unitSalePrice: json['unit_sale_price'] != null
        ? double.tryParse(json['unit_sale_price'].toString()) ?? 0.0
        : 0.0,
    unitCogs: json['unit_cogs'] != null
        ? double.tryParse(json['unit_cogs'].toString()) ?? 0.0
        : 0.0,
    stockQuantity: json['stock_quantity'] != null
        ? int.tryParse(json['stock_quantity'].toString()) ?? 0
        : 0,
    revenue: json['revenue'] != null
        ? double.tryParse(json['revenue'].toString()) ?? 0.0
        : 0.0,
    avgMonthlySold: json['avg_monthly_sold'] != null
        ? (json['avg_monthly_sold'] is int
              ? (json['avg_monthly_sold'] as int).toDouble()
              : json['avg_monthly_sold'] as double)
        : 0.0,
    variantName: json['variant_name'] ?? 'N/A',
    currentStock: json['current_stock'] != null
        ? int.tryParse(json['current_stock'].toString()) ?? 0
        : 0,
    totalSoldLast2Months: json['total_sold_last_2_months'] != null
        ? int.tryParse(json['total_sold_last_2_months'].toString()) ?? 0
        : 0,
    suggestedRestock: json['suggested_restock'] != null
        ? (json['suggested_restock'] is int
              ? json['suggested_restock'] as int
              : (json['suggested_restock'] as double).round())
        : 0,
  );

  PLDetail copyWith({int? suggestedRestock}) {
    return PLDetail(
      productName: productName,
      sku: sku,
      quantitySold: quantitySold,
      unitSalePrice: unitSalePrice,
      unitCogs: unitCogs,
      stockQuantity: stockQuantity,
      revenue: revenue,
      avgMonthlySold: avgMonthlySold,
      variantName: variantName,
      currentStock: currentStock,
      totalSoldLast2Months: totalSoldLast2Months,
      suggestedRestock: suggestedRestock ?? this.suggestedRestock,
    );
  }
}

class WasteDetail {
  final String date;
  final String productName;
  final int sku;
  final String category;
  final int quantity;
  final double unitPurchasePrice;
  final double lossValue;
  final String reason;

  WasteDetail.fromJson(Map<String, dynamic> json)
    : date = json['date'] ?? 'N/A',
      productName = json['product_name'] ?? 'N/A',
      sku = json['sku'] != null ? int.tryParse(json['sku'].toString()) ?? 0 : 0,
      category = json['category'] ?? 'N/A',
      quantity = json['quantity'] != null
          ? int.tryParse(json['quantity'].toString()) ?? 0
          : 0,
      unitPurchasePrice = json['unit_purchase_price'] != null
          ? double.tryParse(json['unit_purchase_price'].toString()) ?? 0.0
          : 0.0,
      lossValue = json['waste_value'] != null
          ? double.tryParse(json['waste_value'].toString()) ?? 0.0
          : (json['loss_value'] != null
                ? double.tryParse(json['loss_value'].toString()) ?? 0.0
                : 0.0),
      reason = json['reason'] ?? 'N/A';
}

class ReportData {
  final double totalRevenue;
  final double totalCogs;
  final double totalWasteLoss;
  final double totalExpenses;
  final double totalAdjustments;
  final double grossProfit;
  final double netProfit;
  final List<WasteDetail> wasteDetails;
  final List<PLDetail> plDetails;
  final List<Map<String, dynamic>> monthlyComparison;

  ReportData.fromJson(Map<String, dynamic> json)
      : totalRevenue = _parseDouble(json['total_revenue']),
        totalCogs = _parseDouble(json['total_cogs']),
        totalWasteLoss = _parseDouble(json['total_waste_loss']),
        totalExpenses = _parseDouble(json['total_expenses']),
        totalAdjustments = _parseDouble(json['total_adjustments']),
        grossProfit = _parseDouble(json['gross_profit']),
        netProfit = _parseDouble(json['net_profit']),
        wasteDetails = (json['waste_details'] as List?)
            ?.map((i) => WasteDetail.fromJson(i as Map<String, dynamic>))
            .toList() ??
            [],
        plDetails = (json['pl_details'] as List?)
            ?.map((i) => PLDetail.fromJson(i as Map<String, dynamic>))
            .toList() ??
            [],
        monthlyComparison = (json['monthly_comparison'] as List?)
            ?.whereType<Map>() // filter non-maps
            .map((i) => Map<String, dynamic>.from(i))
            .toList() ??
            [];

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}



// ============================
// 3. API Service (Updated for token retry logic)
// ============================

/// **IMPORTANT**: This wrapper function cannot contain the refresh logic itself
/// because the access token is managed by the StatefulWidget. The retry logic
/// must be handled within the State class, where the token state can be updated.
///
/// We will keep this function simple and move the refresh/retry logic into
/// `_ReportsScreenState`.
Future<http.Response> _makeReportCall({
  required String period,
  required String accessToken,
  required int shopId,
  String? customStartDate,
  String? customEndDate,
}) async {
  // Make sure /api is included
  String url =
      '$_API_BASE_URL/reports/shop_report/?shop_id=$shopId&period=$period';

  if (period == 'custom') {
    if (customStartDate != null && customEndDate != null) {
      url += '&start_date=$customStartDate&end_date=$customEndDate';
    } else {
      throw Exception('Custom period requires start_date and end_date.');
    }
  }

  return http.get(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    },
  );
}


// ============================
// 4. ReportsScreen Widget
// ============================

class ReportsScreen extends StatefulWidget {
  final int shopId;
  const ReportsScreen({super.key, required this.shopId});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _accessToken = '';
  String _refreshToken = '';

  String _selectedPeriodKey = 'daily';
  Map<String, double> _salesSummaries = {
    'daily': 0.0,
    'monthly': 0.0,
    'yearly': 0.0,
  };
  double _totalSalesAllTime = 1.0;

  ReportData? _currentReportData;
  bool _isLoading = true;
  String _errorMessage = '';

  final Map<String, String> _periodMap = {
    'daily': 'Today',
    'monthly': 'This Month',
    'yearly': 'This Year',
  };

  // --- P&L Dropdown ---
  String _selectedPLPeriod = 'Monthly';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadTokensAndFetchData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<bool> _refreshTokenUtility() async {
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
      if (mounted) setState(() => _accessToken = newAccessToken);
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

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      String newPeriod = _tabController.index == 0
          ? 'daily'
          : _tabController.index == 1
          ? 'monthly'
          : 'yearly';
      if (newPeriod != _selectedPeriodKey) _fetchCurrentReport(newPeriod);
    }
  }

  Future<void> _loadTokensAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('accessToken') ?? '';
    _refreshToken = prefs.getString('refreshToken') ?? '';
    if (_accessToken.isEmpty || _refreshToken.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    await _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await _fetchSalesSummaries();
    await _fetchCurrentReport(_selectedPeriodKey);
  }

  // Future<http.Response> _makeReportCall({
  //   required String period,
  //   required String accessToken,
  //   required int shopId,
  //   String? customStartDate,
  //   String? customEndDate,
  // }) async {
  //   String url =
  //       '$_API_BASE_URL/reports/shop_report/?shop_id=$shopId&period=$period';
  //   if (period == 'custom' &&
  //       customStartDate != null &&
  //       customEndDate != null) {
  //     url += '&start_date=$customStartDate&end_date=$customEndDate';
  //   }
  //   return http.get(
  //     Uri.parse(url),
  //     headers: {
  //       'Content-Type': 'application/json',
  //       'Authorization': 'Bearer $accessToken',
  //     },
  //   );
  // }

  Future<void> _fetchSalesSummaries() async {
    final int shopId = widget.shopId;

    Future<ReportData> _fetchAndParse(String period) async {
      http.Response response = await _makeReportCall(
        period: period,
        accessToken: _accessToken,
        shopId: shopId,
      );
      if (response.statusCode == 401 && await _refreshTokenUtility()) {
        response = await _makeReportCall(
          period: period,
          accessToken: _accessToken,
          shopId: shopId,
        );
      }
      if (response.statusCode == 200)
        return ReportData.fromJson(json.decode(response.body));
      throw Exception('${response.statusCode} - ${response.body}');
    }

    try {
      final results = await Future.wait([
        _fetchAndParse('daily'),
        _fetchAndParse('monthly'),
        _fetchAndParse('yearly'),
      ]);
      if (!mounted) return;
      setState(() {
        _salesSummaries = {
          'daily': results[0].totalRevenue,
          'monthly': results[1].totalRevenue,
          'yearly': results[2].totalRevenue,
        };
        _totalSalesAllTime = _salesSummaries.values.reduce((a, b) => a + b);
        if (_totalSalesAllTime == 0) _totalSalesAllTime = 1.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to fetch sales summaries: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCurrentReport(String periodKey, {
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _selectedPeriodKey = periodKey;
    });

    // For 'custom', ensure start and end are provided
    if (periodKey == 'custom' && (customStart == null || customEnd == null)) {
      setState(() {
        _errorMessage =
        'Please select a valid start and end date for custom period.';
        _isLoading = false;
      });
      return;
    }

    try {
      var response = await _makeReportCall(
        period: periodKey,
        accessToken: _accessToken,
        shopId: widget.shopId,
        customStartDate: customStart != null
            ? DateFormat('yyyy-MM-dd').format(customStart)
            : null,
        customEndDate: customEnd != null
            ? DateFormat('yyyy-MM-dd').format(customEnd)
            : null,
      );

      // Retry with refreshed token if unauthorized
      if (response.statusCode == 401 && await _refreshTokenUtility()) {
        response = await _makeReportCall(
          period: periodKey,
          accessToken: _accessToken,
          shopId: widget.shopId,
          customStartDate: customStart != null
              ? DateFormat('yyyy-MM-dd').format(customStart)
              : null,
          customEndDate: customEnd != null
              ? DateFormat('yyyy-MM-dd').format(customEnd)
              : null,
        );
      }

      if (response.statusCode == 200) {
        final data = ReportData.fromJson(json.decode(response.body));
        if (!mounted) return;
        setState(() {
          _currentReportData = data;
          _isLoading = false;
        });
      } else {
        throw Exception('${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;

      // Redirect to HomeScreen immediately on failure
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) =>
        const HomeScreen(role: '', shopId: null, token: '',)),
            (Route<dynamic> route) => false,
      );
    }
  }

  double get _displayedValue => _salesSummaries[_selectedPeriodKey] ?? 0.0;

  String get _displayedPeriodTitle =>
      _periodMap[_selectedPeriodKey] ?? _selectedPeriodKey;

  Future<DateTimeRange?> _pickCustomDateRange() async {
    final now = DateTime.now();
    return await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
    );
  }

  // Fetch best-selling products
  Future<List<PLDetail>> fetchBestSellingProducts() async {
    final response = await http.get(
      Uri.parse('http://10.0.2.2:8000/api/orders/best-selling/'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonData = json.decode(response.body);
      final List bestSelling = jsonData['best_selling'] ?? [];
      return bestSelling.map((e) => PLDetail.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch best-selling products');
    }
  }

  // Fetch low-selling products
  Future<List<PLDetail>> fetchLowSellingProducts() async {
    final response = await http.get(
      Uri.parse('http://10.0.2.2:8000/api/orders/best-selling/'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> jsonData = json.decode(response.body);
      final List lowSelling = jsonData['low_selling'] ?? [];
      return lowSelling.map((e) => PLDetail.fromJson(e)).toList();
    } else {
      throw Exception('Failed to fetch low-selling products');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Reports")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Error: $_errorMessage',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business Reports အစီရင်ခံစာ"),
        leading: Builder(
          builder: (context) =>
              IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(FontAwesomeIcons.chartLine), text: "Sales အ‌ရောင်း"),
            Tab(icon: Icon(FontAwesomeIcons.trashCan),
                text: "Waste အလေအလွှင့်"),
            Tab(icon: Icon(FontAwesomeIcons.handHoldingDollar),
                text: "P&L အမြတ်/အရှုံး"),
          ],
        ),
      ),
      drawer: const SideBar(selectedPage: 'Reports'),
      body: _isLoading && _currentReportData == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildSalesTab(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildWasteTab(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildProfitLossTab(),
          ),
        ],
      ),
    );
  }

  // =========================
  // SALES TAB
  // =========================
  Widget _buildSalesTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Your period selection buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: _periodMap.keys.map((periodKey) {
              final bool isSelected = periodKey == _selectedPeriodKey;
              final Color color = periodKey == 'daily'
                  ? Colors.teal
                  : periodKey == 'monthly'
                  ? Colors.indigo
                  : Colors.deepPurple;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                child: ElevatedButton.icon(
                  icon: Icon(
                    periodKey == 'daily'
                        ? Icons.today
                        : periodKey == 'monthly'
                        ? Icons.calendar_month
                        : Icons.bar_chart,
                    size: 20,
                  ),
                  label: Text(
                    _periodMap[periodKey]!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: isSelected ? 4 : 0,
                    backgroundColor: isSelected ? color : Colors.white,
                    foregroundColor: isSelected ? Colors.white : color,
                    side: BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (!isSelected) _fetchCurrentReport(periodKey);
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          _buildCircle(
            _displayedValue,
            _displayedPeriodTitle,
            _selectedPeriodKey,
          ),
          const SizedBox(height: 24),

          // Best-selling products
          FutureBuilder<List<PLDetail>>(
            future: fetchBestSellingProducts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No best-selling products"));
              }
              return _buildPLTable(
                snapshot.data!,
                title: "အရောင်းရဆုံး ပစ္စည်းများ ",
                descending: true, // highest sold first
                limit: 5,
              );
            },
          ),
          const SizedBox(height: 24),

          // Low-selling products
          FutureBuilder<List<PLDetail>>(
            future: fetchLowSellingProducts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("No low-selling products"));
              }
              return _buildPLTable(
                snapshot.data!,
                title: "ရောင်းအားနည်း ပစ္စည်းများ",
                descending: false, // lowest sold first
                limit: 5,
              );
            },
          ),

          const SizedBox(height: 24),

          // Sales record table
          _buildSalesRecordTable(
            _displayedPeriodTitle,
            _currentReportData?.plDetails ?? [],
          ),
        ],
      ),
    );
  }

  Widget _buildPLTable(List<PLDetail> items, {
    String title = "Products",
    bool descending = true, // true = highest first, false = lowest first
    int limit = 5,
  }) {
    if (items.isEmpty) {
      return const Center(child: Text("No product sales data available."));
    }

    // Sort according to descending flag
    final sortedItems = List<PLDetail>.from(items)
      ..sort(
            (a, b) =>
        descending
            ? b.totalSoldLast2Months.compareTo(a.totalSoldLast2Months)
            : a.totalSoldLast2Months.compareTo(b.totalSoldLast2Months),
      );

    // Take top N items
    final topItems = sortedItems.take(limit).toList();

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateColor.resolveWith(
                      (states) => Colors.orange.shade50,
                ),
                columns: const [
                  DataColumn(label: Text("Variant")),
                  DataColumn(label: Text("Total Sold (2 mo)")),
                  DataColumn(label: Text("Avg Monthly Sold")),
                  DataColumn(label: Text("Suggested Restock")),
                  DataColumn(label: Text("Remaining Stock")),
                ],
                rows: topItems.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text(item.variantName ?? 'N/A')),
                      DataCell(Text(item.totalSoldLast2Months.toString())),
                      DataCell(Text(item.avgMonthlySold.toStringAsFixed(0))),
                      DataCell(
                        Text(
                          item.suggestedRestock.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: item.suggestedRestock > 0
                                ? Colors.orange.shade700
                                : Colors.grey,
                          ),
                        ),
                      ),
                      DataCell(Text(item.currentStock.toString())),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircle(double value,
      String title,
      String periodKey, {
        double? avgValue,
      }) {
    // Calculate progress for the circular bar
    final progress = _totalSalesAllTime > 0 ? value / _totalSalesAllTime : 0.0;

    // Calculate growth percentage vs average
    double growthPercent = 0;
    if (avgValue != null && avgValue > 0) {
      growthPercent = ((value - avgValue) / avgValue) * 100;
    }

    // Color based on period
    final Color color = periodKey == 'daily'
        ? Colors.teal
        : periodKey == 'monthly'
        ? Colors.indigo
        : Colors.deepPurple;

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 12,
                color: color,
                backgroundColor: color.withOpacity(0.3),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title
                      .split(' ')
                      .last,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "\$${value.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                if (avgValue != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        growthPercent >= 0
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        color: growthPercent >= 0 ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${growthPercent.abs().toStringAsFixed(1)}%",
                        style: TextStyle(
                          color: growthPercent >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesRecordTable(String title, List<PLDetail> items) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$title အရောင်းပစ္စည်းများ",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateColor.resolveWith(
                      (states) => Colors.indigo.shade50,
                ),
                columns: const [
                  DataColumn(
                    label: Text(
                      "Product",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Qty Sold",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Sale Price",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Revenue",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: items.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text(item.productName)),
                      DataCell(Text(item.quantitySold.toString())),
                      DataCell(
                        Text("\$${item.unitSalePrice.toStringAsFixed(2)}"),
                      ),
                      DataCell(
                        Text(
                          "\$${item.revenue.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // WASTE TAB
  // =========================
  Widget _buildWasteTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildWasteSummaryCard(),
          const SizedBox(height: 24),
          _buildWasteTable(),
        ],
      ),
    );
  }

  Widget _buildWasteSummaryCard() {
    final totalWasteLoss = _currentReportData?.totalWasteLoss ?? 0.0;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  FontAwesomeIcons.circleExclamation,
                  color: Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  "${_displayedPeriodTitle} လေလွှင့်စာရင်း",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              "ဆုံးရှုံးတန်ဖိုး(at COGS):",
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              "\$${totalWasteLoss.toStringAsFixed(2)}",
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWasteTable() {
    final items = _currentReportData?.wasteDetails ?? [];
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: MaterialStateColor.resolveWith(
                  (states) => Colors.red.shade50,
            ),
            columns: const [
              DataColumn(
                label: Text(
                  'Date',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Product',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Qty',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Unit COGS',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'တန်ဖိုး',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'အကြောင်းအရင်း',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            rows: items
                .map(
                  (item) =>
                  DataRow(
                    cells: [
                      DataCell(Text(item.date)),
                      DataCell(Text(item.productName)),
                      DataCell(Text(item.category)),
                      DataCell(Text(item.quantity.toString())),
                      DataCell(
                        Text("\$${item.unitPurchasePrice.toStringAsFixed(2)}"),
                      ),
                      DataCell(
                        Text(
                          "\$${item.lossValue.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      DataCell(Text(item.reason)),
                    ],
                  ),
            )
                .toList(),
          ),
        ),
      ),
    );
  }

  // =========================
  // P&L TAB
  // =========================
  Widget _buildProfitLossTab() {
    if (_currentReportData == null) {
      return Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : const Text("No financial data available for this period."),
      );
    }

    final data = _currentReportData!;

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // --- Use backend totals ---
    final revenue = parseDouble(data.totalRevenue);
    final cogs = parseDouble(data.totalCogs);
    final wasteLoss = parseDouble(data.totalWasteLoss);
    final operatingExpenses = parseDouble(data.totalExpenses);
    final otherAdjustments = parseDouble(data.totalAdjustments);

    final grossProfit = parseDouble(data.grossProfit);
    final netProfit = parseDouble(data.netProfit);
    final operatingProfit = grossProfit - operatingExpenses;

    final rows = [
      {"label": "Revenue", "amount": revenue, "type": "income"},
      {"label": "COGS", "amount": cogs, "type": "expense"},
      {"label": "Waste", "amount": wasteLoss, "type": "expense"},
      {"label": "Gross Profit", "amount": grossProfit, "type": "profit"},
      {
        "label": "Operating Expenses",
        "amount": operatingExpenses,
        "type": "expense"
      },
      {
        "label": "Operating Profit",
        "amount": operatingProfit,
        "type": "profit"
      },
      {
        "label": "Other Adjustments",
        "amount": otherAdjustments,
        "type": "adjustment"
      },
      {"label": "Net Profit", "amount": netProfit, "type": "profit"},
    ];

    // --- Main Profit/Loss Chart ---
    final mainBarGroups = <BarChartGroupData>[
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(
            toY: revenue,
            gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade300]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(show: true, toY: 0),
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(
            toY: cogs,
            gradient: LinearGradient(
                colors: [Colors.orange.shade600, Colors.orange.shade300]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          BarChartRodData(
            toY: wasteLoss,
            gradient: LinearGradient(
                colors: [Colors.red.shade400, Colors.red.shade200]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          BarChartRodData(
            toY: grossProfit >= 0 ? grossProfit : 0,
            gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.green.shade300]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(
            toY: operatingExpenses,
            gradient: LinearGradient(
                colors: [Colors.red.shade300, Colors.red.shade100]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          BarChartRodData(
            toY: operatingProfit >= 0 ? operatingProfit : 0,
            gradient: LinearGradient(
                colors: [Colors.green.shade700, Colors.green.shade400]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
      BarChartGroupData(
        x: 3,
        barRods: [
          BarChartRodData(
            toY: otherAdjustments,
            gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade200]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
          BarChartRodData(
            toY: netProfit >= 0 ? netProfit : 0,
            gradient: LinearGradient(
                colors: [Colors.green.shade900, Colors.green.shade600]),
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    ];

    // --- Monthly Comparison Chart ---
    final monthly = (data.monthlyComparison ?? []) as List<dynamic>;
    Widget monthlyChartWidget;
    if (monthly.isNotEmpty) {
      final normalized = monthly.map<Map<String, dynamic>>((e) {
        if (e is Map<String, dynamic>) {
          return {
            'month': e['month_name'] ?? e['month'] ?? 'Unknown',
            'revenue': parseDouble(e['revenue']),
            'gross_profit': parseDouble(e['gross_profit']),
            'net_profit': parseDouble(e['net_profit']),
          };
        }
        return {};
      }).toList();

      final months = normalized.map((e) => e['month'] as String).toList();
      final revenueList = normalized
          .map((e) => e['revenue'] as double)
          .toList();
      final grossList = normalized
          .map((e) => e['gross_profit'] as double)
          .toList();
      final netList = normalized.map((e) => e['net_profit'] as double).toList();

      final monthlyBarGroups = <BarChartGroupData>[];
      for (var i = 0; i < months.length; i++) {
        monthlyBarGroups.add(
          BarChartGroupData(
            x: i,
            barsSpace: 4,
            barRods: [
              BarChartRodData(
                toY: revenueList[i],
                gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade200]),
                width: 12,
              ),
              BarChartRodData(
                toY: grossList[i],
                gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade200]),
                width: 12,
              ),
              BarChartRodData(
                toY: netList[i],
                gradient: LinearGradient(
                    colors: [Colors.purple.shade400, Colors.purple.shade200]),
                width: 12,
              ),
            ],
          ),
        );
      }

      monthlyChartWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            "📅 Monthly Comparison",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: BarChart(
                  BarChartData(
                    barGroups: monthlyBarGroups,
                    groupsSpace: 20,
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true, reservedSize: 50),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= months.length)
                              return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(months[idx],
                                  style: const TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _LegendBox(color: Colors.blue, label: "Revenue"),
              SizedBox(width: 12),
              _LegendBox(color: Colors.green, label: "Gross Profit"),
              SizedBox(width: 12),
              _LegendBox(color: Colors.purple, label: "Net Profit"),
            ],
          ),
        ],
      );
    } else {
      monthlyChartWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SizedBox(height: 20),
          Text(
            "📅 Monthly Comparison",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text("No monthly data available."),
        ],
      );
    }

    // --- Main UI ---
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Period Selector ---
          Row(
            children: [
              const Text("Select Period:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 16),
              ToggleButtons(
                borderRadius: BorderRadius.circular(8),
                isSelected: ["Daily", "Monthly", "Yearly", "Custom"].map((
                    p) => _selectedPLPeriod == p).toList(),
                onPressed: (idx) async {
                  final p = ["Daily", "Monthly", "Yearly", "Custom"][idx];
                  if (p == "Custom") {
                    final picked = await _pickCustomDateRange();
                    if (picked != null) {
                      setState(() {
                        _selectedPLPeriod = p;
                        _customStartDate = picked.start;
                        _customEndDate = picked.end;
                      });
                      await _fetchCurrentReport(
                        'custom',
                        customStart: _customStartDate,
                        customEnd: _customEndDate,
                      );
                    }
                  } else {
                    setState(() {
                      _selectedPLPeriod = p;
                      _customStartDate = null;
                      _customEndDate = null;
                    });
                    await _fetchCurrentReport(p.toLowerCase());
                  }
                },
                children: ["Daily", "Monthly", "Yearly", "Custom"].map((p) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Text(p),
                    )).toList(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // --- Main Profit/Loss Chart ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 520,
              height: 270,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: BarChart(
                    BarChartData(
                      barGroups: mainBarGroups,
                      gridData: FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(
                            showTitles: true, reservedSize: 50)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final labels = [
                                "Revenue",
                                "Gross",
                                "Operating",
                                "Net"
                              ];
                              int index = value.toInt();
                              if (index < 0 || index >= labels.length)
                                return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(labels[index],
                                    style: const TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Summary Boxes ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: rows.map((row) {
                final label = row['label'] as String;
                final amount = row['amount'] as double;
                final type = row['type'] as String;

                Color amountColor;
                if (type == 'profit') {
                  amountColor =
                  amount < 0 ? Colors.red.shade700 : Colors.green.shade700;
                } else if (type == 'expense') {
                  amountColor = Colors.red.shade600;
                } else {
                  amountColor = Colors.black87;
                }

                return Container(
                  width: 180,
                  margin: const EdgeInsets.only(right: 14),
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontWeight: type == 'profit'
                          ? FontWeight.bold
                          : FontWeight.w600,
                          fontSize: 14,
                          color: Colors.grey.shade800)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text("\$${amount.toStringAsFixed(2)}",
                              style: TextStyle(color: amountColor,
                                  fontWeight: type == 'profit'
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 16)),
                          const SizedBox(width: 6),
                          Icon(amount >= 0 ? Icons.trending_up : Icons
                              .trending_down,
                              color: amount >= 0 ? Colors.green : Colors.red,
                              size: 18),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 3,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(colors: [
                            amountColor.withOpacity(0.5),
                            amountColor.withOpacity(0.1)
                          ]),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // --- Monthly Comparison ---
          monthlyChartWidget,
        ],
      ),
    );
  }
}
// --- Small Legend Helper Widget ---
  class _LegendBox extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendBox({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
  return Row(
  children: [
  Container(width: 14, height: 14, color: color),
  const SizedBox(width: 6),
  Text(label, style: const TextStyle(fontSize: 12)),
  ],
  );
  }
  }
