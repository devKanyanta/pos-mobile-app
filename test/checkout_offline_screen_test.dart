import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kantemba/core/session/session.dart';
import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/data/local/local_store.dart';
import 'package:kantemba/ui/checkout_screen.dart';

import 'support/fake_server.dart';

/// SQLite runs on a real isolate, which the test clock cannot advance, so each
/// step yields to the real event loop before pumping the widgets.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets(
    'with no connection a scanned product is sold, saved on the device and '
    'given an offline receipt',
    (tester) async {
      late FakeServer server;
      late LocalStore store;
      late Session session;
      await tester.runAsync(() async {
        store = await LocalStore.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        server = FakeServer()
          ..catalogProducts[1] = catalogItemJson(
            1,
            'Milk',
            barcode: '6001',
            price: 10,
            stock: 3,
          );
        session = Session(
          tokenStore: MemoryTokenStore(),
          httpClient: server.client,
          localStore: store,
          catalogSyncInterval: null,
        );
        await session.signIn(username: 'tester', password: 'secret');
        await session.initialCatalogSync;
        // The till goes offline after it has pulled the catalogue.
        server.offline = true;
        server.requests.clear();
      });
      addTearDown(() => tester.runAsync(store.close));

      await tester.pumpWidget(
        SessionScope(
          session: session,
          child: const MaterialApp(home: CheckoutScreen(active: false)),
        ),
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await _settle(tester);
      expect(find.text('Milk'), findsOneWidget);
      expect(find.textContaining('Added Milk'), findsOneWidget);

      await tester.tap(find.text('Pay'));
      await _settle(tester);
      await tester.tap(find.text('Cash'));
      await _settle(tester);
      await tester.tap(find.text('Continue')); // exact cash
      await _settle(tester);

      expect(find.text('Saved offline'), findsOneWidget);
      expect(find.text('Sale OFF-0001'), findsOneWidget);
      expect(find.textContaining('saved on this device'), findsOneWidget);
      expect(find.text('Total 11.60'), findsOneWidget);

      final queued = await tester.runAsync(() => store.saleQueue.pending());
      expect(queued!.single.draft.items.single.productName, 'Milk');
      expect(queued.single.draft.expectedTotal, 11.6);
      expect(server.posts('/sales'), isEmpty);

      await tester.tap(find.text('New sale'));
      await _settle(tester);
      expect(
        find.text('No items yet. Scan a product to start.'),
        findsOneWidget,
      );

      // The unit just sold is no longer available to sell again.
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, '6001');
      await tester.tap(find.byIcon(Icons.add).first);
      await _settle(tester);
      expect(find.textContaining('Only 2 of Milk in stock'), findsOneWidget);
    },
  );
}
