import '../../data/models/catalog_models.dart';

/// One line in the active sale. Prices come from the backend product.
class CartLine {
  CartLine({required this.product, this.quantity = 1});

  final Product product;
  int quantity;

  /// Price including VAT, as shown to the cashier.
  double get unitTotal => product.price * (1 + product.vatRate / 100);

  double get lineTotal => unitTotal * quantity;
}

/// In-memory cart for the active sale. Keyed by product id.
class Cart {
  final Map<int, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList(growable: false);

  bool get isEmpty => _lines.isEmpty;

  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);

  double get total => _lines.values.fold(0.0, (sum, l) => sum + l.lineTotal);

  int quantityOf(int productId) => _lines[productId]?.quantity ?? 0;

  /// Adds [quantity] units of [product], creating the line if needed.
  void add(Product product, {int quantity = 1}) {
    final existing = _lines[product.id];
    if (existing != null) {
      existing.quantity += quantity;
    } else {
      _lines[product.id] = CartLine(product: product, quantity: quantity);
    }
  }

  /// Sets the quantity for a product. A quantity of zero or less removes it.
  void setQuantity(int productId, int quantity) {
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      _lines[productId]!.quantity = quantity;
    }
  }

  void remove(int productId) => _lines.remove(productId);

  void clear() => _lines.clear();
}

/// Suppresses repeated camera detections of the same barcode.
///
/// A barcode is accepted once; while the camera keeps seeing it, further
/// detections are ignored. It is accepted again only after it has not been
/// seen for [cooldown], or after a different barcode was accepted in between.
/// An intentional re-scan (the code is lifted and presented again) therefore
/// adds another unit.
class ScanDeduplicator {
  ScanDeduplicator({this.cooldown = const Duration(milliseconds: 1500)});

  final Duration cooldown;
  String? _lastCode;
  DateTime? _lastSeen;

  /// Returns true if [code] should be processed at time [now].
  bool accept(String code, DateTime now) {
    final last = _lastSeen;
    final sameCode = code == _lastCode;
    final stillVisible = last != null && now.difference(last) < cooldown;
    if (sameCode && stillVisible) {
      _lastSeen = now;
      return false;
    }
    _lastCode = code;
    _lastSeen = now;
    return true;
  }

  void reset() {
    _lastCode = null;
    _lastSeen = null;
  }
}
