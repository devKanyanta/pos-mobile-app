import '../../data/models/catalog_models.dart';

/// One line in the active sale. Prices come from the backend product.
class CartLine {
  CartLine({required this.product, this.quantity = 1});

  /// Latest backend-confirmed product data (price, VAT, stock).
  Product product;
  int quantity;

  /// Price including VAT, as shown to the cashier.
  double get unitTotal => product.price * (1 + product.vatRate / 100);

  double get lineTotal => unitTotal * quantity;
}

/// In-memory cart for the active sale. Keyed by product id. Amounts here are
/// an estimate for display; the server calculates the real totals.
class Cart {
  final Map<int, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList(growable: false);

  bool get isEmpty => _lines.isEmpty;

  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);

  double get total => _lines.values.fold(0.0, (sum, l) => sum + l.lineTotal);

  int quantityOf(int productId) => _lines[productId]?.quantity ?? 0;

  /// Adds [quantity] units of [product], creating the line if needed. An
  /// existing line takes the fresher product data (the price may have changed).
  void add(Product product, {int quantity = 1}) {
    final existing = _lines[product.id];
    if (existing != null) {
      existing.product = product;
      existing.quantity += quantity;
    } else {
      _lines[product.id] = CartLine(product: product, quantity: quantity);
    }
  }

  /// Sets the quantity for a product. A quantity of zero or less removes it.
  void setQuantity(int productId, int quantity) {
    final line = _lines[productId];
    if (line == null) return;
    if (quantity <= 0) {
      _lines.remove(productId);
    } else {
      line.quantity = quantity;
    }
  }

  void remove(int productId) => _lines.remove(productId);

  void clear() => _lines.clear();
}
