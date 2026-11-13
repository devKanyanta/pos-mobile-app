import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/core/checkout/cart.dart';
import 'package:kantemba/core/checkout/checkout_service.dart';
import 'package:kantemba/core/checkout/offline_sales.dart';
import 'package:kantemba/core/checkout/sale_totals.dart';
import 'package:kantemba/core/receipt/receipt_data.dart';
import 'package:kantemba/core/receipt/receipt_pdf.dart';
import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/sync/catalog_repository.dart';
import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/data/models/sale_models.dart';
import 'package:kantemba/data/models/sync_models.dart';
import 'package:kantemba/data/services/pos_api.dart';
import 'package:kantemba/data/services/sales_api.dart';

import 'support/fake_server.dart';

Product product(
  int id,
  String name, {
  double price = 10,
  double vatRate = 16,
  int stock = 5,
  bool tracked = true,
}) => CatalogProduct(
  id: id,
  name: name,
  sku: null,
  barcode: 'BC$id',
  price: price,
  vatRate: vatRate,
  zraTaxType: 'A',
  trackInventory: tracked,
  stockQuantity: stock,
  active: true,
  categoryId: null,
  updatedAt: null,
).toProduct();

const cash = PaymentMethod(
  id: 1,
  name: 'Cash',
  code: 'CASH',
  isActive: true,
  type: 'CASH',
  requiresReference: false,
);
const mtn = PaymentMethod(
  id: 2,
  name: 'MTN Mobile Money',
  code: 'MTN',
  isActive: true,
  type: 'MOBILE_MONEY',
  requiresReference: true,
);

void main() {
  sqfliteFfiInit();

  late LocalStore store;
  late FakeServer server;
  late OfflineSales offline;
  var now = DateTime(2026, 11, 13, 9, 30, 0);

  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    server = FakeServer();
    now = DateTime(2026, 11, 13, 9, 30, 0);
    offline = OfflineSales(
      queue: store.saleQueue,
      meta: store.meta,
      clock: () => now,
    );
  });

  tearDown(() => store.close());

  Cart cartOf(List<(Product, int)> lines) {
    final cart = Cart();
    for (final (p, qty) in lines) {
      cart.add(p, quantity: qty);
    }
    return cart;
  }

  group('SaleTotals', () {
    test('VAT is rounded half-up per line, like the server', () {
      // 0.50 at 5% is 0.025 a line, which rounds up to 0.03; two such lines
      // give 0.06, where rounding only the sum would give 0.05.
      final totals = SaleTotals.ofCart(
        cartOf([
          (product(1, 'A', price: 0.5, vatRate: 5), 1),
          (product(2, 'B', price: 0.5, vatRate: 5), 1),
        ]),
      );
      expect(totals.lines.map((l) => l.vatCents), [3, 3]);
      expect(totals.vat, 0.06);
      expect(totals.subtotal, 1.0);
      expect(totals.total, 1.06);
    });

    test('a standard-rated, a zero-rated and a larger line', () {
      final totals = SaleTotals.ofCart(
        cartOf([
          (product(1, 'Milk', price: 10, vatRate: 16), 2),
          (product(2, 'Bread', price: 12.5, vatRate: 0), 1),
          (product(3, 'Soap', price: 3.35, vatRate: 16), 3),
        ]),
      );
      // 20.00 -> 3.20; 12.50 -> 0; 10.05 -> 1.608 -> 1.61
      expect(totals.lines.map((l) => l.netCents), [2000, 1250, 1005]);
      expect(totals.lines.map((l) => l.vatCents), [320, 0, 161]);
      expect(totals.subtotalCents, 4255);
      expect(totals.vatCents, 481);
      expect(totals.totalCents, 4736);
    });

    test('cents never drift the way floating point sums do', () {
      final totals = SaleTotals.ofCart(
        cartOf([(product(1, 'Sweet', price: 0.1, vatRate: 0), 3)]),
      );
      expect(totals.totalCents, 30);
      expect(totals.total, 0.3);
    });
  });

  group('OfflineSales', () {
    PaymentInput exact() => const PaymentInput(paymentMethodId: 1);

    test('queues the sale as the upload will send it', () async {
      final cart = cartOf([(product(1, 'Milk'), 2)]);

      final sale = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cart,
        method: cash,
        payment: exact(),
        customerId: 7,
      );

      final queued = (await store.saleQueue.pending()).single;
      final json = queued.draft.toJson();
      expect(json['clientSaleId'], 'sale-0001');
      expect(json['clientReceiptNumber'], 'OFF-0001');
      expect(json['soldAt'], '2026-11-13T09:30:00');
      expect(json['customerId'], 7);
      expect(json['expectedTotal'], 23.2);
      final item = (json['items'] as List).single as Map;
      expect(item['productId'], 1);
      expect(item['productName'], 'Milk');
      expect(item['quantity'], 2);
      expect(item['unitPrice'], 10.0);
      expect(item['vatRate'], 16.0);
      expect(item['zraTaxType'], 'A');
      expect((json['payments'] as List).single, {'paymentMethodId': 1});

      expect(sale.offline, isTrue);
      expect(sale.id, 0);
      expect(sale.saleNumber, 'OFF-0001');
      expect(sale.receiptNumber, 'OFF-0001');
      expect(sale.subtotal, 20.0);
      expect(sale.vatAmount, 3.2);
      expect(sale.totalAmount, 23.2);
      expect(sale.amountPaid, 23.2);
      expect(sale.balanceDue, 0);
      expect(sale.changeGiven, 0);
      expect(sale.paymentStatus, 'PAID');
      expect(sale.soldAt, now);
      expect(sale.items.single.productName, 'Milk');
      expect(sale.items.single.lineTotal, 20.0);
      expect(sale.items.single.totalAmount, 23.2);
      expect(sale.items.single.vatAmount, 3.2);
      expect(sale.payments.single.paymentMethodName, 'Cash');
    });

    testWidgets('its receipt can be saved or printed as a PDF', (tester) async {
      final sale = await tester.runAsync(
        () => offline.record(
          clientSaleId: 'sale-0001',
          cart: cartOf([(product(1, 'Milk'), 2)]),
          method: cash,
          payment: exact(),
        ),
      );
      final bytes = await tester.runAsync(
        () => buildReceiptPdf(ReceiptData(sale: sale!)),
      );

      expect(ascii.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1500));
    });

    test('cash over the total gives change', () async {
      final sale = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cartOf([(product(1, 'Milk'), 1)]),
        method: cash,
        payment: const PaymentInput(paymentMethodId: 1, amount: 20),
      );

      expect(sale.totalAmount, 11.6);
      expect(sale.amountPaid, 11.6);
      expect(sale.changeGiven, 8.4);
      expect(sale.paymentStatus, 'PAID');
      expect(sale.payments.single.amountTendered, 20.0);
      expect(sale.payments.single.amount, 11.6);
      expect(sale.payments.single.changeAmount, 8.4);
    });

    test('cash under the total is a part payment with a balance', () async {
      final sale = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cartOf([(product(1, 'Milk'), 1)]),
        method: cash,
        payment: const PaymentInput(paymentMethodId: 1, amount: 5),
      );

      expect(sale.amountPaid, 5.0);
      expect(sale.balanceDue, 6.6);
      expect(sale.paymentStatus, 'PARTIALLY_PAID');
    });

    test('a mobile money reference is kept on the sale and the receipt',
        () async {
      final sale = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cartOf([(product(1, 'Milk'), 1)]),
        method: mtn,
        payment: const PaymentInput(
          paymentMethodId: 2,
          transactionReference: 'MM998877',
        ),
      );

      expect(sale.payments.single.transactionReference, 'MM998877');
      final queued = (await store.saleQueue.pending()).single;
      expect(queued.draft.payments.single.transactionReference, 'MM998877');
    });

    test('recording the same sale again returns it instead of queueing twice',
        () async {
      final cart = cartOf([(product(1, 'Milk'), 1)]);
      final first = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cart,
        method: cash,
        payment: exact(),
      );
      now = now.add(const Duration(minutes: 5));
      final again = await offline.record(
        clientSaleId: 'sale-0001',
        cart: cart,
        method: cash,
        payment: exact(),
      );

      expect(await store.saleQueue.pendingCount(), 1);
      expect(again.saleNumber, first.saleNumber);
      expect(again.soldAt, first.soldAt);
    });

    test('receipt numbers count up and survive a restart', () async {
      Future<String> sell(String id) async => (await offline.record(
        clientSaleId: id,
        cart: cartOf([(product(1, 'Milk'), 1)]),
        method: cash,
        payment: exact(),
      )).saleNumber;

      expect(await sell('sale-0001'), 'OFF-0001');
      expect(await sell('sale-0002'), 'OFF-0002');

      final restarted = OfflineSales(queue: store.saleQueue, meta: store.meta);
      expect(
        (await restarted.record(
          clientSaleId: 'sale-0003',
          cart: cartOf([(product(1, 'Milk'), 1)]),
          method: cash,
          payment: exact(),
        )).saleNumber,
        'OFF-0003',
      );
    });
  });

  group('CheckoutService offline', () {
    CheckoutService service({bool Function()? preferOffline}) =>
        CheckoutService(
          SalesApi(
            ApiClient(
              baseUrl: 'http://till.test/api/v1',
              tokenProvider: () async => 't',
              httpClient: server.client,
            ),
          ),
          idGenerator: () => 'sale-0001',
          offline: offline,
          preferOffline: preferOffline,
        );

    Cart oneMilk() => cartOf([(product(1, 'Milk'), 1)]);

    test('online, the server records the sale and nothing is queued',
        () async {
      final sale = await service().complete(oneMilk(), cash);

      expect(sale.offline, isFalse);
      expect(sale.saleNumber, 'S-0007');
      expect(await store.saleQueue.pendingCount(), 0);
    });

    test('a lost connection saves the sale on the device', () async {
      server.offline = true;
      final checkout = service();

      final sale = await checkout.complete(oneMilk(), cash);

      expect(sale.offline, isTrue);
      expect(await store.saleQueue.pendingCount(), 1);
      expect(
        (await store.saleQueue.pending()).single.clientSaleId,
        'sale-0001',
      );
      expect(checkout.pendingClientSaleId, isNull);
    });

    test('a refusal from the server is not saved offline', () async {
      server.saleFailureStatus = 400;

      await expectLater(
        service().complete(oneMilk(), cash),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
      );
      expect(await store.saleQueue.pendingCount(), 0);
    });

    test('when the server was just unreachable it is not asked again',
        () async {
      final sale = await service(preferOffline: () => true).complete(
        oneMilk(),
        cash,
      );

      expect(sale.offline, isTrue);
      expect(server.posts('/sales'), isEmpty);
    });

    test('without an offline recorder a lost connection is still an error',
        () async {
      server.offline = true;
      final plain = CheckoutService(
        SalesApi(
          ApiClient(
            baseUrl: 'http://till.test/api/v1',
            tokenProvider: () async => 't',
            httpClient: server.client,
          ),
        ),
      );

      await expectLater(
        plain.complete(oneMilk(), cash),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('stock shown at checkout', () {
    CatalogRepository repo() => CatalogRepository(
      pos: PosApi(
        ApiClient(
          baseUrl: 'http://till.test/api/v1',
          tokenProvider: () async => 't',
          httpClient: server.client,
        ),
      ),
      cache: store.catalog,
      queue: store.saleQueue,
    );

    Future<void> sellOffline(Product p, int qty, String id) => offline.record(
      clientSaleId: id,
      cart: cartOf([(p, qty)]),
      method: cash,
      payment: const PaymentInput(paymentMethodId: 1),
    );

    test('units sold offline come off the cached stock', () async {
      final milk = product(1, 'Milk', stock: 5);
      await store.catalog.applyProducts([CatalogProduct.fromProduct(milk)]);
      await sellOffline(milk, 2, 'sale-0001');
      server.offline = true;

      final found = await repo().findByBarcode('BC1');
      expect(found!.stockQuantity, 3);
      expect((await repo().allProducts()).single.stockQuantity, 3);
    });

    test('the server count is reduced too while the sale is still queued',
        () async {
      final milk = product(1, 'Milk', stock: 5);
      await store.catalog.applyProducts([CatalogProduct.fromProduct(milk)]);
      await sellOffline(milk, 2, 'sale-0001');
      server.products['BC1'] = productJson(1, 'BC1', name: 'Milk', stock: 5);

      expect((await repo().findByBarcode('BC1'))!.stockQuantity, 3);
    });

    test('it never goes below zero and ignores untracked products', () async {
      final milk = product(1, 'Milk', stock: 2);
      final service = product(2, 'Charging', stock: 0, tracked: false);
      await store.catalog.applyProducts([
        CatalogProduct.fromProduct(milk),
        CatalogProduct.fromProduct(service),
      ]);
      await sellOffline(milk, 4, 'sale-0001');
      await sellOffline(service, 3, 'sale-0002');
      server.offline = true;

      expect((await repo().findByBarcode('BC1'))!.stockQuantity, 0);
      expect((await repo().findByBarcode('BC2'))!.stockQuantity, 0);
    });

    test('once a sale is uploaded the stock is the server\'s again', () async {
      final milk = product(1, 'Milk', stock: 5);
      await store.catalog.applyProducts([CatalogProduct.fromProduct(milk)]);
      await sellOffline(milk, 2, 'sale-0001');
      await store.saleQueue.markUploaded('sale-0001');
      server.offline = true;

      expect((await repo().findByBarcode('BC1'))!.stockQuantity, 5);
    });
  });

  group('Session', () {
    test('keeps the business profile for receipts made offline', () async {
      server.merchant = {
        'accountId': 'ACC-1',
        'businessName': 'Mapalo General Dealers',
        'tpin': '1002345678',
        'receiptFooter': 'Thank you!',
        'plan': 'SME',
        'features': {'ZRA': true},
      };
      final session = Session(
        tokenStore: MemoryTokenStore(),
        httpClient: server.client,
        localStore: store,
        catalogSyncInterval: null,
      );
      expect(await session.cachedMerchant(), isNull);

      await session.signIn(username: 'tester', password: 'secret');
      expect(await session.initialCatalogSync, isTrue);

      final merchant = await session.cachedMerchant();
      expect(merchant!.businessName, 'Mapalo General Dealers');
      expect(merchant.receiptFooter, 'Thank you!');
      expect(merchant.hasFeature('ZRA'), isTrue);
    });

    test('an offline sale prints with the cached business details', () async {
      server.merchant = {
        'accountId': 'ACC-1',
        'businessName': 'Mapalo General Dealers',
        'plan': 'SME',
      };
      final session = Session(
        tokenStore: MemoryTokenStore(),
        httpClient: server.client,
        localStore: store,
        catalogSyncInterval: null,
      );
      await session.signIn(username: 'tester', password: 'secret');
      await session.initialCatalogSync;
      server.offline = true;

      final sale = await session.offlineSales!.record(
        clientSaleId: 'sale-0001',
        cart: cartOf([(product(1, 'Milk'), 1)]),
        method: cash,
        payment: const PaymentInput(paymentMethodId: 1),
      );
      final receipt = await session.offlineReceipt(sale);

      expect(receipt.businessName, 'Mapalo General Dealers');
      expect(receipt.receiptNumber, 'OFF-0001');
      expect(receipt.fiscal, isNull);
    });

    test('without a local store there is no offline recorder', () async {
      final session = await server.signedInSession();
      expect(session.offlineSales, isNull);
      expect(session.isOffline, isFalse);
    });
  });
}
