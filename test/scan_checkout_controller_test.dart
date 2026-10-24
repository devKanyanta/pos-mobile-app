import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/core/checkout/scan_checkout_controller.dart';
import 'package:kantemba/core/scanning/scan_deduplicator.dart';

import 'support/fakes.dart';

void main() {
  late FakeLookup lookup;
  late DateTime now;
  late ScanCheckoutController scan;

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    lookup = FakeLookup([
      testProduct(
        1,
        barcode: '6001',
        price: 10,
        vat: 16,
        stock: 5,
        name: 'Milk',
      ),
      testProduct(
        2,
        barcode: '6002',
        price: 20,
        vat: 0,
        stock: 50,
        name: 'Bread',
      ),
      testProduct(
        3,
        barcode: '6003',
        stock: 10,
        active: false,
        name: 'Retired',
      ),
      testProduct(4, barcode: '6004', stock: 0, name: 'Empty shelf'),
      testProduct(5, barcode: '6005', stock: 0, track: false, name: 'Service'),
    ]);
    scan = ScanCheckoutController(
      lookup: lookup,
      deduplicator: ScanDeduplicator(),
      clock: () => now,
    );
  });

  tearDown(() => scan.dispose());

  /// Lets the controller finish its queued lookups.
  Future<void> settle() => pumpEventQueue();

  test(
    'a scanned barcode is looked up on the server and added to the cart',
    () async {
      scan.onDetected('6001');
      await settle();

      expect(lookup.requested, ['6001']);
      expect(scan.cart.quantityOf(1), 1);
      expect(scan.feedback!.outcome, ScanOutcome.added);
      expect(scan.feedback!.message, contains('Milk'));
      expect(
        scan.cart.lines.single.product.price,
        10,
      ); // server data, not device data
    },
  );

  test('scanning the same product again after the code left view adds another unit', () async {
    scan.onDetected('6001');
    await settle();

    now = now.add(const Duration(seconds: 3)); // lifted away, then shown again
    scan.onDetected('6001');
    await settle();

    expect(scan.cart.quantityOf(1), 2);
    expect(scan.cart.lines.length, 1);
  });

  test('repeated camera frames of one code add it only once', () async {
    for (var i = 0; i < 8; i++) {
      scan.onDetected('6001');
      now = now.add(const Duration(milliseconds: 250)); // camera still sees it
    }
    await settle();

    expect(scan.cart.quantityOf(1), 1);
    expect(lookup.requested.length, 1); // no needless network requests either
  });

  test('different products scanned quickly are all added, in order', () async {
    final release = Completer<void>();
    lookup.gate = release.future; // lookups stay in flight

    scan.onDetected('6001');
    scan.onDetected('6002');
    scan.onDetected('6001');
    await settle();
    expect(scan.busy, isTrue);
    expect(lookup.requested, ['6001']); // one at a time

    release.complete();
    await settle();

    expect(lookup.requested, ['6001', '6002', '6001']);
    expect(scan.cart.quantityOf(1), 2);
    expect(scan.cart.quantityOf(2), 1);
    expect(scan.busy, isFalse);
  });

  test('an unknown barcode is reported and the cart is untouched', () async {
    scan.onDetected('9999');
    await settle();

    expect(scan.cart.isEmpty, isTrue);
    expect(scan.feedback!.outcome, ScanOutcome.unknown);
    expect(scan.feedback!.message, contains('9999'));
    expect(scan.feedback!.isError, isTrue);
  });

  test(
    'a network failure is reported clearly and scanning keeps working',
    () async {
      lookup.failWith = const ApiException('Cannot reach the server.');
      scan.onDetected('6001');
      await settle();

      expect(scan.feedback!.outcome, ScanOutcome.failed);
      expect(scan.feedback!.message, contains('No connection'));
      expect(scan.cart.isEmpty, isTrue);

      lookup.failWith = null; // the network is back
      now = now.add(const Duration(seconds: 3));
      scan.onDetected('6001');
      await settle();
      expect(scan.cart.quantityOf(1), 1);
    },
  );

  test(
    'server errors such as permission problems show the server message',
    () async {
      lookup.failWith = const ApiException(
        'You do not have permission to do this.',
        status: 403,
      );
      scan.onDetected('6001');
      await settle();

      expect(scan.feedback!.message, 'You do not have permission to do this.');
    },
  );

  test('inactive products cannot be sold', () async {
    scan.onDetected('6003');
    await settle();

    expect(scan.cart.isEmpty, isTrue);
    expect(scan.feedback!.outcome, ScanOutcome.inactive);
  });

  test('stock limits are respected for scans and the plus button', () async {
    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(seconds: 3));
      scan.onDetected('6001');
      await settle();
    }
    expect(scan.cart.quantityOf(1), 5); // all the stock

    now = now.add(const Duration(seconds: 3));
    scan.onDetected('6001');
    await settle();
    expect(scan.cart.quantityOf(1), 5);
    expect(scan.feedback!.outcome, ScanOutcome.outOfStock);
    expect(scan.feedback!.message, contains('Only 5'));

    expect(scan.increment(1).outcome, ScanOutcome.outOfStock);
    expect(scan.cart.quantityOf(1), 5);
  });

  test('out-of-stock and untracked products', () async {
    scan.onDetected('6004');
    await settle();
    expect(scan.feedback!.message, contains('out of stock'));
    expect(scan.cart.isEmpty, isTrue);

    now = now.add(const Duration(seconds: 3));
    scan.onDetected('6005'); // stock not tracked: always sellable
    await settle();
    expect(scan.cart.quantityOf(5), 1);
  });

  test(
    'manual entry always adds, even for the same code twice in a row',
    () async {
      await scan.addByBarcode(' 6002 ');
      await scan.addByBarcode('6002');

      expect(scan.cart.quantityOf(2), 2);
      expect(lookup.requested, ['6002', '6002']); // trimmed before lookup
    },
  );

  test(
    'blank manual entry and unreadable codes never reach the server',
    () async {
      expect((await scan.addByBarcode('   ')).outcome, ScanOutcome.invalid);
      expect(
        (await scan.addByBarcode('has space')).outcome,
        ScanOutcome.invalid,
      );
      expect(lookup.requested, isEmpty);
    },
  );

  test('quantity buttons adjust and remove lines', () async {
    await scan.addByBarcode('6002');
    scan.increment(2);
    expect(scan.cart.quantityOf(2), 2);

    scan.decrement(2);
    scan.decrement(2);
    expect(scan.cart.isEmpty, isTrue);

    await scan.addByBarcode('6002');
    scan.remove(2);
    expect(scan.cart.isEmpty, isTrue);
  });

  test(
    'a newer lookup refreshes the price of an item already in the cart',
    () async {
      await scan.addByBarcode('6002');
      final updated = FakeLookup([
        testProduct(2, barcode: '6002', price: 25, vat: 0, name: 'Bread'),
      ]);
      final fresh = ScanCheckoutController(lookup: updated, cart: scan.cart);

      await fresh.addByBarcode('6002');

      expect(scan.cart.quantityOf(2), 2);
      expect(scan.cart.lines.single.product.price, 25);
      fresh.dispose();
    },
  );

  test(
    'clear empties the cart and lets the same code be scanned right away',
    () async {
      scan.onDetected('6001');
      await settle();
      scan.clear();
      expect(scan.cart.isEmpty, isTrue);

      scan.onDetected('6001'); // same instant, but the sale was cleared
      await settle();
      expect(scan.cart.quantityOf(1), 1);
    },
  );
}
