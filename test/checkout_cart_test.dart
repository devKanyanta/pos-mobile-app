import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/checkout/cart.dart';
import 'package:kantemba/core/scanning/scan_deduplicator.dart';
import 'package:kantemba/data/models/catalog_models.dart';

Product _product(int id, {double price = 10, double vat = 0}) => Product(
  id: id,
  name: 'Item $id',
  barcode: '000$id',
  sku: null,
  price: price,
  costPrice: 0,
  stockQuantity: 100,
  active: true,
  vatRate: vat,
  trackInventory: false,
  categoryId: null,
  categoryName: null,
  reorderLevel: null,
  lowStock: false,
  zraTaxType: null,
  zraItemCode: null,
  zraItemClassCode: null,
  zraItemTypeCode: null,
  zraOriginCountryCode: null,
  zraPackagingUnitCode: null,
  zraQuantityUnitCode: null,
  zraMapped: false,
  zraRegistered: false,
);

void main() {
  group('Cart', () {
    test('adding the same product increases its quantity', () {
      final cart = Cart();
      final p = _product(1);
      cart.add(p);
      cart.add(p);
      expect(cart.quantityOf(1), 2);
      expect(cart.lines.length, 1);
      expect(cart.itemCount, 2);
    });

    test('total includes VAT and quantity', () {
      final cart = Cart();
      cart.add(_product(1, price: 10, vat: 16), quantity: 2);
      cart.add(_product(2, price: 5, vat: 0));
      expect(cart.total, closeTo(10 * 1.16 * 2 + 5, 1e-9));
    });

    test('setQuantity to zero or less removes the line', () {
      final cart = Cart();
      cart.add(_product(1));
      cart.setQuantity(1, 0);
      expect(cart.isEmpty, isTrue);
      expect(cart.total, 0);
    });

    test('setQuantity updates the line and the total', () {
      final cart = Cart();
      cart.add(_product(1, price: 4));
      cart.setQuantity(1, 3);
      expect(cart.total, closeTo(12, 1e-9));
    });

    test('remove and clear empty the cart', () {
      final cart = Cart();
      cart.add(_product(1));
      cart.add(_product(2));
      cart.remove(1);
      expect(cart.quantityOf(1), 0);
      cart.clear();
      expect(cart.isEmpty, isTrue);
    });
  });

  group('ScanDeduplicator', () {
    final t0 = DateTime(2026, 10, 24, 9);

    test('repeated detections of a held barcode are ignored', () {
      final d = ScanDeduplicator();
      expect(d.accept('111', t0), isTrue);
      expect(
        d.accept('111', t0.add(const Duration(milliseconds: 100))),
        isFalse,
      );
      expect(
        d.accept('111', t0.add(const Duration(milliseconds: 900))),
        isFalse,
      );
    });

    test('a deliberate re-scan after a pause is accepted again', () {
      final d = ScanDeduplicator();
      expect(d.accept('111', t0), isTrue);
      // Still seen 900 ms later (held); then the camera loses it for 2 s.
      expect(
        d.accept('111', t0.add(const Duration(milliseconds: 900))),
        isFalse,
      );
      expect(d.accept('111', t0.add(const Duration(seconds: 3))), isTrue);
    });

    test('a different barcode is accepted immediately', () {
      final d = ScanDeduplicator();
      expect(d.accept('111', t0), isTrue);
      expect(d.accept('222', t0.add(const Duration(milliseconds: 50))), isTrue);
    });

    test('reset allows the same barcode immediately', () {
      final d = ScanDeduplicator();
      expect(d.accept('111', t0), isTrue);
      d.reset();
      expect(d.accept('111', t0.add(const Duration(milliseconds: 10))), isTrue);
    });
  });
}
