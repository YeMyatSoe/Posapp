import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
// ADDED ICON IMPORT: font_awesome_flutter for more expressive icons
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../widgets/admin/sidebar.dart';
import '../../widgets/chart_widget.dart';
import 'emoloyee.dart'; // Assuming this is used or required elsewhere in your project

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
  final int wasteQty;
  final double wasteLoss;
  final double revenue;
  final double cogs;
  final double profit;

  PLDetail.fromJson(Map<String, dynamic> json)
      : productName = json['product_name'] ?? 'N/A',
        sku = json['sku'] != null ? int.tryParse(json['sku'].toString()) ?? 0 : 0,
        quantitySold = json['quantity_sold'] != null ? int.tryParse(json['quantity_sold'].toString()) ?? 0 : 0,
        unitSalePrice = json['unit_sale_price'] != null ? double.tryParse(json['unit_sale_price'].toString()) ?? 0.0 : 0.0,
        unitCogs = json['unit_cogs'] != null ? double.tryParse(json['unit_cogs'].toString()) ?? 0.0 : 0.0,
        wasteQty = json['waste_qty'] != null ? int.tryParse(json['waste_qty'].toString()) ?? 0 : 0,
        wasteLoss = json['waste_loss'] != null ? double.tryParse(json['waste_loss'].toString()) ?? 0.0 : 0.0,
        revenue = json['revenue'] != null ? double.tryParse(json['revenue'].toString()) ?? 0.0 : 0.0,
        cogs = json['cogs'] != null ? double.tryParse(json['cogs'].toString()) ?? 0.0 : 0.0,
        profit = json['profit'] != null ? double.tryParse(json['profit'].toString()) ?? 0.0 : 0.0;
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
        quantity = json['quantity'] != null ? int.tryParse(json['quantity'].toString()) ?? 0 : 0,
        unitPurchasePrice = json['unit_purchase_price'] != null ? double.tryParse(json['unit_purchase_price'].toString()) ?? 0.0 : 0.0,
        lossValue = json['waste_value'] != null
            ? double.tryParse(json['waste_value'].toString()) ?? 0.0
            : (json['loss_value'] != null ? double.tryParse(json['loss_value'].toString()) ?? 0.0 : 0.0),
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

  ReportData.fromJson(Map<String, dynamic> json)
      : totalRevenue = json['total_revenue'] != null ? double.tryParse(json['total_revenue'].toString()) ?? 0.0 : 0.0,
        totalCogs = json['total_cogs'] != null ? double.tryParse(json['total_cogs'].toString()) ?? 0.0 : 0.0,
        totalWasteLoss = json['total_waste_loss'] != null ? double.tryParse(json['total_waste_loss'].toString()) ?? 0.0 : 0.0,
        totalExpenses = json['total_expenses'] != null ? double.tryParse(json['total_expenses'].toString()) ?? 0.0 : 0.0,
        totalAdjustments = json['total_adjustments'] != null ? double.tryParse(json['total_adjustments'].toString()) ?? 0.0 : 0.0,
        grossProfit = json['gross_profit'] != null ? double.tryParse(json['gross_profit'].toString()) ?? 0.0 : 0.0,
        netProfit = json['net_profit'] != null ? double.tryParse(json['net_profit'].toString()) ?? 0.0 : 0.0,
        wasteDetails = (json['waste_details'] as List?)?.map((i) => WasteDetail.fromJson(i as Map<String, dynamic>)).toList() ?? [],
        plDetails = (json['pl_details'] as List?)?.map((i) => PLDetail.fromJson(i as Map<String, dynamic>)).toList() ?? [];
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
  String url = '$_API_BASE_URL/reports/shop_report/?shop_id=$shopId&period=$period';

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

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _accessToken = '';
  String _refreshToken = ''; // Added to hold the refresh token

  String _selectedPeriodKey = 'daily';
  Map<String, double> _salesSummaries = {'daily': 0.0, 'monthly': 0.0, 'yearly': 0.0};
  double _totalSalesAllTime = 1.0;

  ReportData? _currentReportData;
  bool _isLoading = true;
  String _errorMessage = '';

  final Map<String, String> _periodMap = {
    'daily': 'Today',
    'monthly': 'This Month',
    'yearly': 'This Year',
  };

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

  // REUSABLE TOKEN REFRESH UTILITY (Added)
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

      if (mounted) {
        setState(() {
          _accessToken = newAccessToken; // Update local state for subsequent calls
        });
      }
      return true;
    } else {
      // Refresh failed (Refresh Token expired). Force re-login.
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

  void _handleTabChange() {
    // Only fetch if the tab index actually changed (not just scrolling animation)
    if (!_tabController.indexIsChanging) {
      String newPeriod = _tabController.index == 0
          ? 'daily'
          : _tabController.index == 1
          ? 'monthly'
          : 'yearly';
      if (newPeriod != _selectedPeriodKey) {
        _fetchCurrentReport(newPeriod);
      }
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

  // FETCH SALES SUMMARIES (Updated with Refresh Logic)
  Future<void> _fetchSalesSummaries() async {
    final int shopId = widget.shopId;

    Future<ReportData> _fetchAndParse(String period) async {
      http.Response response = await _makeReportCall(
        period: period,
        accessToken: _accessToken,
        shopId: shopId,
      );

      // Check for 401 and attempt refresh
      if (response.statusCode == 401 && await _refreshTokenUtility()) {
        // Retry call with new Access Token
        response = await _makeReportCall(
          period: period,
          accessToken: _accessToken,
          shopId: shopId,
        );
      }

      if (response.statusCode == 200) {
        return ReportData.fromJson(json.decode(response.body));
      } else if (response.statusCode == 401) {
        // Refresh failed or unauthorized after refresh (should be handled by utility)
        throw Exception('Unauthorized access. Please relogin.');
      } else {
        throw Exception('${response.statusCode} - ${response.body}');
      }
    }

    try {
      final dailyFuture = _fetchAndParse('daily');
      final monthlyFuture = _fetchAndParse('monthly');
      final yearlyFuture = _fetchAndParse('yearly');

      final results = await Future.wait([dailyFuture, monthlyFuture, yearlyFuture]);
      final dailyReport = results[0];
      final monthlyReport = results[1];
      final yearlyReport = results[2];

      if (!mounted) return;

      setState(() {
        _salesSummaries = {
          'daily': dailyReport.totalRevenue,
          'monthly': monthlyReport.totalRevenue,
          'yearly': yearlyReport.totalRevenue,
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

  // FETCH CURRENT REPORT (Updated with Refresh Logic)
  Future<void> _fetchCurrentReport(String periodKey) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _selectedPeriodKey = periodKey;
    });

    try {
      http.Response response = await _makeReportCall(
        period: periodKey,
        accessToken: _accessToken,
        shopId: widget.shopId,
      );

      // Check for 401 and attempt refresh
      if (response.statusCode == 401 && await _refreshTokenUtility()) {
        // Retry call with new Access Token
        response = await _makeReportCall(
          period: periodKey,
          accessToken: _accessToken,
          shopId: widget.shopId,
        );
      }

      if (response.statusCode == 200) {
        final data = ReportData.fromJson(json.decode(response.body));
        if (!mounted) return;
        setState(() {
          _currentReportData = data;
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        // Handle case where refresh failed but utility didn't redirect (e.g., initial call was 401)
        throw Exception('Unauthorized. Please relogin.');
      }
      else {
        throw Exception('${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentReportData = null;
        _errorMessage = 'Failed to load report for $periodKey: $e';
        _isLoading = false;
      });
    }
  }

  double get _displayedValue => _salesSummaries[_selectedPeriodKey] ?? 0.0;
  String get _displayedPeriodTitle => _periodMap[_selectedPeriodKey] ?? _selectedPeriodKey;

  // Location: _ReportsScreenState.build(BuildContext context)

  @override
  Widget build(BuildContext context) {
    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Reports")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error: $_errorMessage\nCheck API URL, shop ID, and server.',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    // 1. Center the content on large screens
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          // 👇 SETTING A STRICTER, SMALLER MAX WIDTH (600px)
          maxWidth: 600,
        ),
        // 2. The main Scaffold is contained within the constraint
        child: Scaffold(
          appBar: AppBar(
            title: const Text("Business Reports"),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            // actions: [
            //   IconButton(
            //     icon: const Icon(Icons.settings_outlined),
            //     onPressed: () {
            //       // TODO: Implement settings/filter logic
            //     },
            //   ),
            // ],
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                // color: Theme.of(context).primaryColor,
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(width: 3.0, color: Theme.of(context).colorScheme.secondary),
                insets: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
              tabs: const [
                Tab(icon: Icon(FontAwesomeIcons.chartLine, size: 20), text: "Sales"),
                Tab(icon: Icon(FontAwesomeIcons.trashCan, size: 20), text: "Waste"),
                Tab(icon: Icon(FontAwesomeIcons.handHoldingDollar, size: 20), text: "P&L"),
              ],
            ),
          ),
          drawer: const SideBar(selectedPage: 'Reports'),
          body: _isLoading && _currentReportData == null
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
            controller: _tabController,
            children: [
              _buildSalesTab(),
              _buildWasteTab(),
              _buildProfitLossTab(),
            ],
          ),
        ),
      ),
    );
  }

  // ====================
  // Sales Tab
  // ====================
  Widget _buildSalesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBarColumn()),
              const SizedBox(width: 16),
              // Moved circle widget to the top for prominence
              _buildCircle(_displayedValue, _displayedPeriodTitle, _selectedPeriodKey),
            ],
          ),
          const SizedBox(height: 24),
          _buildSalesRecordTable(_displayedPeriodTitle, _currentReportData?.plDetails ?? []),
        ],
      ),
    );
  }

  Widget _buildBarColumn() {
    return Column(
      children: _salesSummaries.keys.map((periodKey) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8), // Reduced bottom padding
          child: _buildBarCard(
              _periodMap[periodKey]!,
              _salesSummaries[periodKey]!,
              periodKey == 'daily' ? Colors.teal : (periodKey == 'monthly' ? Colors.indigo : Colors.deepPurple), // Changed colors
              periodKey),
        );
      }).toList(),
    );
  }

  Widget _buildBarCard(String title, double value, Color color, String periodKey) {
    bool isSelected = periodKey == _selectedPeriodKey;

    return GestureDetector(
      onTap: () {
        if (periodKey != _selectedPeriodKey) _fetchCurrentReport(periodKey);
      },
      child: AnimatedContainer( // Use AnimatedContainer for smooth transition
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: color)),
                Icon(
                  periodKey == 'daily' ? Icons.today : (periodKey == 'monthly' ? Icons.calendar_month : Icons.calendar_today),
                  color: color,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text("\$${value.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value / _totalSalesAllTime,
                minHeight: 10,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircle(double value, String title, String periodKey) {
    final progress = _totalSalesAllTime > 1.0 ? value / _totalSalesAllTime : 0.0;

    Color color = periodKey == 'daily' ? Colors.teal : (periodKey == 'monthly' ? Colors.indigo : Colors.deepPurple);

    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 10,
                color: color,
                backgroundColor: color.withOpacity(0.3),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title.split(' ').last, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Text("\$${value.toStringAsFixed(0)}",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesRecordTable(String title, List<PLDetail> items) {
    return Card(
      elevation: 6, // Increased elevation
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // More rounded corners
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$title Sales Records",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueGrey)),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 50,
                headingRowColor: MaterialStateColor.resolveWith((states) => Colors.indigo.shade50), // Highlight header
                columns: const [
                  DataColumn(label: Text("Product", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Qty Sold", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Sale Price", style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Revenue", style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: items.map((item) {
                  return DataRow(cells: [
                    DataCell(Text(item.productName)),
                    DataCell(Text(item.quantitySold.toString())),
                    DataCell(Text("\$${item.unitSalePrice.toStringAsFixed(2)}")),
                    DataCell(Text("\$${item.revenue.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green))),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====================
  // Waste Tab
  // ====================
  Widget _buildWasteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Icon(FontAwesomeIcons.circleExclamation, color: Colors.red, size: 24),
              const SizedBox(width: 10),
              Text("${_displayedPeriodTitle} Waste Summary",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
            ],
          ),
          const Divider(height: 20),
          Text("Total Loss Value (at COGS):", style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text("\$${totalWasteLoss.toStringAsFixed(2)}",
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.redAccent)),
        ]),
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
            columnSpacing: 20,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 50,
            headingRowColor: MaterialStateColor.resolveWith((states) => Colors.red.shade50),
            columns: const [
              DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Unit COGS', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Loss Value', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: items.map((item) {
              return DataRow(cells: [
                DataCell(Text(item.date)),
                DataCell(Text(item.productName)),
                DataCell(Text(item.category)),
                DataCell(Text(item.quantity.toString())),
                DataCell(Text("\$${item.unitPurchasePrice.toStringAsFixed(2)}")),
                DataCell(Text("\$${item.lossValue.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red))),
                DataCell(Text(item.reason)),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ====================
  // Profit & Loss Tab
  // ====================
  Widget _buildProfitLossTab() {
    final report = _currentReportData;
    final items = report?.plDetails ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // SUMMARY CARD REFACTOR
        Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _buildSummaryTile(Icons.attach_money, "Total Revenue", report?.totalRevenue, Colors.green),
              _buildSummaryTile(FontAwesomeIcons.minus, "Total COGS", report?.totalCogs, Colors.brown),
              _buildSummaryTile(FontAwesomeIcons.trashCan, "Total Waste Loss", report?.totalWasteLoss, Colors.red),
              _buildSummaryTile(FontAwesomeIcons.receipt, "Total Expenses", report?.totalExpenses, Colors.orange),
              _buildSummaryTile(FontAwesomeIcons.sliders, "Total Adjustments", report?.totalAdjustments, Colors.blueGrey),

              const Divider(height: 20, thickness: 2, color: Colors.black45),

              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("NET PROFIT",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text("\$${report?.netProfit.toStringAsFixed(2) ?? '0.00'}",
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: (report?.netProfit ?? 0) >= 0 ? Colors.green.shade700 : Colors.red.shade700)),
                  ],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text("${_displayedPeriodTitle} Detailed P&L (Product Level)",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueGrey)),
        const SizedBox(height: 12),
        // DETAILED P&L TABLE REFACTOR
        Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 50,
              headingRowColor: MaterialStateColor.resolveWith((states) => Colors.grey.shade100),
              columns: const [
                DataColumn(label: Text('Product', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Sold Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Revenue', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('COGS', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Waste Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Waste Loss', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Profit', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: items.map((item) {
                double revenue = item.unitSalePrice * item.quantitySold;
                double totalCogs = item.unitCogs * item.quantitySold;
                double soldProfit = revenue - totalCogs - item.wasteLoss;

                return DataRow(cells: [
                  DataCell(Text(item.productName)),
                  DataCell(Text(item.quantitySold.toString())),
                  DataCell(Text("\$${revenue.toStringAsFixed(2)}", style: const TextStyle(color: Colors.green))),
                  DataCell(Text("\$${totalCogs.toStringAsFixed(2)}", style: const TextStyle(color: Colors.brown))),
                  DataCell(Text(item.wasteQty.toString())),
                  DataCell(Text("\$${item.wasteLoss.toStringAsFixed(2)}", style: const TextStyle(color: Colors.red))),
                  DataCell(Text("\$${soldProfit.toStringAsFixed(2)}",
                      style: TextStyle(fontWeight: FontWeight.bold, color: soldProfit >= 0 ? Colors.green.shade700 : Colors.red.shade700))),
                ]);
              }).toList(),
            ),
          ),
        ),
      ]),
    );
  }

  // Helper Widget for P&L Summary
  Widget _buildSummaryTile(IconData icon, String title, double? value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontSize: 16, color: Colors.grey.shade800)),
            ],
          ),
          Text("\$${value?.toStringAsFixed(2) ?? '0.00'}",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}