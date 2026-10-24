import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/ui/checkout_screen.dart';

import 'support/fake_server.dart';

/// The camera cannot run in tests, so the screen is shown with its scanner
/// paused (`active: false`) and barcodes arrive through manual entry, which
/// uses exactly the same lookup/cart/checkout path as the camera.
Future<FakeServer> _pumpCheckout(WidgetTester tester) async {
  final server = FakeServer()
    ..products['6001'] = productJson(
      1,
      '6001',
      name: 'Milk',
      price: 10,
      stock: 3,
    )
    ..products['6002'] = productJson(
      2,
      '6002',
      name: 'Old stock',
      stock: 4,
      active: false,
    );
  final session = await server.signedInSession();
  await tester.pumpWidget(
    SessionScope(
      session: session,
      child: const MaterialApp(home: CheckoutScreen(active: false)),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.tap(find.byIcon(Icons.add).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the camera is not opened while the Sales tab is hidden', (
    tester,
  ) async {
    await _pumpCheckout(tester);
    expect(find.text('Scanner paused'), findsOneWidget);
  });

  testWidgets('a barcode is looked up on the server and added to the cart', (
    tester,
  ) async {
    final server = await _pumpCheckout(tester);

    await _enter(tester, '6001');

    expect(
      server.requests
          .where((r) => r.url.path.endsWith('/products/by-barcode'))
          .length,
      1,
    );
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Total 11.60'), findsOneWidget);
    expect(find.textContaining('Added Milk'), findsOneWidget);
    // The whole catalogue is never downloaded just to scan.
    expect(
      server.requests.where((r) => r.url.path == '/api/v1/products'),
      isEmpty,
    );
  });

  testWidgets(
    'scanning the same product again raises the quantity, up to the stock',
    (tester) async {
      await _pumpCheckout(tester);

      await _enter(tester, '6001');
      await _enter(tester, '6001');
      await _enter(tester, '6001');
      expect(find.text('3'), findsOneWidget);

      await _enter(tester, '6001'); // only 3 in stock
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('Only 3 of Milk in stock'), findsOneWidget);
    },
  );

  testWidgets('unknown barcodes and unavailable products are explained', (
    tester,
  ) async {
    await _pumpCheckout(tester);

    await _enter(tester, '9999');
    expect(find.textContaining('Unknown barcode 9999'), findsOneWidget);

    await _enter(tester, '6002');
    expect(find.textContaining('not available for sale'), findsOneWidget);
    expect(find.text('No items yet. Scan a product to start.'), findsOneWidget);
  });

  testWidgets('a lost connection is reported and the cart survives', (
    tester,
  ) async {
    final server = await _pumpCheckout(tester);
    await _enter(tester, '6001');

    server.offline = true;
    await tester.enterText(find.byType(TextField).first, '6001');
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('No connection to the server'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
  });

  testWidgets(
    'paying sends items and tender in one request and shows the server total',
    (tester) async {
      final server = await _pumpCheckout(tester);
      await _enter(tester, '6001');

      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue')); // exact cash
      await tester.pumpAndSettle();

      final sales = server.posts('/sales').toList();
      expect(sales.length, 1);
      final body = server.bodyOf(sales.single);
      expect((body['items'] as List).single, containsPair('barcode', '6001'));
      expect((body['items'] as List).single, containsPair('productId', 1));
      expect((body['payments'] as List).single, {'paymentMethodId': 1});
      expect(body['clientSaleId'], isNotEmpty);

      expect(find.text('Sale complete'), findsOneWidget);
      expect(find.text('Sale S-0007'), findsOneWidget);
      expect(
        find.text('Total 11.60'),
        findsOneWidget,
      ); // from the server response

      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();
      expect(
        find.text('No items yet. Scan a product to start.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('mobile money asks for the confirmation code', (tester) async {
    final server = await _pumpCheckout(tester);
    await _enter(tester, '6001');

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MTN Mobile Money'));
    await tester.pumpAndSettle();
    expect(find.text('MTN Mobile Money confirmation code'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'MM998877');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final payment =
        (server.bodyOf(server.posts('/sales').single)['payments'] as List)
            .single;
    expect(payment, {'paymentMethodId': 2, 'transactionReference': 'MM998877'});
  });
}
