import '../../data/models/catalog_models.dart';

/// Finds a product by barcode on the server. Kept as an interface so the
/// scanning logic can be tested without a network.
abstract interface class ProductLookup {
  /// The product carrying [barcode], or null when none does.
  /// Throws `ApiException` for network or server failures.
  Future<Product?> findByBarcode(String barcode);
}
