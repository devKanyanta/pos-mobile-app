import 'json_utils.dart';

/// `ProductResponse` from the products endpoints.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.price,
    required this.costPrice,
    required this.stockQuantity,
    required this.active,
    required this.vatRate,
    required this.trackInventory,
    required this.categoryId,
    required this.categoryName,
    required this.reorderLevel,
    required this.lowStock,
    required this.zraTaxType,
    required this.zraItemCode,
    required this.zraItemClassCode,
    required this.zraItemTypeCode,
    required this.zraOriginCountryCode,
    required this.zraPackagingUnitCode,
    required this.zraQuantityUnitCode,
    required this.zraMapped,
    required this.zraRegistered,
  });

  final int id;
  final String name;
  final String? barcode;
  final String? sku;
  final double price;
  final double costPrice;
  final int stockQuantity;
  final bool active;
  final double vatRate;
  final bool trackInventory;
  final int? categoryId;
  final String? categoryName;
  final int? reorderLevel;
  final bool lowStock;
  final String? zraTaxType;
  final String? zraItemCode;
  final String? zraItemClassCode;
  final String? zraItemTypeCode;
  final String? zraOriginCountryCode;
  final String? zraPackagingUnitCode;
  final String? zraQuantityUnitCode;
  final bool zraMapped;
  final bool zraRegistered;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: toInt(json['id']),
        name: toStr(json['name']),
        barcode: toStrOrNull(json['barcode']),
        sku: toStrOrNull(json['sku']),
        price: toDouble(json['price']),
        costPrice: toDouble(json['costPrice']),
        stockQuantity: toInt(json['stockQuantity']),
        active: toBool(json['active'], true),
        vatRate: toDouble(json['vatRate']),
        trackInventory: toBool(json['trackInventory']),
        categoryId: toIntOrNull(json['categoryId']),
        categoryName: toStrOrNull(json['categoryName']),
        reorderLevel: toIntOrNull(json['reorderLevel']),
        lowStock: toBool(json['lowStock']),
        zraTaxType: toStrOrNull(json['zraTaxType']),
        zraItemCode: toStrOrNull(json['zraItemCode']),
        zraItemClassCode: toStrOrNull(json['zraItemClassCode']),
        zraItemTypeCode: toStrOrNull(json['zraItemTypeCode']),
        zraOriginCountryCode: toStrOrNull(json['zraOriginCountryCode']),
        zraPackagingUnitCode: toStrOrNull(json['zraPackagingUnitCode']),
        zraQuantityUnitCode: toStrOrNull(json['zraQuantityUnitCode']),
        zraMapped: toBool(json['zraMapped']),
        zraRegistered: toBool(json['zraRegistered']),
      );
}

/// `CategoryResponse`.
class Category {
  const Category({required this.id, required this.name, this.description});

  final int id;
  final String name;
  final String? description;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: toInt(json['id']),
        name: toStr(json['name']),
        description: toStrOrNull(json['description']),
      );
}

/// `PaymentMethodResponse`.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
    required this.type,
    required this.requiresReference,
  });

  final int id;
  final String name;
  final String code;
  final bool isActive;
  final String type;
  final bool requiresReference;

  bool get isCash => type == 'CASH';
  bool get isMobileMoney => type == 'MOBILE_MONEY';

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: toInt(json['id']),
        name: toStr(json['name']),
        code: toStr(json['code']),
        isActive: toBool(json['isActive'], true),
        type: toStr(json['type'], 'OTHER'),
        requiresReference: toBool(json['requiresReference']),
      );
}
