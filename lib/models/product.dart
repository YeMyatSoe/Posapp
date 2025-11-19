class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String category;
  final String? barcode; // ✅ Added barcode field
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.barcode, // ✅ optional
    this.variants = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    List<ProductVariant> parseVariants(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((v) => ProductVariant.fromJson(v)).toList();
      }
      return [];
    }

    final variants = parseVariants(json['variants']);

    double price = variants.isNotEmpty
        ? variants.map((v) => v.effectivePrice).reduce((a, b) => a < b ? a : b)
        : 0.0;

    return Product(
      id: json['id'].toString(),
      name: json['name'] ?? '',
      price: price,
      imageUrl: json['image'] ?? 'https://picsum.photos/200/300',
      category: json['category']?.toString() ?? 'Uncategorized',
      barcode: json['barcode']?.toString(),
      variants: variants,
    );
  }
}
  class ProductVariant {
  final int id;
  final int? color;
  final int? size;
  final String? colorName;
  final String? sizeName;
  final int stockQuantity;
  final double salePrice;
  final double? singleSalePrice;
  final double? packSalePrice;
  final bool isPack;
  final int unitsPerPack;

  ProductVariant({
    required this.id,
    this.color,
    this.size,
    this.colorName,
    this.sizeName,
    this.stockQuantity = 0,
    required this.salePrice,
    this.singleSalePrice,
    this.packSalePrice,
    this.isPack = false,
    this.unitsPerPack = 1,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ProductVariant(
      id: parseInt(json['id']),
      color: json['color'] != null ? parseInt(json['color']) : null,
      size: json['size'] != null ? parseInt(json['size']) : null,
      colorName: json['color_name'],
      sizeName: json['size_name'],
      stockQuantity: parseInt(json['stock_quantity']),
      salePrice: parseDouble(json['sale_price']),
      singleSalePrice: json['single_sale_price'] != null
          ? parseDouble(json['single_sale_price'])
          : null,
      packSalePrice: json['pack_sale_price'] != null
          ? parseDouble(json['pack_sale_price'])
          : null,
      isPack: json['is_pack'] ?? false,
      unitsPerPack: parseInt(json['units_per_pack'] ?? 1),
    );
  }

  double get effectivePrice {
    if (isPack) return packSalePrice ?? salePrice;
    return singleSalePrice ?? salePrice;
  }
}

