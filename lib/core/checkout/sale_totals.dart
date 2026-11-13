import 'cart.dart';

/// One line's amounts in whole cents (ngwee).
class LineAmounts {
  const LineAmounts({required this.netCents, required this.vatCents});

  /// Unit price × quantity, VAT exclusive.
  final int netCents;
  final int vatCents;

  int get grossCents => netCents + vatCents;
}

/// A sale's amounts, calculated the way the server calculates them, so a
/// receipt printed offline shows the amounts the server will later record.
///
/// Prices are VAT exclusive. Each line is `unit price × quantity`, and the VAT
/// on it is `net × rate / 100` rounded half-up to the cent, per line; the
/// total is the sum of net and VAT over all lines (see the backend's
/// `SaleCalculator`). Everything is integer cents, so no floating-point
/// error can creep into a sum. Line and sale discounts are not offered at the
/// till and are not handled here.
class SaleTotals {
  SaleTotals._(this.lines)
    : subtotalCents = lines.fold(0, (sum, l) => sum + l.netCents),
      vatCents = lines.fold(0, (sum, l) => sum + l.vatCents);

  final List<LineAmounts> lines;
  final int subtotalCents;
  final int vatCents;

  int get totalCents => subtotalCents + vatCents;

  double get subtotal => subtotalCents / 100;
  double get vat => vatCents / 100;
  double get total => totalCents / 100;

  factory SaleTotals.ofCart(Cart cart) => SaleTotals._([
    for (final line in cart.lines)
      _line(line.product.price, line.quantity, line.product.vatRate),
  ]);

  static LineAmounts _line(double unitPrice, int quantity, double vatRate) {
    final net = toCents(unitPrice) * quantity;
    // The rate in hundredths of a percent, so 16 % is 1600: net × rate / 100
    // cents becomes net × 1600 / 10000, rounded half-up by adding half.
    final vat = (net * toCents(vatRate) + 5000) ~/ 10000;
    return LineAmounts(netCents: net, vatCents: vat);
  }

  /// [amount] in whole cents, rounded to the nearest.
  static int toCents(double amount) => (amount * 100).round();
}
