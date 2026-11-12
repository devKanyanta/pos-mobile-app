import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/data/models/sale_models.dart';
import 'package:kantemba/data/models/sync_models.dart';

CatalogProduct product(
  int id,
  String name, {
  String? barcode,
  String? sku,
  double price = 10,
  double vatRate = 16,
  bool active = true,
  int stock = 5,
  int? categoryId,
}) => CatalogProduct(
  id: id,
  name: name,
  sku: sku,
  barcode: barcode,
  price: price,
  vatRate: vatRate,
  zraTaxType: 'A',
  trackInventory: true,
  stockQuantity: stock,
  active: active,
  categoryId: categoryId,
  updatedAt: null,
);

OfflineSaleDraft draft(String id, {DateTime? soldAt}) => OfflineSaleDraft(
  clientSaleId: id,
  soldAt: soldAt ?? DateTime(2026, 11, 12, 9, 30, 15),
  customerId: 7,
  notes: 'offline',
  expectedTotal: 23.20,
  items: const [
    OfflineSaleItem(
      productId: 1,
      productName: 'Mealie Meal 5kg',
      quantity: 2,
      unitPrice: 10,
      vatRate: 16,
      zraTaxType: 'A',
    ),
  ],
  payments: const [
    PaymentInput(paymentMethodId: 2, amount: 23.20, transactionReference: 'MM-1'),
  ],
);

void main() {
  sqfliteFfiInit();

  late LocalStore store;

  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => store.close());

  group('CatalogCache', () {
    test('caches products and looks them up by barcode with category name',
        () async {
      await store.catalog.replaceCategories(
        const [Category(id: 3, name: 'Groceries')],
      );
      await store.catalog.applyProducts([
        product(1, 'Mealie Meal 5kg', barcode: '6001001000011', categoryId: 3),
        product(2, 'Phone Charging', price: 5, vatRate: 0),
      ]);

      final found = await store.catalog.productByBarcode('6001001000011');
      expect(found, isNotNull);
      expect(found!.name, 'Mealie Meal 5kg');
      expect(found.price, 10);
      expect(found.vatRate, 16);
      expect(found.categoryName, 'Groceries');
      expect(found.zraMapped, isTrue);

      expect(await store.catalog.productByBarcode('nope'), isNull);
      expect(await store.catalog.productCount(), 2);
    });

    test('a delta updates existing products in place', () async {
      await store.catalog.applyProducts([
        product(1, 'Bread', barcode: 'B1', price: 12),
      ]);
      await store.catalog.applyProducts([
        product(1, 'Bread Loaf', barcode: 'B1', price: 14, stock: 9),
      ]);

      final updated = await store.catalog.productById(1);
      expect(updated!.name, 'Bread Loaf');
      expect(updated.price, 14);
      expect(updated.stockQuantity, 9);
      expect(await store.catalog.productCount(), 1);
    });

    test('inactive products are hidden from lookup and search', () async {
      await store.catalog.applyProducts([
        product(1, 'Old Stock', barcode: 'OLD1', active: false),
      ]);
      expect(await store.catalog.productByBarcode('OLD1'), isNull);
      expect(await store.catalog.searchProducts('Old'), isEmpty);
      expect((await store.catalog.productById(1))!.active, isFalse);
    });

    test('removeProductsNotIn deletes what the server no longer has',
        () async {
      await store.catalog.applyProducts([
        product(1, 'Keep', barcode: 'K1'),
        product(2, 'Gone', barcode: 'G1'),
        product(3, 'Also gone'),
      ]);
      await store.catalog.removeProductsNotIn([1]);

      expect(await store.catalog.productCount(), 1);
      expect(await store.catalog.productById(1), isNotNull);
      expect(await store.catalog.productByBarcode('G1'), isNull);
    });

    test('search matches name substring, exact sku and exact barcode',
        () async {
      await store.catalog.applyProducts([
        product(1, 'Sugar 1kg', sku: 'SKU-9', barcode: 'SUG1'),
        product(2, 'Brown Sugar', barcode: 'SUG2'),
        product(3, 'Salt'),
      ]);

      expect((await store.catalog.searchProducts('sugar')).length, 2);
      expect((await store.catalog.searchProducts('SKU-9')).single.id, 1);
      expect((await store.catalog.searchProducts('sug2')).single.id, 2);
    });

    test('payment methods round-trip', () async {
      await store.catalog.replacePaymentMethods(const [
        PaymentMethod(
          id: 1,
          name: 'Cash',
          code: 'CASH',
          isActive: true,
          type: 'CASH',
          requiresReference: false,
        ),
        PaymentMethod(
          id: 2,
          name: 'MTN Mobile Money',
          code: 'MTN',
          isActive: true,
          type: 'MOBILE_MONEY',
          requiresReference: true,
        ),
      ]);

      final methods = await store.catalog.paymentMethods();
      expect(methods.length, 2);
      expect(methods.first.isCash, isTrue);
      expect(methods.last.requiresReference, isTrue);
    });
  });

  group('SaleQueue', () {
    test('an enqueued sale round-trips the full upload payload', () async {
      await store.saleQueue.enqueue(draft('c-1'));

      final queued = (await store.saleQueue.pending()).single;
      expect(queued.status, QueuedSaleStatus.pending);
      expect(queued.attempts, 0);

      final json = queued.draft.toJson();
      expect(json['clientSaleId'], 'c-1');
      expect(json['soldAt'], '2026-11-12T09:30:15');
      expect(json['customerId'], 7);
      expect(json['expectedTotal'], 23.20);
      final items = json['items'] as List;
      expect((items.single as Map)['productName'], 'Mealie Meal 5kg');
      final payments = json['payments'] as List;
      expect((payments.single as Map)['transactionReference'], 'MM-1');
    });

    test('enqueueing the same clientSaleId twice keeps one row', () async {
      await store.saleQueue.enqueue(draft('c-1'));
      await store.saleQueue.enqueue(draft('c-1'));
      expect(await store.saleQueue.pendingCount(), 1);
    });

    test('pending is oldest first and respects the limit', () async {
      await store.saleQueue.enqueue(
        draft('late'),
        now: DateTime(2026, 11, 12, 10),
      );
      await store.saleQueue.enqueue(
        draft('early'),
        now: DateTime(2026, 11, 12, 9),
      );

      final all = await store.saleQueue.pending();
      expect([for (final s in all) s.clientSaleId], ['early', 'late']);
      expect((await store.saleQueue.pending(limit: 1)).single.clientSaleId,
          'early');
    });

    test('upload bookkeeping: attempt, uploaded, rejected, requeue', () async {
      await store.saleQueue.enqueue(draft('c-1'));
      await store.saleQueue.enqueue(draft('c-2'));

      await store.saleQueue.recordAttempt(['c-1', 'c-2']);
      await store.saleQueue.markUploaded('c-1');
      await store.saleQueue.markRejected('c-2', 'soldAt is too old');

      expect(await store.saleQueue.pendingCount(), 0);
      expect(await store.saleQueue.rejectedCount(), 1);

      final rejected = (await store.saleQueue.all()).single;
      expect(rejected.clientSaleId, 'c-2');
      expect(rejected.status, QueuedSaleStatus.rejected);
      expect(rejected.error, 'soldAt is too old');
      expect(rejected.attempts, 1);
      expect(rejected.lastAttemptAt, isNotNull);

      await store.saleQueue.requeue('c-2');
      final requeued = (await store.saleQueue.pending()).single;
      expect(requeued.status, QueuedSaleStatus.pending);
      expect(requeued.error, isNull);

      await store.saleQueue.remove('c-2');
      expect(await store.saleQueue.all(), isEmpty);
    });
  });

  group('SyncMeta', () {
    test('set, overwrite, get and remove', () async {
      expect(await store.meta.get(SyncMeta.deviceIdKey), isNull);

      await store.meta.set(SyncMeta.deviceIdKey, 'till-01');
      await store.meta.set(SyncMeta.catalogSinceKey, '2026-11-12T08:00:00');
      expect(await store.meta.get(SyncMeta.deviceIdKey), 'till-01');

      await store.meta.set(SyncMeta.deviceIdKey, 'till-02');
      expect(await store.meta.get(SyncMeta.deviceIdKey), 'till-02');

      await store.meta.remove(SyncMeta.deviceIdKey);
      expect(await store.meta.get(SyncMeta.deviceIdKey), isNull);
      expect(await store.meta.get(SyncMeta.catalogSinceKey),
          '2026-11-12T08:00:00');
    });
  });

  test('data survives closing and reopening the database', () async {
    final dir = await Directory.systemTemp.createTemp('kantemba_store_test');
    final path = '${dir.path}/kantemba.db';
    try {
      var fileStore = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      await fileStore.catalog.applyProducts([product(1, 'Bread', barcode: 'B1')]);
      await fileStore.saleQueue.enqueue(draft('c-1'));
      await fileStore.meta.set(SyncMeta.deviceIdKey, 'till-01');
      await fileStore.close();

      fileStore = await LocalStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await fileStore.catalog.productByBarcode('B1'))!.name, 'Bread');
      expect(await fileStore.saleQueue.pendingCount(), 1);
      expect(await fileStore.meta.get(SyncMeta.deviceIdKey), 'till-01');
      await fileStore.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
