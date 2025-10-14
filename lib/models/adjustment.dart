import 'package:intl/intl.dart';

class Adjustment {
  final int? id; // Nullable for new adjustments
  final int shop;
  final String? shopName;
  final int? user;
  final String? userName;
  final DateTime date;
  final double amount;
  final String description;
  final String adjustmentType; // 'INCOME' or 'EXPENSE'
  final DateTime? createdAt;

  Adjustment({
    this.id,
    required this.shop,
    this.shopName,
    this.user,
    this.userName,
    required this.date,
    required this.amount,
    required this.description,
    required this.adjustmentType,
    this.createdAt,
  });
  factory Adjustment.fromJson(Map<String, dynamic> json) {

    // --- FIX: Robustly handle 'amount' which may be String or num ---
    final rawAmount = json['amount'];
    double parsedAmount;

    if (rawAmount is num) {
      // Handles JSON numbers (int or double)
      parsedAmount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      // Handles Django DecimalField serialized as a string (e.g., "45.99")
      parsedAmount = double.tryParse(rawAmount) ?? 0.0;
    } else {
      // Fallback for unexpected null or type
      parsedAmount = 0.0;
    }
    // --- END FIX ---

    // Optional: If your Django ViewSet is NOT using pk_url_kwarg for 'shop'
    // and instead includes the full Shop object, you may need a deeper check:
    final rawShop = json['shop'];
    int shopId = rawShop is Map ? rawShop['id'] as int : rawShop as int;

    // Optional: Safely parse user ID, handling cases where it might be null
    final rawUser = json['user'];
    int? userId = rawUser is int ? rawUser : (rawUser is String ? int.tryParse(rawUser) : null);


    return Adjustment(
      id: json['id'] as int?,
      shop: shopId,
      shopName: json['shop_name'] as String?,
      user: userId,
      userName: json['user_name'] as String?,
      date: DateTime.parse(json['date'] as String),

      amount: parsedAmount, // Use the safely parsed amount

      description: json['description'] as String,

      // NOTE: Ensure your Flutter form uses 'GAIN'/'LOSS'/'CORRECTION'
      // instead of 'INCOME'/'EXPENSE' to match your Django model.
      adjustmentType: json['adjustment_type'] as String,

      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  // Method to convert the object to a JSON map for API submission (Creation/Update)
  Map<String, dynamic> toJsonForCreation() {
    return {
      'shop': shop,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'amount': amount,
      'description': description,
      'adjustment_type': adjustmentType,
    };
  }
}