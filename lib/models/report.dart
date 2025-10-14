import 'package:flutter/material.dart';

// Helper function to safely parse dynamic values to double
double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

// --- Detail Models ---

@immutable
class WasteItem {
  final DateTime date;
  final String productName;
  final String sku;
  final String category;
  final int quantity;
  final double unitPurchasePrice;
  final double lossValue;
  final String? reason;

  const WasteItem({
    required this.date,
    required this.productName,
    required this.sku,
    required this.category,
    required this.quantity,
    required this.unitPurchasePrice,
    required this.lossValue,
    this.reason,
  });

  factory WasteItem.fromJson(Map<String, dynamic> json) {
    return WasteItem(
      date: DateTime.parse(json['date']),
      productName: json['product_name'] as String,
      sku: json['sku'].toString(),
      category: json['category'] as String,
      quantity: json['quantity'] as int,
      unitPurchasePrice: _toDouble(json['unit_purchase_price']),
      lossValue: _toDouble(json['loss_value']),
      reason: json['reason'] as String?,
    );
  }
}

@immutable
class PLItem {
  final String productName;
  final String sku;
  final int quantitySold;
  final double unitSalePrice;
  final double unitCogs;
  final int wasteQty;
  final double wasteLoss;
  final double revenue;
  final double cogs;
  final double profit;

  const PLItem({
    required this.productName,
    required this.sku,
    required this.quantitySold,
    required this.unitSalePrice,
    required this.unitCogs,
    required this.wasteQty,
    required this.wasteLoss,
    required this.revenue,
    required this.cogs,
    required this.profit,
  });

  factory PLItem.fromJson(Map<String, dynamic> json) {
    return PLItem(
      productName: json['product_name'] as String,
      sku: json['sku'].toString(),
      quantitySold: json['quantity_sold'] as int,
      unitSalePrice: _toDouble(json['unit_sale_price']),
      unitCogs: _toDouble(json['unit_cogs']),
      wasteQty: json['waste_qty'] as int,
      wasteLoss: _toDouble(json['waste_loss']),
      revenue: _toDouble(json['revenue']),
      cogs: _toDouble(json['cogs']),
      profit: _toDouble(json['profit']),
    );
  }
}

// --- Main Report Model ---

@immutable
class ShopReport {
  // Summary
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;
  final double totalCogs;
  final double totalWasteLoss;
  final double totalExpenses;
  final double totalAdjustments;
  final double grossProfit;
  final double netProfit;

  // Details
  final List<WasteItem> wasteDetails;
  final List<PLItem> plDetails;

  const ShopReport({
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalCogs,
    required this.totalWasteLoss,
    required this.totalExpenses,
    required this.totalAdjustments,
    required this.grossProfit,
    required this.netProfit,
    required this.wasteDetails,
    required this.plDetails,
  });

  factory ShopReport.fromJson(Map<String, dynamic> json) {
    return ShopReport(
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      totalRevenue: _toDouble(json['total_revenue']),
      totalCogs: _toDouble(json['total_cogs']),
      totalWasteLoss: _toDouble(json['total_waste_loss']),
      totalExpenses: _toDouble(json['total_expenses']),
      totalAdjustments: _toDouble(json['total_adjustments']),
      grossProfit: _toDouble(json['gross_profit']),
      netProfit: _toDouble(json['net_profit']),
      wasteDetails: (json['waste_details'] as List)
          .map((i) => WasteItem.fromJson(i))
          .toList(),
      plDetails: (json['pl_details'] as List)
          .map((i) => PLItem.fromJson(i))
          .toList(),
    );
  }

  // Helper for Sales summary
  Map<String, double> get salesSummary {
    return {
      'revenue': totalRevenue,
      'cogs': totalCogs,
      'waste_loss': totalWasteLoss,
      'net_profit': netProfit,
    };
  }

}

// Represents the initial state while data is loading
final ShopReport initialReport = ShopReport(
  startDate: DateTime.now(),
  endDate: DateTime.now(),
  totalRevenue: 0.0,
  totalCogs: 0.0,
  totalWasteLoss: 0.0,
  totalExpenses: 0.0,
  totalAdjustments: 0.0,
  grossProfit: 0.0,
  netProfit: 0.0,
  wasteDetails: const [],
  plDetails: const [],
);
