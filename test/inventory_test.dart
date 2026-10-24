import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/session/session_scope.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/ui/inventory_history_screen.dart';
import 'package:kantemba/ui/product_actions.dart';

import 'support/fake_server.dart';

Future<FakeServer> _pumpAdjust(WidgetTester tester, {int stock = 5}) async {
  final server = FakeServer(role: 'MANAGER');
  final session = await server.signedInSession();
  final product = Product.fromJson(
    productJson(1, '6001', name: 'Milk', stock: stock),
  );
  await tester.pumpWidget(
    SessionScope(
      session: session,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAdjustmentDialog(context, product),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  testWidgets('a zero adjustment is rejected without calling the server', (
    tester,
  ) async {
    final server = await _pumpAdjust(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Change (use - to reduce)'),
      '0',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Count');
    await tester.tap(find.text('Save adjustment'));
    await tester.pump();

    expect(find.textContaining('not zero'), findsOneWidget);
    expect(server.posts('/inventory-movements/adjustment'), isEmpty);
  });

  testWidgets('an adjustment without a reason is rejected', (tester) async {
    final server = await _pumpAdjust(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Change (use - to reduce)'),
      '2',
    );
    await tester.tap(find.text('Save adjustment'));
    await tester.pump();

    expect(find.text('Enter a reason for the adjustment.'), findsOneWidget);
    expect(server.posts('/inventory-movements/adjustment'), isEmpty);
  });

  testWidgets('a reduction below zero stock is blocked locally', (
    tester,
  ) async {
    final server = await _pumpAdjust(tester, stock: 5);
    await tester.enterText(
      find.widgetWithText(TextField, 'Change (use - to reduce)'),
      '-6',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Breakage',
    );
    await tester.tap(find.text('Save adjustment'));
    await tester.pump();

    expect(find.textContaining('cannot go below zero'), findsOneWidget);
    expect(server.posts('/inventory-movements/adjustment'), isEmpty);
  });

  testWidgets(
    'a valid adjustment is posted with its signed quantity and reason',
    (tester) async {
      final server = await _pumpAdjust(tester, stock: 5);
      await tester.enterText(
        find.widgetWithText(TextField, 'Change (use - to reduce)'),
        '-2',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Damaged',
      );
      await tester.tap(find.text('Save adjustment'));
      await tester.pumpAndSettle();

      final posts = server.posts('/inventory-movements/adjustment').toList();
      expect(posts.length, 1);
      final body = server.bodyOf(posts.single);
      expect(body['productId'], 1);
      expect(body['quantity'], -2);
      expect(body['reason'], 'Damaged');
    },
  );

  testWidgets('a server rejection is shown and nothing is reported as saved', (
    tester,
  ) async {
    final server = FakeServer(role: 'MANAGER')
      ..adjustmentError = 'Stock cannot be negative';
    final session = await server.signedInSession();
    final product = Product.fromJson(productJson(1, '6001', stock: 5));
    await tester.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdjustmentDialog(context, product),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Change (use - to reduce)'),
      '1',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Count');
    await tester.tap(find.text('Save adjustment'));
    await tester.pumpAndSettle();

    expect(find.text('Stock cannot be negative'), findsOneWidget);
    expect(find.textContaining('Adjusted Milk'), findsNothing);
  });

  testWidgets('history lists movements returned by the server', (tester) async {
    final server = FakeServer(role: 'MANAGER')
      ..movements = [
        {
          'id': 1,
          'productName': 'Milk',
          'movementType': 'RESTOCK',
          'quantity': 12,
          'notes': 'Delivery',
          'performedBy': 'tester',
          'createdAt': '2026-10-20T08:00:00Z',
        },
        {
          'id': 2,
          'productName': 'Milk',
          'movementType': 'ADJUSTMENT',
          'quantity': -2,
          'createdAt': '2026-10-21T08:00:00Z',
        },
      ];
    final session = await server.signedInSession();
    await tester.pumpWidget(
      SessionScope(
        session: session,
        child: const MaterialApp(home: InventoryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Received · Milk'), findsOneWidget);
    expect(find.text('Adjustment · Milk'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    expect(server.requests.last.url.path, '/api/v1/inventory-movements');
  });

  testWidgets('a single product history calls the per-product endpoint', (
    tester,
  ) async {
    final server = FakeServer(role: 'MANAGER');
    final session = await server.signedInSession();
    final product = Product.fromJson(productJson(7, '6001', name: 'Milk'));
    await tester.pumpWidget(
      SessionScope(
        session: session,
        child: MaterialApp(home: InventoryHistoryScreen(product: product)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No stock movements recorded yet.'), findsOneWidget);
    expect(
      server.requests.last.url.path,
      '/api/v1/inventory-movements/product/7',
    );
  });

  testWidgets('history does not show an empty state when the request fails', (
    tester,
  ) async {
    final server = FakeServer(role: 'MANAGER');
    final session = await server.signedInSession();
    server.offline = true;
    await tester.pumpWidget(
      SessionScope(
        session: session,
        child: const MaterialApp(home: InventoryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No stock movements recorded yet.'), findsNothing);
  });
}
