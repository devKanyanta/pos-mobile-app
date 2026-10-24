import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/core/catalog/barcode_assignment.dart';
import 'package:kantemba/core/checkout/cart.dart';
import 'package:kantemba/core/checkout/checkout_service.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/data/services/pos_api.dart';
import 'package:kantemba/data/services/sales_api.dart';

import 'support/fakes.dart';

ApiClient _client(MockClient mock) => ApiClient(
  baseUrl: 'http://example.test/api/v1',
  tokenProvider: () async => 'token',
  httpClient: mock,
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _productJson(int id, String barcode) => {
  'id': id,
  'name': 'Item $id',
  'barcode': barcode,
  'price': 10.0,
  'stockQuantity': 5,
  'active': true,
  'vatRate': 16.0,
  'trackInventory': true,
};

Map<String, dynamic> _saleJson({String status = 'PAID', double change = 0}) => {
  'id': 7,
  'saleNumber': 'S-0007',
  'subtotal': 20.0,
  'vatAmount': 3.2,
  'totalAmount': 23.2,
  'amountPaid': 23.2,
  'balanceDue': 0.0,
  'changeGiven': change,
  'paymentStatus': status,
  'saleStatus': 'ACTIVE',
  'items': <Object>[],
  'payments': <Object>[],
};

void main() {
  group('PosApi.findByBarcode', () {
    test(
      'calls the lookup endpoint with the barcode and parses the product',
      () async {
        late http.Request seen;
        final api = PosApi(
          _client(
            MockClient((request) async {
              seen = request;
              return _json(_productJson(3, '6001234567890'));
            }),
          ),
        );

        final product = await api.findByBarcode('6001234567890');

        expect(seen.url.path, '/api/v1/products/by-barcode');
        expect(seen.url.queryParameters['barcode'], '6001234567890');
        expect(seen.headers['Authorization'], 'Bearer token');
        expect(product!.id, 3);
        expect(product.barcode, '6001234567890');
      },
    );

    test('an unknown barcode is null, not an error', () async {
      final api = PosApi(
        _client(
          MockClient(
            (_) async => _json({
              'status': 404,
              'message': 'No product found for barcode 0000',
            }, 404),
          ),
        ),
      );

      expect(await api.findByBarcode('0000'), isNull);
    });

    test('a 404 from a server without the endpoint is NOT treated as unknown barcode', () async {
      final api = PosApi(
        _client(
          MockClient(
            (_) async => _json({
              'status': 404,
              'message': 'No endpoint matches this path',
            }, 404),
          ),
        ),
      );

      expect(api.findByBarcode('6001'), throwsA(isA<ApiException>()));
    });

    test('permission and network failures surface as ApiException', () async {
      final forbidden = PosApi(
        _client(
          MockClient((_) async => _json({'message': 'Access Denied'}, 403)),
        ),
      );
      await expectLater(
        forbidden.findByBarcode('6001'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );

      final offline = PosApi(
        _client(MockClient((_) async => throw http.ClientException('down'))),
      );
      await expectLater(
        offline.findByBarcode('6001'),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
        ),
      );
    });
  });

  group('CheckoutService', () {
    Cart cartOf(List<(Product, int)> lines) {
      final cart = Cart();
      for (final (product, quantity) in lines) {
        cart.add(product, quantity: quantity);
      }
      return cart;
    }

    final cash = PaymentMethod(
      id: 1,
      name: 'Cash',
      code: 'CASH',
      isActive: true,
      type: 'CASH',
      requiresReference: false,
    );
    final momo = PaymentMethod(
      id: 2,
      name: 'MTN',
      code: 'MTN',
      isActive: true,
      type: 'MOBILE_MONEY',
      requiresReference: true,
    );

    test('sends items (id + barcode) and the tender in ONE request, without a client total', () async {
      final requests = <http.Request>[];
      final service = CheckoutService(
        SalesApi(
          _client(
            MockClient((request) async {
              requests.add(request);
              return _json(_saleJson(), 201);
            }),
          ),
        ),
        idGenerator: () => 'client-sale-0001',
      );

      final sale = await service.complete(
        cartOf([(testProduct(1, barcode: '6001'), 2)]),
        cash,
      );

      expect(requests.length, 1);
      expect(requests.single.url.path, '/api/v1/sales');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['clientSaleId'], 'client-sale-0001');
      expect(body['items'], [
        {
          'productId': 1,
          'quantity': 2,
          'discountAmount': 0.0,
          'barcode': '6001',
        },
      ]);
      expect(body['payments'], [
        {
          'paymentMethodId': 1,
        }, // no amount: the server settles the balance it calculated
      ]);
      expect(sale.totalAmount, 23.2); // server's number, not computed here
    });

    test('mobile money sends the confirmation code; cash can send the amount received', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = CheckoutService(
        SalesApi(
          _client(
            MockClient((request) async {
              bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              return _json(_saleJson(change: 6.8), 201);
            }),
          ),
        ),
      );
      final cart = cartOf([(testProduct(1), 1)]);

      await service.complete(cart, momo, reference: '  MM123456 ');
      await service.complete(cart, cash, amountReceived: 30);

      expect((bodies[0]['payments'] as List).single, {
        'paymentMethodId': 2,
        'transactionReference': 'MM123456',
      });
      expect((bodies[1]['payments'] as List).single, {
        'paymentMethodId': 1,
        'amount': 30.0,
      });
    });

    test('a retry after a failure reuses the same client sale id (no duplicate sale)', () async {
      final ids = <String>[];
      var calls = 0;
      final service = CheckoutService(
        SalesApi(
          _client(
            MockClient((request) async {
              ids.add(
                (jsonDecode(request.body) as Map)['clientSaleId'] as String,
              );
              calls++;
              if (calls == 1) throw http.ClientException('response lost');
              return _json(_saleJson(), 201);
            }),
          ),
        ),
      );
      final cart = cartOf([(testProduct(1), 1)]);

      await expectLater(
        service.complete(cart, cash),
        throwsA(isA<ApiException>()),
      );
      await service.complete(cart, cash);
      await service.complete(cart, cash); // a later, separate sale

      expect(ids[0], ids[1]);
      expect(ids[2], isNot(ids[0]));
    });

    test('changing the cart between attempts starts a new sale id', () async {
      final ids = <String>[];
      final service = CheckoutService(
        SalesApi(
          _client(
            MockClient((request) async {
              ids.add(
                (jsonDecode(request.body) as Map)['clientSaleId'] as String,
              );
              return _json({
                'message': 'Insufficient stock for product: Item 1',
              }, 400);
            }),
          ),
        ),
      );
      final cart = cartOf([(testProduct(1), 1)]);

      await expectLater(
        service.complete(cart, cash),
        throwsA(isA<ApiException>()),
      );
      cart.add(testProduct(2));
      await expectLater(
        service.complete(cart, cash),
        throwsA(isA<ApiException>()),
      );

      expect(ids[0], isNot(ids[1]));
    });

    test(
      'server rejections keep their message so the cashier sees why',
      () async {
        final service = CheckoutService(
          SalesApi(
            _client(
              MockClient(
                (_) async => _json({
                  'message': 'Insufficient stock for product: Milk. Available: 1, requested: 2',
                }, 400),
              ),
            ),
          ),
        );

        await expectLater(
          service.complete(cartOf([(testProduct(1), 2)]), cash),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Insufficient stock'),
            ),
          ),
        );
      },
    );

    test('an empty cart cannot be submitted', () {
      final service = CheckoutService(
        SalesApi(_client(MockClient((_) async => _json({})))),
      );
      expect(service.complete(Cart(), cash), throwsStateError);
    });
  });

  group('BarcodeAssignmentChecker', () {
    final lookup = FakeLookup([testProduct(1, barcode: '6001', name: 'Milk')]);
    final checker = BarcodeAssignmentChecker(lookup);

    test('blank means no barcode', () async {
      expect((await checker.check('  ')).status, BarcodeStatus.none);
    });

    test('malformed barcodes are rejected without asking the server', () async {
      lookup.requested.clear();
      final result = await checker.check('12 34');
      expect(result.status, BarcodeStatus.invalid);
      expect(result.blocksSaving, isTrue);
      expect(lookup.requested, isEmpty);
    });

    test(
      'a free barcode is available (and returned in canonical form)',
      () async {
        final result = await checker.check(' abc123 ');
        expect(result.status, BarcodeStatus.available);
        expect(result.code, 'ABC123');
      },
    );

    test(
      'a barcode used by another product is reported with that product',
      () async {
        final result = await checker.check('6001');
        expect(result.status, BarcodeStatus.taken);
        expect(result.owner!.name, 'Milk');
        expect(result.blocksSaving, isTrue);
        expect(result.message, contains('Milk'));
      },
    );

    test('a product may keep its own barcode when editing', () async {
      final result = await checker.check('6001', editingProductId: 1);
      expect(result.status, BarcodeStatus.available);
    });

    test(
      'when the server cannot be reached the check is unverified, not blocking',
      () async {
        final offline = FakeLookup([])
          ..failWith = const ApiException('Cannot reach the server.');
        final result = await BarcodeAssignmentChecker(offline).check('6002');
        expect(result.status, BarcodeStatus.unverified);
        expect(result.blocksSaving, isFalse);
      },
    );
  });
}
