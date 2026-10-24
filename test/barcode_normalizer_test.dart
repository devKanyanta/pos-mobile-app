import 'package:flutter_test/flutter_test.dart';

import 'package:kantemba/core/scanning/barcode_normalizer.dart';

void main() {
  group('BarcodeNormalizer', () {
    test('canonical trims and upper-cases, blank is null', () {
      expect(BarcodeNormalizer.canonical('  abc-123 '), 'ABC-123');
      expect(BarcodeNormalizer.canonical('   '), isNull);
      expect(BarcodeNormalizer.canonical(null), isNull);
    });

    test('accepts common retail barcodes', () {
      for (final code in [
        '6001234567890',
        '12345670',
        '012345678905',
        'ITEM_1/A+2',
        '123',
      ]) {
        expect(BarcodeNormalizer.validate(code), isNull, reason: code);
        expect(BarcodeNormalizer.isValid(code), isTrue, reason: code);
      }
    });

    test('rejects values the backend would refuse', () {
      for (final code in ['12', '12 34', '12#34', '6.00123E+12', 'x' * 65]) {
        expect(BarcodeNormalizer.validate(code), isNotNull, reason: code);
        expect(
          BarcodeNormalizer.isValid(BarcodeNormalizer.canonical(code)),
          isFalse,
          reason: code,
        );
      }
    });

    test('blank input is not an error (the product just has no barcode)', () {
      expect(BarcodeNormalizer.validate(''), isNull);
      expect(BarcodeNormalizer.validate(null), isNull);
    });
  });
}
