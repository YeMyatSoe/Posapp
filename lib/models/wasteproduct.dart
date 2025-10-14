class WasteProduct {
  final int id;
  final String date;
  final String productName;
  final int? sku;
  final String? category;
  final int quantity;
  final double unitPurchasePrice;
  final double lossValue;
  final String reason;
  final String? colorName;
  final String? sizeName;

  WasteProduct({
    required this.id,
    required this.date,
    required this.productName,
    this.sku,
    this.category,
    required this.quantity,
    required this.unitPurchasePrice,
    required this.lossValue,
    required this.reason,
    this.colorName,
    this.sizeName,
  });

  factory WasteProduct.fromJson(Map<String, dynamic> json) {
    // Safely get the variant object
    final variant = json['variant'] ?? json['product'] ?? {};

    // Parse unit purchase price
    double unitPrice = 0.0;
    if (variant['unit_purchase_price'] is num) {
      unitPrice = (variant['unit_purchase_price'] as num).toDouble();
    } else {
      unitPrice = double.tryParse(variant['unit_purchase_price']?.toString() ?? '0') ?? 0.0;
    }

    // Parse quantity
    final qty = json['quantity'] ?? 0;

    return WasteProduct(
      id: json['id'] ?? 0,
      date: json['recorded_at']?.split("T").first ?? 'N/A',
      productName: json['product_name'] ?? json['product']?['name'] ?? 'N/A',
      sku: variant['sku'] ?? variant['id'],
      category: variant['category'] ?? variant['category_name'],
      quantity: qty,
      unitPurchasePrice: unitPrice,
      lossValue: qty * unitPrice,
      reason: json['reason'] ?? '-',
      colorName: variant['color_name'] ?? '-',
      sizeName: variant['size_name'] ?? '-',
    );
  }
}
