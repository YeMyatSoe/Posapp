class SupplierDebt {
  final int id;
  final String shopName;
  final String supplierName;
  final double amount;
  final String status;
  final String? dueDate;

  SupplierDebt({
    required this.id,
    required this.shopName,
    required this.supplierName,
    required this.amount,
    required this.status,
    this.dueDate,
  });

  factory SupplierDebt.fromJson(Map<String, dynamic> json) {
    return SupplierDebt(
      id: json['id'],
      shopName: json['shop']?['name'] ?? '-',
      supplierName: json['supplier']?['name'] ?? '-',
      amount: (json['amount'] as num).toDouble(),
      status: json['status'] ?? 'UNPAID',
      dueDate: json['due_date'],
    );
  }
}
