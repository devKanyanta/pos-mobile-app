import '../../data/local/sale_queue.dart';
import '../../data/local/sync_meta.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/sale_models.dart';
import '../../data/models/sync_models.dart';
import 'cart.dart';
import 'sale_totals.dart';

/// Saves a sale on the device when the server cannot be reached, and builds
/// the provisional receipt the cashier hands over.
///
/// The sale is stored in the outbox exactly as the upload will send it, with
/// the product names and prices the cashier saw, and keeps the id the online
/// attempt used. If that attempt actually reached the server and only the
/// reply was lost, the later upload is answered `DUPLICATE` and nothing is
/// counted twice.
class OfflineSales {
  OfflineSales({
    required this._queue,
    required this._meta,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SaleQueue _queue;
  final SyncMeta _meta;
  final DateTime Function() _clock;

  /// Queues the sale in [cart] paid with [payment] by [method], and returns
  /// its provisional receipt. Recording the same [clientSaleId] again returns
  /// the sale already queued instead of creating a second one.
  Future<Sale> record({
    required String clientSaleId,
    required Cart cart,
    required PaymentMethod method,
    required PaymentInput payment,
    int? customerId,
  }) async {
    final totals = SaleTotals.ofCart(cart);

    final existing = await _queue.find(clientSaleId);
    final OfflineSaleDraft draft;
    if (existing != null) {
      draft = existing.draft;
    } else {
      draft = OfflineSaleDraft(
        clientSaleId: clientSaleId,
        clientReceiptNumber: await _nextReceiptNumber(),
        soldAt: _clock(),
        customerId: customerId,
        expectedTotal: totals.total,
        items: [
          for (final line in cart.lines)
            OfflineSaleItem.fromProduct(line.product, line.quantity),
        ],
        payments: [payment],
      );
      await _queue.enqueue(draft, now: _clock());
    }

    return _provisionalSale(draft, cart, totals, method, payment);
  }

  /// `OFF-0001`, `OFF-0002`, … — a number the customer's paper receipt
  /// carries and the server stores as the sale's client receipt number.
  Future<String> _nextReceiptNumber() async {
    final last = int.tryParse(
      await _meta.get(SyncMeta.offlineReceiptSeqKey) ?? '',
    );
    final next = (last ?? 0) + 1;
    await _meta.set(SyncMeta.offlineReceiptSeqKey, '$next');
    return 'OFF-${next.toString().padLeft(4, '0')}';
  }

  Sale _provisionalSale(
    OfflineSaleDraft draft,
    Cart cart,
    SaleTotals totals,
    PaymentMethod method,
    PaymentInput payment,
  ) {
    final totalCents = totals.totalCents;
    // What was handed over: the typed cash amount, or exactly the total.
    final tenderedCents = payment.amount == null
        ? totalCents
        : SaleTotals.toCents(payment.amount!);
    final paidCents = tenderedCents < totalCents ? tenderedCents : totalCents;
    final changeCents = tenderedCents > totalCents
        ? tenderedCents - totalCents
        : 0;
    final paid = paidCents >= totalCents;
    final receiptNumber = draft.clientReceiptNumber ?? draft.clientSaleId;

    return Sale(
      id: 0,
      saleNumber: receiptNumber,
      customerId: draft.customerId,
      customerName: null,
      subtotal: totals.subtotal,
      discountAmount: 0,
      vatAmount: totals.vat,
      totalAmount: totals.total,
      amountPaid: paidCents / 100,
      balanceDue: (totalCents - paidCents) / 100,
      changeGiven: changeCents / 100,
      refundedAmount: 0,
      paymentStatus: paid ? 'PAID' : 'PARTIALLY_PAID',
      saleStatus: 'ACTIVE',
      notes: null,
      createdBy: null,
      soldAt: draft.soldAt,
      receiptId: null,
      receiptNumber: receiptNumber,
      zraStatus: null,
      needsReview: false,
      offline: true,
      items: [
        for (var i = 0; i < cart.lines.length; i++)
          SaleItem(
            id: -(i + 1),
            productId: cart.lines[i].product.id,
            productName: cart.lines[i].product.name,
            quantity: cart.lines[i].quantity,
            unitPrice: cart.lines[i].product.price,
            lineTotal: totals.lines[i].netCents / 100,
            totalAmount: totals.lines[i].grossCents / 100,
            refundedQuantity: 0,
            itemStatus: 'ACTIVE',
            vatRate: cart.lines[i].product.vatRate,
            vatAmount: totals.lines[i].vatCents / 100,
            zraTaxType: cart.lines[i].product.zraTaxType,
          ),
      ],
      payments: [
        Payment(
          id: 0,
          paymentMethodName: method.name,
          paymentMethodType: method.type,
          amount: paidCents / 100,
          amountTendered: tenderedCents / 100,
          changeAmount: changeCents / 100,
          transactionReference: payment.transactionReference,
          paymentStatus: 'SUCCESS',
          paidAt: draft.soldAt,
          receiptNumber: receiptNumber,
        ),
      ],
    );
  }
}
