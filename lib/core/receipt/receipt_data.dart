import 'package:intl/intl.dart';

import '../../data/models/merchant_models.dart';
import '../../data/models/receipt_models.dart';
import '../../data/models/sale_models.dart';
import '../../data/services/pos_api.dart';
import '../../data/services/sales_api.dart';

/// Amounts are shown with two decimals and no currency symbol, as everywhere
/// else in the app.
String formatMoney(double value) => value.toStringAsFixed(2);

/// Everything a receipt shows, gathered once so the on-screen receipt and the
/// printed/PDF receipt can never disagree.
///
/// [sale] is authoritative (the server calculated every amount). [merchant]
/// and [fiscal] enrich it and may be missing: a receipt must still be usable
/// when the business profile or the fiscal details cannot be loaded.
class ReceiptData {
  const ReceiptData({required this.sale, this.merchant, this.fiscal});

  final Sale sale;
  final MerchantProfile? merchant;
  final ReceiptInfo? fiscal;

  static const fallbackBusinessName = 'Kantemba POS';

  String get businessName {
    final name = merchant?.businessName.trim() ?? '';
    return name.isEmpty ? fallbackBusinessName : name;
  }

  String get receiptNumber {
    final fromServer = fiscal?.receiptNumber.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    final fromSale = sale.receiptNumber?.trim() ?? '';
    return fromSale.isNotEmpty ? fromSale : sale.saleNumber;
  }

  String get footer {
    final text = merchant?.receiptFooter.trim() ?? '';
    return text.isEmpty ? 'Thank you for your purchase.' : text;
  }

  String? get soldAtLabel {
    final at = sale.soldAt;
    return at == null
        ? null
        : DateFormat('dd MMM yyyy, HH:mm').format(at.toLocal());
  }

  bool get hasFiscalDetails => fiscal != null && fiscal!.zraStatus != null;

  /// A file name that is safe on every platform, e.g. `receipt-R-0007.pdf`.
  String get fileName {
    final safe = receiptNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return 'receipt-$safe.pdf';
  }

  /// The items that were actually sold (not voided or fully refunded lines).
  List<SaleItem> get items => sale.items;

  ReceiptData copyWith({MerchantProfile? merchant, ReceiptInfo? fiscal}) =>
      ReceiptData(
        sale: sale,
        merchant: merchant ?? this.merchant,
        fiscal: fiscal ?? this.fiscal,
      );

  /// Loads the business profile and fiscal details for [sale]. Each lookup is
  /// independent and best effort: a failure leaves that part out.
  static Future<ReceiptData> load(PosApi pos, SalesApi sales, Sale sale) async {
    final results = await Future.wait<Object?>([
      pos.getMerchant().then<Object?>((m) => m).catchError((_) => null),
      sales
          .receiptForSale(sale.id)
          .then<Object?>((r) => r)
          .catchError((_) => null),
    ]);
    return ReceiptData(
      sale: sale,
      merchant: results[0] as MerchantProfile?,
      fiscal: results[1] as ReceiptInfo?,
    );
  }
}
