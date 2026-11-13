import 'catalog_models.dart';
import 'json_utils.dart';
import 'sale_models.dart';

/// Formats a device-local time the way the backend's `LocalDateTime` fields
/// expect it: ISO date and time, seconds precision, no time zone.
String formatLocalDateTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${time.year.toString().padLeft(4, '0')}'
      '-${two(time.month)}-${two(time.day)}';
  return '${date}T${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// One product from `GET /sync/catalog` (`CatalogResponse.ProductItem`): the
/// fields a till needs to ring up sales offline.
class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    required this.price,
    required this.vatRate,
    required this.zraTaxType,
    required this.trackInventory,
    required this.stockQuantity,
    required this.active,
    required this.categoryId,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String? sku;
  final String? barcode;

  /// VAT-exclusive, like everywhere else in the API.
  final double price;
  final double vatRate;
  final String? zraTaxType;
  final bool trackInventory;
  final int stockQuantity;
  final bool active;
  final int? categoryId;
  final String? updatedAt;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: toInt(json['id']),
    name: toStr(json['name']),
    sku: toStrOrNull(json['sku']),
    barcode: toStrOrNull(json['barcode']),
    price: toDouble(json['price']),
    vatRate: toDouble(json['vatRate']),
    zraTaxType: toStrOrNull(json['zraTaxType']),
    trackInventory: toBool(json['trackInventory'], true),
    stockQuantity: toInt(json['stockQuantity']),
    active: toBool(json['active'], true),
    categoryId: toIntOrNull(json['categoryId']),
    updatedAt: toStrOrNull(json['updatedAt']),
  );

  /// Snapshot of this product from the product endpoints, for a delta pull
  /// that is answered from already-loaded full products.
  factory CatalogProduct.fromProduct(Product product) => CatalogProduct(
    id: product.id,
    name: product.name,
    sku: product.sku,
    barcode: product.barcode,
    price: product.price,
    vatRate: product.vatRate,
    zraTaxType: product.zraTaxType,
    trackInventory: product.trackInventory,
    stockQuantity: product.stockQuantity,
    active: product.active,
    categoryId: product.categoryId,
    updatedAt: null,
  );

  /// Full [Product] view for the checkout path. Fields the sync catalogue
  /// does not carry (cost price, reorder level, ZRA registration) take
  /// neutral values; checkout never reads them.
  Product toProduct({String? categoryName}) => Product(
    id: id,
    name: name,
    barcode: barcode,
    sku: sku,
    price: price,
    costPrice: 0,
    stockQuantity: stockQuantity,
    active: active,
    vatRate: vatRate,
    trackInventory: trackInventory,
    categoryId: categoryId,
    categoryName: categoryName,
    reorderLevel: null,
    lowStock: false,
    zraTaxType: zraTaxType,
    zraItemCode: null,
    zraItemClassCode: null,
    zraItemTypeCode: null,
    zraOriginCountryCode: null,
    zraPackagingUnitCode: null,
    zraQuantityUnitCode: null,
    zraMapped: zraTaxType != null,
    zraRegistered: false,
  );
}

/// `GET /sync/catalog` (`CatalogResponse`): a full snapshot or a delta.
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.serverTime,
    required this.full,
    required this.products,
    required this.categories,
    required this.paymentMethods,
    required this.productIds,
  });

  /// Pass back as `since` on the next pull. Kept exactly as the server wrote
  /// it, so the server's clock is the only one involved.
  final String serverTime;
  final bool full;
  final List<CatalogProduct> products;
  final List<Category> categories;
  final List<PaymentMethod> paymentMethods;

  /// Every product id the server has; anything cached but missing here was
  /// deleted. Null when the response did not carry the list, in which case
  /// nothing may be deleted.
  final List<int>? productIds;

  factory CatalogSnapshot.fromJson(Map<String, dynamic> json) =>
      CatalogSnapshot(
        serverTime: toStr(json['serverTime']),
        full: toBool(json['full']),
        products: toMapList(json['products'])
            .map(CatalogProduct.fromJson)
            .toList(growable: false),
        categories: toMapList(json['categories'])
            .map(Category.fromJson)
            .toList(growable: false),
        paymentMethods: toMapList(json['paymentMethods'])
            .map(PaymentMethod.fromJson)
            .toList(growable: false),
        productIds: json['productIds'] is List
            ? [for (final id in json['productIds'] as List) toInt(id)]
            : null,
      );
}

/// What the server did with one uploaded sale (`SyncSaleResult`).
class SyncSaleResult {
  const SyncSaleResult({
    required this.clientSaleId,
    required this.status,
    required this.saleNumber,
    required this.receiptNumber,
    required this.conflicts,
    required this.error,
  });

  final String clientSaleId;

  /// `CREATED` (recorded now), `DUPLICATE` (recorded earlier — safe to drop
  /// from the queue) or `REJECTED` (invalid; see [error]).
  final String status;
  final String? saleNumber;
  final String? receiptNumber;

  /// Problems the server recorded on a created sale for a manager to review
  /// (e.g. `NEGATIVE_STOCK`, `PRICE_MISMATCH`).
  final List<String> conflicts;
  final String? error;

  bool get isRecorded => status == 'CREATED' || status == 'DUPLICATE';
  bool get isRejected => status == 'REJECTED';

  factory SyncSaleResult.fromJson(Map<String, dynamic> json) => SyncSaleResult(
    clientSaleId: toStr(json['clientSaleId']),
    status: toStr(json['status']),
    saleNumber: toStrOrNull(json['saleNumber']),
    receiptNumber: toStrOrNull(json['receiptNumber']),
    conflicts: [
      if (json['conflicts'] is List)
        for (final c in json['conflicts'] as List) toStr(c),
    ],
    error: toStrOrNull(json['error']),
  );
}

/// `POST /sync/sales` answer: one [SyncSaleResult] per uploaded sale.
class SyncSalesResponse {
  const SyncSalesResponse({required this.results});

  final List<SyncSaleResult> results;

  factory SyncSalesResponse.fromJson(Map<String, dynamic> json) =>
      SyncSalesResponse(
        results: toMapList(json['results'])
            .map(SyncSaleResult.fromJson)
            .toList(growable: false),
      );
}

/// `DeviceResponse` from the sync endpoints: one registered till.
class Device {
  const Device({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.model,
    required this.appVersion,
    required this.active,
    required this.registeredBy,
    required this.lastUser,
    required this.lastSeenAt,
    required this.lastSyncAt,
    required this.pendingQueueSize,
    required this.reportedOnline,
  });

  final int id;
  final String deviceId;
  final String? name;
  final String? model;
  final String? appVersion;
  final bool active;
  final String? registeredBy;
  final String? lastUser;
  final DateTime? lastSeenAt;
  final DateTime? lastSyncAt;
  final int pendingQueueSize;
  final bool reportedOnline;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: toInt(json['id']),
    deviceId: toStr(json['deviceId']),
    name: toStrOrNull(json['name']),
    model: toStrOrNull(json['model']),
    appVersion: toStrOrNull(json['appVersion']),
    active: toBool(json['active'], true),
    registeredBy: toStrOrNull(json['registeredBy']),
    lastUser: toStrOrNull(json['lastUser']),
    lastSeenAt: toDateTime(json['lastSeenAt']),
    lastSyncAt: toDateTime(json['lastSyncAt']),
    pendingQueueSize: toInt(json['pendingQueueSize']),
    reportedOnline: toBool(json['reportedOnline']),
  );
}

/// One line of an offline sale (`OfflineSaleRequest.Item`). Carries the
/// device's product snapshot so the server can record the sale even if the
/// product has since changed or disappeared.
class OfflineSaleItem {
  const OfflineSaleItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.vatRate,
    this.zraTaxType,
    this.discountAmount = 0,
  });

  final int productId;
  final String productName;
  final int quantity;

  /// Price charged on the device, VAT exclusive.
  final double unitPrice;
  final double vatRate;
  final String? zraTaxType;
  final double discountAmount;

  factory OfflineSaleItem.fromProduct(Product product, int quantity) =>
      OfflineSaleItem(
        productId: product.id,
        productName: product.name,
        quantity: quantity,
        unitPrice: product.price,
        vatRate: product.vatRate,
        zraTaxType: product.zraTaxType,
      );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'vatRate': vatRate,
    'zraTaxType': ?zraTaxType,
    if (discountAmount > 0) 'discountAmount': discountAmount,
  };

  factory OfflineSaleItem.fromJson(Map<String, dynamic> json) =>
      OfflineSaleItem(
        productId: toInt(json['productId']),
        productName: toStr(json['productName']),
        quantity: toInt(json['quantity']),
        unitPrice: toDouble(json['unitPrice']),
        vatRate: toDouble(json['vatRate']),
        zraTaxType: toStrOrNull(json['zraTaxType']),
        discountAmount: toDouble(json['discountAmount']),
      );
}

/// A sale captured while offline: the body of one entry in `POST /sync/sales`
/// (`OfflineSaleRequest`). [clientSaleId] is the idempotency key, so the same
/// draft can be uploaded any number of times without double-counting.
class OfflineSaleDraft {
  const OfflineSaleDraft({
    required this.clientSaleId,
    required this.soldAt,
    required this.items,
    required this.payments,
    this.clientReceiptNumber,
    this.customerId,
    this.notes,
    this.discountAmount = 0,
    this.expectedTotal,
  });

  final String clientSaleId;

  /// Receipt number the device printed, if any.
  final String? clientReceiptNumber;

  /// Device-local time of the sale; the server reports it on this business
  /// day, not the day it was uploaded.
  final DateTime soldAt;
  final int? customerId;
  final String? notes;
  final double discountAmount;

  /// Total the device showed the customer, so the server can flag drift.
  final double? expectedTotal;
  final List<OfflineSaleItem> items;
  final List<PaymentInput> payments;

  Map<String, dynamic> toJson() => {
    'clientSaleId': clientSaleId,
    'clientReceiptNumber': ?clientReceiptNumber,
    'soldAt': formatLocalDateTime(soldAt),
    'customerId': ?customerId,
    'notes': ?notes,
    if (discountAmount > 0) 'discountAmount': discountAmount,
    'expectedTotal': ?expectedTotal,
    'items': [for (final item in items) item.toJson()],
    'payments': [for (final payment in payments) payment.toJson()],
  };

  factory OfflineSaleDraft.fromJson(Map<String, dynamic> json) =>
      OfflineSaleDraft(
        clientSaleId: toStr(json['clientSaleId']),
        clientReceiptNumber: toStrOrNull(json['clientReceiptNumber']),
        soldAt: toDateTime(json['soldAt']) ?? DateTime.now(),
        customerId: toIntOrNull(json['customerId']),
        notes: toStrOrNull(json['notes']),
        discountAmount: toDouble(json['discountAmount']),
        expectedTotal: toDoubleOrNull(json['expectedTotal']),
        items: toMapList(json['items'])
            .map(OfflineSaleItem.fromJson)
            .toList(growable: false),
        payments: toMapList(json['payments'])
            .map(PaymentInput.fromJson)
            .toList(growable: false),
      );
}

/// Where a queued sale is in its life. Uploaded sales leave the queue, so
/// there is no "done" state.
enum QueuedSaleStatus {
  /// Waiting to be uploaded (or re-tried after a connection error).
  pending,

  /// The server refused it (`REJECTED`); needs a human decision.
  rejected;

  static QueuedSaleStatus parse(String? value) =>
      value == 'REJECTED' ? rejected : pending;

  String get wireName => this == rejected ? 'REJECTED' : 'PENDING';
}

/// One row of the device's outbox: the draft plus its upload bookkeeping.
class QueuedSale {
  const QueuedSale({
    required this.draft,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.error,
    this.lastAttemptAt,
  });

  final OfflineSaleDraft draft;
  final QueuedSaleStatus status;
  final int attempts;
  final DateTime createdAt;
  final String? error;
  final DateTime? lastAttemptAt;

  String get clientSaleId => draft.clientSaleId;
}
