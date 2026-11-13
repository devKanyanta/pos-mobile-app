import 'dart:math';

import '../../data/models/catalog_models.dart';
import '../../data/models/sale_models.dart';
import '../../data/services/sales_api.dart';
import '../api/api_exception.dart';
import 'cart.dart';
import 'offline_sales.dart';

/// Completes a sale in a single atomic request.
///
/// The items and the tender go to `POST /sales` together, so the server
/// calculates prices, VAT and the total, checks stock, deducts it and records
/// the payment in one transaction: either all of it happens or none of it.
/// No payment amount is sent unless the cashier typed a cash amount, because
/// an omitted amount means "settle the balance the server calculated".
///
/// Retrying after a failure reuses one `clientSaleId`, so a request whose
/// response was lost cannot create a second sale; the server answers the
/// retry with the sale it already recorded.
///
/// With [offline] set, a sale that cannot reach the server is saved on the
/// device instead of failing, and the cashier gets a provisional receipt
/// ([Sale.offline]). Only a connection failure does this: when the server
/// answers with an error (out of stock, a bad request) the sale is refused as
/// before. [preferOffline] says the server was just found unreachable, so the
/// sale is saved at once instead of waiting out another network timeout.
class CheckoutService {
  CheckoutService(
    this._sales, {
    String Function()? idGenerator,
    this.offline,
    this.preferOffline,
  }) : _newId = idGenerator ?? _randomId;

  final SalesApi _sales;
  final String Function() _newId;
  final OfflineSales? offline;
  final bool Function()? preferOffline;

  String? _pendingId;
  String? _pendingSignature;

  /// The id that will be used for the next attempt (for tests and display).
  String? get pendingClientSaleId => _pendingId;

  Future<Sale> complete(
    Cart cart,
    PaymentMethod method, {
    String? reference,
    double? amountReceived,
    int? customerId,
  }) async {
    if (cart.isEmpty) {
      throw StateError('The sale has no items.');
    }

    final items = [
      for (final line in cart.lines)
        SaleItemInput(
          productId: line.product.id,
          quantity: line.quantity,
          barcode: line.product.barcode,
        ),
    ];
    final payment = PaymentInput(
      paymentMethodId: method.id,
      amount: amountReceived,
      transactionReference: (reference == null || reference.trim().isEmpty)
          ? null
          : reference.trim(),
    );

    final signature =
        '${[for (final i in items) '${i.productId}x${i.quantity}'].join(',')}|${method.id}|${payment.transactionReference}|$amountReceived|$customerId';
    if (_pendingSignature != signature || _pendingId == null) {
      _pendingId = _newId();
      _pendingSignature = signature;
    }

    final clientSaleId = _pendingId!;
    Future<Sale> saveOffline() => offline!.record(
      clientSaleId: clientSaleId,
      cart: cart,
      method: method,
      payment: payment,
      customerId: customerId,
    );

    Sale sale;
    if (offline != null && (preferOffline?.call() ?? false)) {
      sale = await saveOffline();
    } else {
      try {
        sale = await _sales.createSale(
          items: items,
          payments: [payment],
          customerId: customerId,
          clientSaleId: clientSaleId,
        );
      } on ApiException catch (e) {
        if (offline == null || !e.isNetwork) rethrow;
        sale = await saveOffline();
      }
    }

    _pendingId = null;
    _pendingSignature = null;
    return sale;
  }

  /// Forget any pending attempt (the cashier cleared the sale).
  void reset() {
    _pendingId = null;
    _pendingSignature = null;
  }

  static String _randomId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'k-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$suffix';
  }
}
