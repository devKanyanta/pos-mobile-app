import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kantemba/core/api/token_store.dart';
import 'package:kantemba/core/session/session.dart';

/// Token store that never touches the platform keystore.
class MemoryTokenStore extends TokenStore {
  String? _token;
  String? _username;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<String?> readUsername() async => _username;

  @override
  Future<void> save({required String token, required String username}) async {
    _token = token;
    _username = username;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _username = null;
  }
}

/// A tiny fake of the POS backend for widget tests.
class FakeServer {
  FakeServer({this.role = 'CASHIER'});

  final String role;

  /// Products the barcode endpoint knows, keyed by canonical barcode.
  final Map<String, Map<String, dynamic>> products = {};

  /// Every request received, in order.
  final List<http.Request> requests = [];

  /// When true, every call fails like an unreachable server.
  bool offline = false;

  /// When set, adjustment requests fail with this server message.
  String? adjustmentError;

  /// When set, device registration fails with this server message (503).
  String? deviceRegisterError;

  /// What `GET /sync/catalog` knows. A pull without `since` returns all of
  /// [catalogProducts]; a pull with it returns only those whose id is in
  /// [catalogChangedIds]. `productIds` is always every id.
  final Map<int, Map<String, dynamic>> catalogProducts = {};
  final Set<int> catalogChangedIds = {};
  String catalogServerTime = '2026-11-12T10:00:00.123456';

  /// When true, `GET /sync/catalog` fails with a 500.
  bool catalogFails = false;

  /// When true, `GET /products/by-barcode` fails with a 500.
  bool barcodeFails = false;

  /// `GET /merchant` answer; null makes the endpoint fail with 404.
  Map<String, dynamic>? merchant;

  /// `GET /receipts/sale/{id}` answer; null makes the endpoint fail with 404.
  Map<String, dynamic>? receipt;

  /// Customers returned by `GET /customers`.
  List<Map<String, dynamic>> customers = [];

  /// Movement rows returned by the history endpoints.
  List<Map<String, dynamic>> movements = [];

  Map<String, dynamic> saleResponse = {
    'id': 7,
    'saleNumber': 'S-0007',
    'subtotal': 10.0,
    'vatAmount': 1.6,
    'totalAmount': 11.6,
    'amountPaid': 11.6,
    'balanceDue': 0.0,
    'changeGiven': 0.0,
    'paymentStatus': 'PAID',
    'saleStatus': 'ACTIVE',
    'items': <Object>[],
    'payments': <Object>[],
  };

  Iterable<http.Request> posts(String path) =>
      requests.where((r) => r.method == 'POST' && r.url.path == '/api/v1$path');

  Map<String, dynamic> bodyOf(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    requests.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');

    if (path == '/sync/devices/register' && request.method == 'POST') {
      if (deviceRegisterError != null) {
        return _json({'message': deviceRegisterError}, 503);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'id': 1,
        'deviceId': body['deviceId'],
        'name': body['name'],
        'model': body['model'],
        'appVersion': body['appVersion'],
        'active': true,
        'pendingQueueSize': 0,
      });
    }
    if (path == '/sync/catalog' && request.method == 'GET') {
      if (catalogFails) return _json({'message': 'boom'}, 500);
      final since = request.url.queryParameters['since'];
      final sent = since == null
          ? catalogProducts.values.toList()
          : [
              for (final id in catalogChangedIds)
                if (catalogProducts[id] != null) catalogProducts[id]!,
            ];
      return _json({
        'serverTime': catalogServerTime,
        'full': since == null,
        'products': sent,
        'categories': [
          {'id': 1, 'name': 'Groceries'},
        ],
        'paymentMethods': [
          {
            'id': 1,
            'name': 'Cash',
            'code': 'CASH',
            'isActive': true,
            'type': 'CASH',
            'requiresReference': false,
          },
        ],
        'productIds': catalogProducts.keys.toList(),
      });
    }
    if (path == '/auth/login') {
      return _json({
        'token': 't',
        'username': 'tester',
        'roles': [role],
      });
    }
    if (path == '/merchant' && request.method == 'GET') {
      return merchant == null
          ? _json({'message': 'No merchant profile'}, 404)
          : _json(merchant!);
    }
    if (path.startsWith('/receipts/sale/')) {
      return receipt == null
          ? _json({'message': 'No receipt'}, 404)
          : _json(receipt!);
    }
    if (path == '/customers' && request.method == 'GET') {
      return _json(customers);
    }
    if (path == '/payment-methods') {
      return _json([
        {
          'id': 1,
          'name': 'Cash',
          'code': 'CASH',
          'isActive': true,
          'type': 'CASH',
          'requiresReference': false,
        },
        {
          'id': 2,
          'name': 'MTN Mobile Money',
          'code': 'MTN',
          'isActive': true,
          'type': 'MOBILE_MONEY',
          'requiresReference': true,
        },
      ]);
    }
    if (path == '/products/by-barcode') {
      if (barcodeFails) return _json({'message': 'boom'}, 500);
      final product = products[request.url.queryParameters['barcode']];
      return product != null
          ? _json(product)
          : _json({
              'status': 404,
              'message':
                  'No product found for barcode ${request.url.queryParameters['barcode']}',
            }, 404);
    }
    if (path == '/products' && request.method == 'GET') {
      return _json(products.values.toList());
    }
    if (path == '/products' && request.method == 'POST') {
      return _json({
        ...jsonDecode(request.body) as Map<String, dynamic>,
        'id': 99,
      }, 201);
    }
    if (path == '/inventory-movements/restock' && request.method == 'POST') {
      return _json({'id': 1, 'movementType': 'RESTOCK'}, 201);
    }
    if (path == '/inventory-movements/adjustment' && request.method == 'POST') {
      if (adjustmentError != null) {
        return _json({'message': adjustmentError}, 400);
      }
      return _json({'id': 2, 'movementType': 'ADJUSTMENT'}, 201);
    }
    if (path == '/inventory-movements' ||
        path.startsWith('/inventory-movements/product/')) {
      return _json(movements);
    }
    if (path == '/sales' && request.method == 'POST') {
      return _json(saleResponse, 201);
    }
    return _json({'message': 'No endpoint matches this path'}, 404);
  }

  MockClient get client => MockClient(_handle);

  /// A session signed in as [role] that talks to this fake.
  Future<Session> signedInSession() async {
    final session = Session(tokenStore: MemoryTokenStore(), httpClient: client);
    await session.signIn(username: 'tester', password: 'secret');
    requests.clear();
    return session;
  }
}

Map<String, dynamic> productJson(
  int id,
  String barcode, {
  String name = 'Milk',
  double price = 10,
  int stock = 5,
  bool active = true,
}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'price': price,
  'stockQuantity': stock,
  'active': active,
  'vatRate': 16.0,
  'trackInventory': true,
};

/// A product as `GET /sync/catalog` sends it.
Map<String, dynamic> catalogItemJson(
  int id,
  String name, {
  String? barcode,
  double price = 10,
  int stock = 5,
  bool active = true,
  int? categoryId,
}) => {
  'id': id,
  'name': name,
  'barcode': barcode,
  'price': price,
  'vatRate': 16.0,
  'zraTaxType': 'A',
  'trackInventory': true,
  'stockQuantity': stock,
  'active': active,
  'categoryId': categoryId,
};
