import 'package:flutter/foundation.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  final int variantId;
  final String colorName;
  final String sizeName;
  final double price;
  int quantity;        // Number of packs or singles
  final int unitsPerPack; // 1 for single, >1 for pack

  CartItem({
    required this.product,
    required this.variantId,
    required this.colorName,
    required this.sizeName,
    required this.price,
    this.quantity = 1,
    this.unitsPerPack = 1,
  });

  /// Key differentiates single vs pack
  String get key => '$variantId-$unitsPerPack';

  /// Total actual units represented
  int get totalUnits => quantity * unitsPerPack;

  /// Total amount for this item (price × quantity)
  double get totalAmount => price * quantity;   // ✅ Add this
}


class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => _items;

  double get totalAmount => _items.values
      .fold(0, (sum, item) => sum + item.price * item.quantity);

  int get totalItems =>
      _items.values.fold(0, (sum, item) => sum + item.totalUnits);

  void addToCart(CartItem item, {required int availableStock}) {
    final key = item.key;
    if (_items.containsKey(key)) {
      final existing = _items[key]!;

      final newTotalUnits = existing.totalUnits + item.totalUnits;
      if (newTotalUnits > availableStock) return;

      existing.quantity += item.quantity; // increment packs or singles
    } else {
      if (item.totalUnits > availableStock) return;
      _items[key] = item;
    }

    notifyListeners();
  }

  void incrementItem(CartItem item, {required int availableStock}) {
    final key = item.key;
    if (!_items.containsKey(key)) return;

    final existing = _items[key]!;
    final newTotalUnits = existing.totalUnits + existing.unitsPerPack;

    if (newTotalUnits > availableStock) return;

    existing.quantity += 1;
    notifyListeners();
  }

  void decrementItem(CartItem item) {
    final key = item.key;
    if (!_items.containsKey(key)) return;

    final existing = _items[key]!;

    if (existing.quantity > 1) {
      existing.quantity -= 1;
    } else {
      _items.remove(key);
    }

    notifyListeners();
  }

  void removeItem(CartItem item) {
    _items.remove(item.key);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> get checkoutItems {
    return _items.values
        .map((item) => {
      "variant": item.variantId,
      "quantity": item.totalUnits,
    })
        .toList();
  }
}
