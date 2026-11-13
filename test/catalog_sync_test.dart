import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/sync/catalog_repository.dart';
import 'package:kantemba/core/sync/catalog_sync.dart';
import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/data/services/pos_api.dart';
import 'package:kantemba/data/services/sync_api.dart';

import 'support/fake_server.dart';

void main() {
  sqfliteFfiInit();

  late LocalStore store;
  late FakeServer server;
  late ApiClient client;

  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    server = FakeServer();
    client = ApiClient(
      baseUrl: 'http://till.test/api/v1',
      tokenProvider: () async => 't',
      httpClient: server.client,
    );
  });

  tearDown(() => store.close());

  CatalogSync newSync() => CatalogSync(
    api: SyncApi(client),
    cache: store.catalog,
    meta: store.meta,
    clock: () => DateTime(2026, 11, 12, 10, 5),
  );

  Iterable<String?> sinceValues() => server.requests
      .where((r) => r.url.path.endsWith('/sync/catalog'))
      .map((r) => r.url.queryParameters['since']);

  group('CatalogSync', () {
    test('the first pull is a full snapshot and fills the cache', () async {
      server.catalogProducts
        ..[1] = catalogItemJson(1, 'Milk', barcode: '6001', categoryId: 1)
        ..[2] = catalogItemJson(2, 'Bread', barcode: '6002');

      expect(await newSync().sync(), isTrue);

      expect(sinceValues(), [null]);
      expect(await store.catalog.productCount(), 2);
      final milk = await store.catalog.productByBarcode('6001');
      expect(milk!.name, 'Milk');
      expect(milk.categoryName, 'Groceries');
      expect((await store.catalog.paymentMethods()).single.name, 'Cash');
      expect(
        await store.meta.get(SyncMeta.catalogSinceKey),
        '2026-11-12T10:00:00.123456',
      );
      expect(
        await store.meta.get(SyncMeta.lastCatalogSyncKey),
        '2026-11-12T10:05:00',
      );
    });

    test('later pulls send the bookmark and apply only the changes', () async {
      server.catalogProducts
        ..[1] = catalogItemJson(1, 'Milk', barcode: '6001', price: 10)
        ..[2] = catalogItemJson(2, 'Bread', barcode: '6002');
      final sync = newSync();
      await sync.sync();

      server.catalogProducts[1] =
          catalogItemJson(1, 'Milk', barcode: '6001', price: 12);
      server.catalogChangedIds.add(1);
      server.catalogServerTime = '2026-11-12T11:00:00';
      await sync.sync();

      expect(sinceValues(), [null, '2026-11-12T10:00:00.123456']);
      expect((await store.catalog.productById(1))!.price, 12);
      expect((await store.catalog.productById(2))!.name, 'Bread');
      expect(
        await store.meta.get(SyncMeta.catalogSinceKey),
        '2026-11-12T11:00:00',
      );
    });

    test('products deleted on the server disappear from the cache', () async {
      server.catalogProducts
        ..[1] = catalogItemJson(1, 'Milk', barcode: '6001')
        ..[2] = catalogItemJson(2, 'Bread', barcode: '6002');
      final sync = newSync();
      await sync.sync();

      server.catalogProducts.remove(2);
      await sync.sync();

      expect(await store.catalog.productById(2), isNull);
      expect(await store.catalog.productCount(), 1);
    });

    test('a failed pull keeps the old cache and the old bookmark', () async {
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final sync = newSync();
      await sync.sync();

      server.catalogFails = true;
      expect(await sync.sync(), isFalse);
      server.catalogFails = false;
      server.offline = true;
      expect(await sync.sync(), isFalse);

      expect(await store.catalog.productCount(), 1);
      expect(
        await store.meta.get(SyncMeta.catalogSinceKey),
        '2026-11-12T10:00:00.123456',
      );
    });

    test('overlapping calls share one pull', () async {
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final sync = newSync();
      final results = await Future.wait([sync.sync(), sync.sync()]);

      expect(results, [true, true]);
      expect(sinceValues(), hasLength(1));
    });

    test('reset makes the next pull a full snapshot again', () async {
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final sync = newSync();
      await sync.sync();
      await sync.reset();
      await sync.sync();

      expect(sinceValues(), [null, null]);
    });
  });

  group('CatalogRepository', () {
    var now = DateTime(2026, 11, 12, 10);

    CatalogRepository newRepo() => CatalogRepository(
      pos: PosApi(client),
      cache: store.catalog,
      clock: () => now,
    );

    setUp(() => now = DateTime(2026, 11, 12, 10));

    Future<void> seedCache() async {
      server.catalogProducts[1] = catalogItemJson(
        1,
        'Cached Milk',
        barcode: '6001',
        price: 10,
      );
      await newSync().sync();
    }

    int barcodeCalls() =>
        server.requests.where((r) => r.url.path.endsWith('/by-barcode')).length;

    test('online, the server answers and refreshes the cache', () async {
      server.products['6001'] = productJson(
        1,
        '6001',
        name: 'Live Milk',
        price: 11,
      );
      final repo = newRepo();

      final product = await repo.findByBarcode('6001');

      expect(product!.name, 'Live Milk');
      expect(repo.isOffline, isFalse);
      final cached = await store.catalog.productByBarcode('6001');
      expect(cached!.name, 'Live Milk');
      expect(cached.price, 11);
    });

    test('an unknown barcode on the server is not looked up in the cache',
        () async {
      await seedCache();
      server.products.clear();

      expect(await newRepo().findByBarcode('6001'), isNull);
    });

    test('offline, a cached product is found without the server', () async {
      await seedCache();
      server.offline = true;
      final repo = newRepo();

      final product = await repo.findByBarcode('6001');

      expect(product!.name, 'Cached Milk');
      expect(repo.isOffline, isTrue);
      expect(await repo.findByBarcode('0000'), isNull);
    });

    test('after a failure the server is skipped until the hold passes',
        () async {
      await seedCache();
      final repo = newRepo();
      server.offline = true;
      await repo.findByBarcode('6001');

      server.offline = false;
      server.products['6001'] = productJson(1, '6001', name: 'Live Milk');
      server.requests.clear();
      expect((await repo.findByBarcode('6001'))!.name, 'Cached Milk');
      expect(barcodeCalls(), 0);

      now = now.add(const Duration(seconds: 16));
      expect((await repo.findByBarcode('6001'))!.name, 'Live Milk');
      expect(barcodeCalls(), 1);
      expect(repo.isOffline, isFalse);
    });

    test('with nothing cached the connection error is not hidden', () async {
      server.offline = true;

      await expectLater(
        newRepo().findByBarcode('6001'),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
      );
    });

    test('a server error is believed, not papered over with the cache',
        () async {
      await seedCache();
      server.barcodeFails = true;
      final repo = newRepo();

      await expectLater(
        repo.findByBarcode('6001'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(repo.isOffline, isFalse);
    });

    test('payment methods and the product list fall back to the cache',
        () async {
      await seedCache();
      final repo = newRepo();
      server.offline = true;

      expect((await repo.paymentMethods()).single.code, 'CASH');
      expect((await repo.allProducts()).single.name, 'Cached Milk');
    });
  });

  group('Session', () {
    test('signing in registers the till, then pulls the catalogue', () async {
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final session = Session(
        tokenStore: MemoryTokenStore(),
        httpClient: server.client,
        localStore: store,
        catalogSyncInterval: null,
      );
      await session.signIn(username: 'tester', password: 'secret');
      expect(await session.initialCatalogSync, isTrue);

      final order = [
        for (final r in server.requests)
          if (r.url.path.contains('/sync/')) r.url.path.split('/').last,
      ];
      expect(order, ['register', 'catalog']);
      expect(await store.catalog.productCount(), 1);
    });

    test('checkout reads fall back to the cache when the server is down',
        () async {
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final session = Session(
        tokenStore: MemoryTokenStore(),
        httpClient: server.client,
        localStore: store,
        catalogSyncInterval: null,
      );
      await session.signIn(username: 'tester', password: 'secret');
      await session.initialCatalogSync;

      server.offline = true;

      expect((await session.productLookup.findByBarcode('6001'))!.name, 'Milk');
      expect((await session.loadPaymentMethods()).single.code, 'CASH');
    });
  });
}
