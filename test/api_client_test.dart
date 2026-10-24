import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kantemba/core/api/api_client.dart';
import 'package:kantemba/core/api/api_exception.dart';
import 'package:kantemba/data/models/auth_models.dart';
import 'package:kantemba/data/models/catalog_models.dart';
import 'package:kantemba/data/models/sale_models.dart';

ApiClient _client(
  http.Client http, {
  String? token = 'abc',
  void Function()? onUnauthorized,
}) =>
    ApiClient(
      baseUrl: 'http://example.test/api/v1/',
      tokenProvider: () async => token,
      onUnauthorized: onUnauthorized,
      httpClient: http,
    );

void main() {
  group('ApiClient', () {
    test('sends bearer token and decodes JSON', () async {
      late http.Request seen;
      final client = _client(MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'ok': true}), 200,
            headers: {'content-type': 'application/json'});
      }));

      final result = await client.get('/products', query: {'active': 'true'});

      expect(result, {'ok': true});
      expect(seen.url.toString(),
          'http://example.test/api/v1/products?active=true');
      expect(seen.headers['Authorization'], 'Bearer abc');
    });

    test('omits Authorization when there is no token', () async {
      late http.Request seen;
      final client = _client(
        MockClient((request) async {
          seen = request;
          return http.Response('', 204);
        }),
        token: null,
      );

      final result = await client.get('/categories');

      expect(result, isNull);
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('maps server error message and status', () async {
      final client = _client(MockClient((_) async =>
          http.Response(jsonEncode({'message': 'Stock too low'}), 409)));

      expect(
        () => client.post('/sales', body: {}),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'Stock too low')
            .having((e) => e.status, 'status', 409)),
      );
    });

    test('uses a generic message when the error body has none', () async {
      final client = _client(MockClient((_) async => http.Response('', 404)));

      expect(
        () => client.get('/products/9'),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'The requested item was not found.')),
      );
    });

    test('clears the session on 401 for protected calls', () async {
      var cleared = false;
      final client = _client(
        MockClient((_) async => http.Response('', 401)),
        onUnauthorized: () => cleared = true,
      );

      await expectLater(client.get('/sales'), throwsA(isA<ApiException>()));
      expect(cleared, isTrue);
    });

    test('reports unreachable server as ApiException', () async {
      final client = _client(MockClient((_) async {
        throw http.ClientException('connection refused');
      }));

      expect(() => client.get('/sales'), throwsA(isA<ApiException>()));
    });
  });

  group('models', () {
    test('AuthResponse parses roles and detects admin', () {
      final auth = AuthResponse.fromJson({
        'token': 't',
        'username': 'ann',
        'roles': ['CASHIER', 'ADMIN'],
      });
      expect(auth.username, 'ann');
      expect(auth.isAdmin, isTrue);
    });

    test('Product accepts numeric strings for money fields', () {
      final p = Product.fromJson({
        'id': 3,
        'name': 'Milk',
        'price': '12.50',
        'costPrice': 9,
        'stockQuantity': '4',
        'vatRate': null,
      });
      expect(p.price, 12.5);
      expect(p.costPrice, 9);
      expect(p.stockQuantity, 4);
      expect(p.vatRate, 0);
      expect(p.active, isTrue);
    });

    test('SaleItem computes remaining quantity after refunds', () {
      final item = SaleItem.fromJson({
        'id': 1,
        'productId': 2,
        'productName': 'Bread',
        'quantity': 5,
        'refundedQuantity': 2,
      });
      expect(item.remainingQuantity, 3);
    });

    test('Sale detects voided status and parses nested items', () {
      final sale = Sale.fromJson({
        'id': 7,
        'saleNumber': 'S-7',
        'saleStatus': 'VOIDED',
        'totalAmount': '30',
        'items': [
          {'id': 1, 'productId': 2, 'productName': 'A', 'quantity': 1}
        ],
        'payments': [],
      });
      expect(sale.isVoided, isTrue);
      expect(sale.totalAmount, 30);
      expect(sale.items.single.productName, 'A');
    });

    test('SaleItemInput and PaymentInput serialise to request JSON', () {
      expect(
        const SaleItemInput(productId: 1, quantity: 2).toJson(),
        {'productId': 1, 'quantity': 2, 'discountAmount': 0.0},
      );
      expect(
        const PaymentInput(paymentMethodId: 4, amount: 10).toJson(),
        {'paymentMethodId': 4, 'amount': 10.0},
      );
    });
  });
}
