import 'package:flutter/foundation.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  final int variantId; // Must match ProductVariant.id in backend
  final String colorName;
  final String sizeName;
  int quantity;

  CartItem({
    required this.product,
    required this.variantId,
    this.colorName = "N/A",
    this.sizeName = "N/A",
    this.quantity = 1,
  });

  String get key => '$variantId';
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => _items;

  double get totalAmount {
    double total = 0;
    _items.forEach((key, item) {
      total += item.product.price * item.quantity;
    });
    return total;
  }

  int get totalItems {
    int total = 0;
    _items.forEach((key, item) {
      total += item.quantity;
    });
    return total;
  }

  void addToCart(CartItem item, {int? availableStock}) {
    final key = item.key;
    if (_items.containsKey(key)) {
      final newQty = _items[key]!.quantity + item.quantity;
      if (newQty > (availableStock ?? 9999)) return;
      _items[key]!.quantity = newQty;
    } else {
      if (item.quantity > (availableStock ?? 9999)) return;
      _items[key] = item;
    }
    notifyListeners();
  }

  void incrementItem(CartItem item, {int? availableStock}) {
    final key = item.key;
    if (_items.containsKey(key)) {
      if (_items[key]!.quantity + 1 > (availableStock ?? 9999)) return;
      _items[key]!.quantity += 1;
      notifyListeners();
    }
  }

  void decrementItem(CartItem item) {
    final key = item.key;
    if (_items.containsKey(key)) {
      if (_items[key]!.quantity > 1) {
        _items[key]!.quantity -= 1;
      } else {
        _items.remove(key);
      }
      notifyListeners();
    }
  }

  void removeItem(CartItem item) {
    _items.remove(item.key);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  /// For API checkout: only send variant ID and quantity
  List<Map<String, dynamic>> get checkoutItems {
    return _items.values.map((item) {
      return {
        "variant": item.variantId,
        "quantity": item.quantity,
      };
    }).toList();
  }
}
