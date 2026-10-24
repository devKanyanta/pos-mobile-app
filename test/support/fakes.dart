import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/core/checkout/product_lookup.dart';
import 'package:kantemba/data/models/catalog_models.dart';

Product testProduct(
  int id, {
  String? barcode,
  double price = 10,
  double vat = 16,
  int stock = 100,
  bool active = true,
  bool track = true,
  String? name,
}) => Product(
  id: id,
  name: name ?? 'Item $id',
  barcode: barcode ?? '600000000000$id',
  sku: null,
  price: price,
  costPrice: 0,
  stockQuantity: stock,
  active: active,
  vatRate: vat,
  trackInventory: track,
  categoryId: null,
  categoryName: null,
  reorderLevel: null,
  lowStock: false,
  zraTaxType: null,
  zraItemCode: null,
  zraItemClassCode: null,
  zraItemTypeCode: null,
  zraOriginCountryCode: null,
  zraPackagingUnitCode: null,
  zraQuantityUnitCode: null,
  zraMapped: false,
  zraRegistered: false,
);

/// In-memory stand-in for the backend lookup.
class FakeLookup implements ProductLookup {
  FakeLookup(List<Product> products)
    : _byBarcode = {for (final p in products) p.barcode!: p};

  final Map<String, Product> _byBarcode;
  final List<String> requested = [];

  /// When set, the next lookups throw this.
  ApiException? failWith;

  /// Completes lookups only when released, to test ordering.
  Future<void>? gate;

  @override
  Future<Product?> findByBarcode(String barcode) async {
    requested.add(barcode);
    if (gate != null) await gate;
    final failure = failWith;
    if (failure != null) throw failure;
    return _byBarcode[barcode];
  }
}
