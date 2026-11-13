import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/sync/device_identity.dart';
import 'package:kantemba/core/sync/sale_uploader.dart';
import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/data/models/sale_models.dart';
import 'package:kantemba/data/models/sync_models.dart';
import 'package:kantemba/data/services/sync_api.dart';

import 'support/fake_server.dart';

OfflineSaleDraft draft(String id, {int productId = 1, int quantity = 1}) =>
    OfflineSaleDraft(
      clientSaleId: id,
      clientReceiptNumber: 'OFF-$id',
      soldAt: DateTime(2026, 11, 13, 9, 30),
      expectedTotal: 11.6,
      items: [
        OfflineSaleItem(
          productId: productId,
          productName: 'Milk',
          quantity: quantity,
          unitPrice: 10,
          vatRate: 16,
          zraTaxType: 'A',
        ),
      ],
      payments: const [PaymentInput(paymentMethodId: 1)],
    );

void main() {
  sqfliteFfiInit();

  late LocalStore store;
  late FakeServer server;

  setUp(() async {
    store = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    server = FakeServer();
  });

  tearDown(() => store.close());

  SaleUploader uploader({int batchSize = 50}) => SaleUploader(
    api: SyncApi(
      ApiClient(
        baseUrl: 'http://till.test/api/v1',
        tokenProvider: () async => 't',
        httpClient: server.client,
      ),
    ),
    queue: store.saleQueue,
    meta: store.meta,
    identity: DeviceIdentity(store.meta),
    appVersion: '1.0.0+1',
    batchSize: batchSize,
    clock: () => DateTime(2026, 11, 13, 12),
  );

  Future<void> queue(Iterable<String> ids) async {
    var minute = 0;
    for (final id in ids) {
      await store.saleQueue.enqueue(
        draft(id),
        now: DateTime(2026, 11, 13, 10, minute++ % 60),
      );
    }
  }

  List<Map<String, dynamic>> uploads() => [
    for (final r in server.posts('/sync/sales')) server.bodyOf(r),
  ];

  List<Map<String, dynamic>> heartbeats() => [
    for (final r in server.posts('/sync/heartbeat')) server.bodyOf(r),
  ];

  test('sends queued sales and removes the ones the server recorded', () async {
    await queue(['sale-0001', 'sale-0002']);

    final result = await uploader().run();

    expect(result.ok, isTrue);
    expect(result.uploaded, 2);
    expect(result.pending, 0);
    expect(await store.saleQueue.all(), isEmpty);

    final body = uploads().single;
    expect(body['deviceId'], await DeviceIdentity(store.meta).deviceId());
    expect(body['pendingQueueSize'], 0);
    final sales = (body['sales'] as List).cast<Map<String, dynamic>>();
    expect(sales.map((s) => s['clientSaleId']), ['sale-0001', 'sale-0002']);
    expect(sales.first['soldAt'], '2026-11-13T09:30:00');
    expect(sales.first['clientReceiptNumber'], 'OFF-sale-0001');
    expect(sales.first['expectedTotal'], 11.6);
    expect((sales.first['items'] as List).single, containsPair('productName', 'Milk'));
    expect(
      await store.meta.get(SyncMeta.lastUploadKey),
      '2026-11-13T12:00:00',
    );
  });

  test('a sale the server already has is dropped, not counted again', () async {
    await queue(['sale-0001']);
    server.uploadedSaleIds.add('sale-0001');

    final result = await uploader().run();

    expect(result.uploaded, 0);
    expect(result.duplicates, 1);
    expect(await store.saleQueue.all(), isEmpty);
  });

  test('a rejected sale stays with the server\'s reason and is not resent',
      () async {
    await queue(['sale-0001', 'sale-0002']);
    server.rejectedSaleIds['sale-0002'] = 'soldAt is in the future';

    final first = await uploader().run();
    expect(first.uploaded, 1);
    expect(first.rejected, 1);
    expect(first.pending, 0);

    final kept = (await store.saleQueue.all()).single;
    expect(kept.clientSaleId, 'sale-0002');
    expect(kept.status, QueuedSaleStatus.rejected);
    expect(kept.error, 'soldAt is in the future');

    server.requests.clear();
    final second = await uploader().run();
    expect(second.rejected, 0);
    expect(uploads(), isEmpty);
    // It still counts as waiting on this till.
    expect(heartbeats().single['pendingQueueSize'], 1);

    await store.saleQueue.requeue('sale-0002');
    server.rejectedSaleIds.clear();
    expect((await uploader().run()).uploaded, 1);
    expect(await store.saleQueue.all(), isEmpty);
  });

  test('conflicts the server flags are counted for the manager', () async {
    await queue(['sale-0001', 'sale-0002']);
    server.uploadConflicts = ['NEGATIVE_STOCK'];

    final result = await uploader().run();

    expect(result.uploaded, 2);
    expect(result.conflicts, 2);
    expect(await store.saleQueue.all(), isEmpty);
  });

  test('a long queue goes up in batches, oldest first', () async {
    await queue([for (var i = 1; i <= 120; i++) 'sale-${i.toString().padLeft(4, '0')}']);

    final result = await uploader(batchSize: 50).run();

    expect(result.uploaded, 120);
    final batches = uploads();
    expect(batches.map((b) => (b['sales'] as List).length), [50, 50, 20]);
    expect(batches.map((b) => b['pendingQueueSize']), [70, 20, 0]);
    expect(
      (batches.first['sales'] as List).first['clientSaleId'],
      'sale-0001',
    );
    expect(
      (batches.last['sales'] as List).last['clientSaleId'],
      'sale-0120',
    );
  });

  test('with no connection the queue is untouched and retried later',
      () async {
    await queue(['sale-0001']);
    server.offline = true;

    final failed = await uploader().run();

    expect(failed.ok, isFalse);
    expect(failed.unreachable, isTrue);
    expect(failed.pending, 1);
    final waiting = (await store.saleQueue.pending()).single;
    expect(waiting.attempts, 1);
    expect(waiting.status, QueuedSaleStatus.pending);

    server.offline = false;
    final retried = await uploader().run();
    expect(retried.uploaded, 1);
    expect(await store.saleQueue.all(), isEmpty);
    expect(server.uploadedSaleIds, {'sale-0001'});
  });

  test('a reply lost after the server recorded the sales costs nothing',
      () async {
    await queue(['sale-0001', 'sale-0002']);
    server.uploadLosesReply = true;

    final lost = await uploader().run();
    expect(lost.unreachable, isTrue);
    expect(await store.saleQueue.pendingCount(), 2);
    expect(server.uploadedSaleIds, {'sale-0001', 'sale-0002'});

    server.uploadLosesReply = false;
    final retried = await uploader().run();

    expect(retried.uploaded, 0);
    expect(retried.duplicates, 2);
    expect(await store.saleQueue.all(), isEmpty);
    expect(server.uploadedSaleIds, hasLength(2));
  });

  test('a refusal of the whole request stops the run and keeps every sale',
      () async {
    await queue(['sale-0001', 'sale-0002']);
    server.uploadFailureStatus = 400;

    final result = await uploader().run();

    expect(result.ok, isFalse);
    expect(result.unreachable, isFalse);
    expect(result.error, contains('deactivated'));
    expect(uploads(), hasLength(1)); // one attempt, not a retry loop
    expect(server.uploadedSaleIds, isEmpty);
    expect(await store.saleQueue.pendingCount(), 2);
    expect(await store.saleQueue.rejectedCount(), 0);
  });

  test('an answer that settles nothing does not loop forever', () async {
    await queue(['sale-0001']);
    server.uploadAnswersNothing = true;

    final result = await uploader().run();

    expect(result.ok, isFalse);
    expect(result.error, contains('did not settle'));
    expect(server.posts('/sync/sales'), hasLength(1));
    expect(await store.saleQueue.pendingCount(), 1);
  });

  test('overlapping runs share one upload', () async {
    await queue(['sale-0001']);
    final up = uploader();

    final results = await Future.wait([up.run(), up.run()]);

    expect(results[0], same(results[1]));
    expect(results[0].uploaded, 1);
    expect(server.posts('/sync/sales'), hasLength(1));
  });

  test('a failure inside the app is reported, not thrown', () async {
    final broken = await LocalStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final up = SaleUploader(
      api: SyncApi(
        ApiClient(
          baseUrl: 'http://till.test/api/v1',
          tokenProvider: () async => 't',
          httpClient: server.client,
        ),
      ),
      queue: broken.saleQueue,
      meta: broken.meta,
      identity: DeviceIdentity(broken.meta),
    );
    await broken.close();

    final result = await up.run();

    expect(result.ok, isFalse);
    expect(result.error, startsWith('Upload failed'));
  });

  test('an empty queue still tells the server the till is online', () async {
    final result = await uploader().run();

    expect(result.ok, isTrue);
    expect(uploads(), isEmpty);
    final beat = heartbeats().single;
    expect(beat['online'], true);
    expect(beat['pendingQueueSize'], 0);
    expect(beat['appVersion'], '1.0.0+1');
    expect(beat['deviceId'], await DeviceIdentity(store.meta).deviceId());
  });

  test('no heartbeat is attempted when the server cannot be reached',
      () async {
    server.offline = true;
    await uploader().run();
    server.offline = false;
    expect(heartbeats(), isEmpty);
  });

  group('Session', () {
    Session newSession({
      Stream<bool>? connectivity,
      Duration? uploadRetryInterval,
      Duration? catalogSyncInterval,
    }) => Session(
      tokenStore: MemoryTokenStore(),
      httpClient: server.client,
      localStore: store,
      catalogSyncInterval: catalogSyncInterval,
      uploadRetryInterval: uploadRetryInterval,
      connectivity: connectivity,
    );

    Future<void> until(FutureOr<bool> Function() done) async {
      for (var i = 0; i < 100 && !await done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await done(), isTrue, reason: 'timed out waiting');
    }

    List<String> syncCalls() => [
      for (final r in server.requests)
        if (r.url.path.contains('/sync/')) r.url.path.split('/').last,
    ];

    test('sales go up before the catalogue is pulled', () async {
      await queue(['sale-0001']);
      server.catalogProducts[1] = catalogItemJson(1, 'Milk', barcode: '6001');
      final session = newSession();

      await session.signIn(username: 'tester', password: 'secret');
      expect(await session.initialCatalogSync, isTrue);

      expect(syncCalls(), ['register', 'sales', 'heartbeat', 'catalog']);
      expect(await store.saleQueue.all(), isEmpty);
    });

    test('when the connection returns, waiting sales are sent', () async {
      final network = StreamController<bool>();
      final session = newSession(connectivity: network.stream);
      await session.signIn(username: 'tester', password: 'secret');
      await session.initialCatalogSync;

      await queue(['sale-0001']);
      server.requests.clear();
      network.add(true);

      await until(() => server.uploadedSaleIds.contains('sale-0001'));
      await until(() => syncCalls().contains('catalog'));
      expect(await store.saleQueue.all(), isEmpty);
      await network.close();
    });

    test('with no network at all, checkout goes straight to the cache',
        () async {
      final network = StreamController<bool>();
      final session = newSession(connectivity: network.stream);
      await session.signIn(username: 'tester', password: 'secret');
      await session.initialCatalogSync;
      expect(session.isOffline, isFalse);

      network.add(false);
      await until(() => session.isOffline);

      network.add(true);
      await until(() => !session.isOffline);
      await network.close();
    });

    test('a signed-out till forgets that the network was gone', () async {
      final network = StreamController<bool>();
      final session = newSession(connectivity: network.stream);
      await session.signIn(username: 'tester', password: 'secret');
      network.add(false);
      await until(() => session.isOffline);

      await session.signOut();

      expect(session.isOffline, isFalse);
      await network.close();
    });

    test('waiting sales are retried on a timer', () async {
      final session = newSession(
        uploadRetryInterval: const Duration(milliseconds: 30),
      );
      await session.signIn(username: 'tester', password: 'secret');
      await session.initialCatalogSync;

      server.offline = true;
      await queue(['sale-0001']);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(server.uploadedSaleIds, isEmpty);

      server.offline = false;
      await until(() => server.uploadedSaleIds.contains('sale-0001'));
      await until(() async => await store.saleQueue.pendingCount() == 0);
      await session.signOut(); // stops the timer
    });
  });
}
