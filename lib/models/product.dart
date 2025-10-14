class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String category;
  final List<ProductVariant> variants; // List of variants, never null

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.variants = const [], // Default to empty list
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is int) return value.toDouble();
      if (value is double) return value;
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    List<ProductVariant> parseVariants(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((v) => ProductVariant.fromJson(v)).toList();
      }
      return [];
    }

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: parseDouble(json['sale_price']),
      imageUrl: json['image'] ?? 'https://picsum.photos/200/300',
      category: json['category']?['name'] ?? 'Uncategorized',
      variants: parseVariants(json['variants']), // Always a list
    );
  }
}

class ProductVariant {
  final String? id;
  final String? colorName;
  final String? sizeName;
  final int stockQuantity;

  ProductVariant({
    this.id,
    this.colorName,
    this.sizeName,
    this.stockQuantity = 0,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id']?.toString(),
      colorName: json['color_name'],
      sizeName: json['size_name'],
      stockQuantity: json['stock_quantity'] ?? 0,
    );
  }
}
