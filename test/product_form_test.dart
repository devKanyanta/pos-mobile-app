import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/ui/product_form_screen.dart';

import 'support/fake_server.dart';

Future<FakeServer> _pumpForm(
  WidgetTester tester, {
  String role = 'MANAGER',
  Product? product,
}) async {
  final server = FakeServer(role: role)
    ..products['6001'] = productJson(1, '6001', name: 'Fresh Milk', stock: 12);
  final session = await server.signedInSession();
  await tester.pumpWidget(
    SessionScope(
      session: session,
      child: MaterialApp(home: ProductFormScreen(product: product)),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _fill(WidgetTester tester, {required String barcode}) async {
  await tester.enterText(_field('Name'), 'Brown Bread');
  await tester.enterText(_field('Barcode (optional)'), barcode);
  await tester.enterText(_field('Price (ex VAT)'), '18');
  await tester.pump();
}

void main() {
  testWidgets('a new product is saved with its (canonical) barcode', (
    tester,
  ) async {
    final server = await _pumpForm(tester);

    await _fill(tester, barcode: ' new-123 ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final posts = server.posts('/products').toList();
    expect(posts.length, 1);
    final body = server.bodyOf(posts.single);
    expect(body['barcode'], 'NEW-123');
    expect(body['name'], 'Brown Bread');
  });

  testWidgets('a product can be saved without a barcode', (tester) async {
    final server = await _pumpForm(tester);

    await _fill(tester, barcode: '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = server.bodyOf(server.posts('/products').single);
    expect(body.containsKey('barcode'), isFalse);
  });

  testWidgets(
    'a barcode that already exists never creates a duplicate product',
    (tester) async {
      final server = await _pumpForm(tester);

      await _fill(tester, barcode: '6001');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Barcode already in use'), findsOneWidget);
      expect(
        find.textContaining('Fresh Milk already has barcode 6001'),
        findsOneWidget,
      );
      expect(server.posts('/products'), isEmpty);

      // Managers are guided to the existing product or to adding stock.
      expect(find.text('Open product'), findsOneWidget);
      expect(find.text('Add stock'), findsOneWidget);

      await tester.tap(find.text('Use another barcode'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_field('Barcode (optional)')).controller!.text,
        isEmpty,
      );
      expect(server.posts('/products'), isEmpty);
    },
  );

  testWidgets('an existing barcode can be turned into a stock entry instead', (
    tester,
  ) async {
    final server = await _pumpForm(tester);

    await _fill(tester, barcode: '6001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();

    expect(find.text('Add stock: Fresh Milk'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Units received'),
      '24',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final restock = server.posts('/inventory-movements/restock').single;
    expect(server.bodyOf(restock), containsPair('productId', 1));
    expect(server.bodyOf(restock), containsPair('quantity', 24));
    expect(server.posts('/products'), isEmpty); // still no duplicate product
  });

  testWidgets('a cashier is not offered stock or product management', (
    tester,
  ) async {
    await _pumpForm(tester, role: 'CASHIER');

    await _fill(tester, barcode: '6001');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Barcode already in use'), findsOneWidget);
    expect(find.text('Add stock'), findsNothing);
    expect(find.text('Open product'), findsNothing);
    expect(find.text('Use another barcode'), findsOneWidget);
  });

  testWidgets('a malformed barcode is rejected before anything is sent', (
    tester,
  ) async {
    final server = await _pumpForm(tester);

    await _fill(tester, barcode: 'has space');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no spaces'), findsWidgets);
    expect(server.posts('/products'), isEmpty);
    expect(
      server.requests.where((r) => r.url.path.endsWith('/by-barcode')),
      isEmpty,
    );
  });

  testWidgets(
    'editing a product keeps its own barcode without a false duplicate',
    (tester) async {
      final server = FakeServer(role: 'MANAGER')
        ..products['6001'] = productJson(1, '6001', name: 'Fresh Milk');
      final session = await server.signedInSession();
      final product = Product.fromJson(
        productJson(1, '6001', name: 'Fresh Milk'),
      );
      await tester.pumpWidget(
        SessionScope(
          session: session,
          child: MaterialApp(home: ProductFormScreen(product: product)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byIcon(Icons.qr_code_scanner).first,
        warnIfMissed: false,
      );
      // (the scanner page is not opened in tests; just confirm the field shows the barcode)
      expect(
        tester.widget<TextField>(_field('Barcode (optional)')).controller!.text,
        '6001',
      );
      expect(find.text('Barcode already in use'), findsNothing);
    },
  );
}
